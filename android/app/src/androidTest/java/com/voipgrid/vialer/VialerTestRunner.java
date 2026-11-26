package com.voipgrid.vialer;

import androidx.test.runner.AndroidJUnitRunner;

// Subclass of AndroidJUnitRunner defined in the test APK DEX so emulator.wtf
// can find the declared testInstrumentationRunner class during pre-deploy validation.
// AndroidJUnitRunner itself lives in the main APK (via integration_test's api dep),
// so AGP deduplication would exclude it from the test APK; this wrapper bypasses that.
public class VialerTestRunner extends AndroidJUnitRunner {}
