package com.voipgrid.vialer;

import android.os.ParcelFileDescriptor;
import android.os.SystemClock;

import androidx.test.platform.app.InstrumentationRegistry;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Google Play services' connection to Firebase Cloud Messaging, which delivers incoming call pushes.
 *
 * An emulator booted from a snapshot restores a connection the server has long dropped, so pushes
 * never arrive until Play services notices and reconnects, which takes longer than a test waits.
 */
final class PushConnection {
    private static final String STATE_COMMAND = "dumpsys activity service com.google.android.gms/.gcm.GcmService";
    // Matches lines like "11-24 10:56:03.123 net=100: Connected", capturing the time without millis.
    private static final Pattern CONNECTED = Pattern.compile(
            "^\\s*(\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\.\\d+ net=\\d+: Connected$",
            Pattern.MULTILINE);
    private static final long TIMEOUT_MILLIS = 3 * 60 * 1000;
    private static final long POLL_INTERVAL_MILLIS = 5 * 1000;

    private PushConnection() {}

    /** Drops the network so Play services reconnects, and waits until it has. */
    static void reconnect() throws IOException, InterruptedException {
        shell("svc wifi disable");
        Thread.sleep(POLL_INTERVAL_MILLIS);
        shell("svc wifi enable");
        String reenabledAt = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(new Date());

        long deadline = SystemClock.uptimeMillis() + TIMEOUT_MILLIS;
        String state = "";
        while (SystemClock.uptimeMillis() < deadline) {
            state = shell(STATE_COMMAND);
            if (connectedSince(state, reenabledAt)) {
                return;
            }
            Thread.sleep(POLL_INTERVAL_MILLIS);
        }
        throw new IllegalStateException(
                "Google Play services did not reconnect to Firebase Cloud Messaging within "
                        + TIMEOUT_MILLIS / 1000 + "s of the network coming back at "
                        + reenabledAt + ", so no incoming call can ring. Push connection state:\n" + state);
    }

    private static boolean connectedSince(String state, String time) {
        Matcher connected = CONNECTED.matcher(state);
        while (connected.find()) {
            if (connected.group(1).compareTo(time) >= 0) {
                return true;
            }
        }
        return false;
    }

    private static String shell(String command) throws IOException {
        ParcelFileDescriptor output = InstrumentationRegistry.getInstrumentation()
                .getUiAutomation()
                .executeShellCommand(command);
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                new ParcelFileDescriptor.AutoCloseInputStream(output), StandardCharsets.UTF_8))) {
            return reader.lines().collect(Collectors.joining("\n"));
        }
    }
}
