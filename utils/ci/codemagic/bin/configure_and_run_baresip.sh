#!/bin/bash
set -e # Ensures the script exits if any commands fail to execute

# Port baresip's ctrl_tcp module listens on, keep in sync with the port in
# integration_test/utils/baresip_client.dart.
BARESIP_CTRL_PORT=4444

CONFIG=~/.baresip/config

# In-place sed that works with both the BSD sed on macOS and the GNU sed on the
# Linux build machines: only the `-i<suffix>` form (no separate argument) is
# accepted by both, so edit with a suffix and drop the backup afterwards.
patch_config() {
    sed -i.bak "$1" "$CONFIG"
    rm -f "$CONFIG.bak"
}

if ! command -v baresip > /dev/null 2>&1; then
    if command -v brew > /dev/null 2>&1; then
        brew install baresip
    else
        # Codemagic's Linux build machines run unattended-upgrades at boot, which
        # holds the dpkg lock for the first minute of the build; wait for it
        # instead of failing.
        sudo apt-get -o DPkg::Lock::Timeout=300 install -y baresip
    fi

    # Run it once briefly to generate the default configuration files, then close it
    (sleep 5; echo "/quit") | baresip
fi

# Add a SIP account that will make the call, unless it is already configured
sip_account="<sip:${INTEGRATION_TEST_SIP_USER}@sip.encryptedsip.com:5061;transport=tls>;regint=3600;auth_pass=${INTEGRATION_TEST_SIP_PASS};mediaenc=srtp-mand"
if grep -qF "${sip_account}" ~/.baresip/accounts 2>/dev/null; then
    echo "📋 SIP account for ${INTEGRATION_TEST_SIP_USER} already in ~/.baresip/accounts"
else
    # Drop any stale entry for this user (for example after a password change)
    if [ -f ~/.baresip/accounts ]; then
        sed -i.bak "/^<sip:${INTEGRATION_TEST_SIP_USER}@sip\.encryptedsip\.com/d" ~/.baresip/accounts
        rm -f ~/.baresip/accounts.bak
    fi
    echo "${sip_account}" >> ~/.baresip/accounts
fi

# The generated config pins module_path to the versioned Cellar directory,
# which Homebrew deletes on upgrade, leaving baresip without any modules.
if command -v brew > /dev/null 2>&1; then
    patch_config "s#^module_path.*#module_path\t\t$(brew --prefix)/lib/baresip/modules#"
fi

# Enable the srtp module by uncommenting it in the config
patch_config 's/^#module[[:space:]]*srtp.so/module\t\t\tsrtp.so/'

# Disable the audio devices, to not get permission requests on macOS and to not
# need a sound card at all on the headless Linux build machines.
patch_config 's/^module[[:space:]]*coreaudio\.so/#&/'
patch_config 's/^module[[:space:]]*alsa\.so/#&/'
patch_config 's/^module[[:space:]]*pulse\.so/#&/'
patch_config 's/^module[[:space:]]*portaudio\.so/#&/'

# Without a sound card baresip would send no audio at all, and the PBX only
# learns where to send media for a client behind NAT from the media it sends,
# so baresip would hear nothing, DTMF included. A generated tone as source and
# files as players keep media flowing both ways without any audio device. The
# alert player (busy tones and such) needs its own path, or aufile writes it to
# speaker.wav in the directory baresip was started from.
patch_config 's/^#module[[:space:]]*ausine\.so/module\t\t\tausine.so/'
patch_config 's/^#module[[:space:]]*aufile\.so/module\t\t\taufile.so/'
patch_config '/^#*audio_source[[:space:]]/d'
patch_config '/^#*audio_player[[:space:]]/d'
patch_config '/^#*audio_alert[[:space:]]/d'
printf 'audio_source\t\tausine,440\naudio_player\t\taufile,%s\naudio_alert\t\taufile,%s\n' \
    "$HOME/.baresip/received_audio.wav" "$HOME/.baresip/alert_audio.wav" >> "$CONFIG"

# Enable controlling basesip via a tcp socket
patch_config 's/^#module_app[[:space:]]*ctrl_tcp.so/module_app\t\t\tctrl_tcp.so/'

# Start from a clean slate: a leftover baresip from an earlier run would keep
# port 4444, making the wait below succeed against a process this script does
# not own while its own instance silently failed to bind ctrl_tcp.
killall -9 baresip > /dev/null 2>&1 || true

# Start baresip and run in the background
nohup baresip -v > ~/.baresip/baresip.log 2>&1 &

# The connection is opened in a subshell, which closes it again on exit.
ctrl_port_is_open() {
    (exec 3<> "/dev/tcp/127.0.0.1/$BARESIP_CTRL_PORT") 2>/dev/null
}

# Wait for the ctrl_tcp module to accept connections.
echo "⏳ Waiting for baresip to listen on 127.0.0.1:$BARESIP_CTRL_PORT..."
for _ in $(seq 30); do
    ctrl_port_is_open && break
    sleep 1
done

if ! ctrl_port_is_open; then
    echo "🚨 baresip is not listening on 127.0.0.1:$BARESIP_CTRL_PORT, so the ctrl_tcp module did not load"
    echo "🚨 Last 50 lines of ~/.baresip/baresip.log:"
    tail -n 50 ~/.baresip/baresip.log || true
    exit 1
fi

# Registration is only waited for, never enforced: the log wording differs
# between baresip versions, and a failure to register surfaces clearly enough as
# a dial that never connects.
for _ in $(seq 30); do
    if grep -q "200 OK" ~/.baresip/baresip.log 2>/dev/null; then
        echo "✅ baresip registered ${INTEGRATION_TEST_SIP_USER} and is ready to place calls, tail the log at ~/.baresip/baresip.log"
        break
    fi
    sleep 1
done
