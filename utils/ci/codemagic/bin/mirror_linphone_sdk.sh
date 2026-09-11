#!/bin/bash

# Mirrors the flaky Linphone SDK repo locally and points the gitlab URL at it via
# git insteadOf, so SPM resolves from disk during the build. Gitlab outages fail
# (and retry) here instead of mid-build. The mirror is cached between builds, so
# an outage only costs us the newest refs rather than the whole build.

set -euo pipefail

GITLAB_URL="https://gitlab.linphone.org/BC/public/linphone-sdk-swift-ios.git"
LOCAL_MIRROR="$HOME/linphone-sdk-swift-ios-mirror.git"
TIMEOUT_SECONDS=300
DELAY_SECONDS=2

GIT_LOG="$(mktemp)"

# A previous run points the gitlab URL at the mirror, which would make the refresh
# below fetch the mirror from itself; the rule is restored once we're done.
git config --global --unset-all "url.file://$LOCAL_MIRROR.insteadOf" || true

if [ -d "$LOCAL_MIRROR" ]; then
  echo "Refreshing the cached Linphone SDK mirror..."
  action="refresh"
else
  echo "Cloning Linphone SDK from gitlab into a local mirror..."
  action="clone"
fi

SECONDS=0
attempt=0
while true; do
  attempt=$((attempt + 1))

  if [ "$action" = "refresh" ]; then
    if git --git-dir="$LOCAL_MIRROR" remote update --prune >"$GIT_LOG" 2>&1; then
      break
    fi
  else
    rm -rf "$LOCAL_MIRROR"
    if git clone --mirror "$GITLAB_URL" "$LOCAL_MIRROR" >"$GIT_LOG" 2>&1; then
      break
    fi
  fi

  if [ "$SECONDS" -ge "$TIMEOUT_SECONDS" ]; then
    cat "$GIT_LOG"
    if [ "$action" = "refresh" ]; then
      # The cached mirror still has every ref from the last successful build, which
      # is enough unless this build bumps the SDK to a version we've never fetched.
      echo "⚠️ Could not reach gitlab after $attempt attempt(s) over ${TIMEOUT_SECONDS}s; falling back to the cached mirror"
      break
    fi
    echo "❌ Failed to clone Linphone SDK from gitlab after $attempt attempt(s) over ${TIMEOUT_SECONDS}s"
    exit 1
  fi
  sleep "$DELAY_SECONDS"
done

# Point the gitlab URL at the local clone.
git config --global "url.file://$LOCAL_MIRROR.insteadOf" "$GITLAB_URL"

echo "✅ Linphone SDK mirrored locally after $attempt attempt(s); gitlab URL now resolves from $LOCAL_MIRROR"
