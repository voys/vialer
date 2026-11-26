package com.voipgrid.vialer;

import androidx.test.platform.app.InstrumentationRegistry;

import dev.flutter.plugins.integration_test.FlutterTestRunner;

import org.junit.runner.Description;
import org.junit.runner.notification.Failure;
import org.junit.runner.notification.RunNotifier;

/**
 * Runs the Flutter integration tests, first reconnecting the device to Firebase Cloud Messaging
 * when the run passes {@code refreshPushConnection=true}, so the incoming call push can arrive.
 */
public class IncomingCallReadyTestRunner extends FlutterTestRunner {
    private static final String REFRESH_PUSH_CONNECTION_ARGUMENT = "refreshPushConnection";

    private final Class<?> testClass;

    public IncomingCallReadyTestRunner(Class<?> testClass) {
        super(testClass);
        this.testClass = testClass;
    }

    // With FlutterTestRunner's own "Flutter Tests" name, emulator.wtf's flaky test retry finds no
    // tests to run.
    @Override
    public Description getDescription() {
        return Description.createTestDescription(testClass, "Integration Tests");
    }

    @Override
    public void run(RunNotifier notifier) {
        if (isPushConnectionRefreshRequested()) {
            try {
                PushConnection.reconnect();
            } catch (Exception e) {
                reportFailure(notifier, e);
                return;
            }
        }
        super.run(notifier);
    }

    private static boolean isPushConnectionRefreshRequested() {
        String argument = InstrumentationRegistry.getArguments().getString(REFRESH_PUSH_CONNECTION_ARGUMENT);
        return Boolean.parseBoolean(argument);
    }

    private void reportFailure(RunNotifier notifier, Exception e) {
        notifier.fireTestStarted(getDescription());
        notifier.fireTestFailure(new Failure(getDescription(), e));
        notifier.fireTestFinished(getDescription());
    }
}
