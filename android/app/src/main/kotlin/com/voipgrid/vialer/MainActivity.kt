package com.voipgrid.vialer

import SystemTones
import android.content.ClipboardManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.view.textclassifier.TextClassifier
import androidx.annotation.NonNull
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.firebase.ktx.Firebase
import com.google.firebase.messaging.ktx.messaging
import com.voipgrid.vialer.IncomingCallActivity.Companion.INCOMING_CALL_CANCEL_INTENT
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import org.openvoipalliance.flutterphonelib.PhoneLib
import org.openvoipalliance.flutterphonelib.startCall

class MainActivity : FlutterActivity(), CallScreenBehavior {
    private lateinit var nativeToFlutter: NativeToFlutter

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        val binaryMessenger = flutterEngine.dartExecutor.binaryMessenger

        NativeLogging.setUp(binaryMessenger, App.logger)
        ContactSortHostApi.setUp(binaryMessenger, object : ContactSortHostApi {
            override fun getSorting(): ContactSort {
                return ContactSort(orderBy = OrderBy.FAMILY_NAME)
            }
        })

        NativeIncomingCallScreen.setUp(binaryMessenger, object : NativeIncomingCallScreen {
            override fun launch(
                remotePartyHeading: String,
                remotePartySubheading: String,
                imageUri: String,
            ) {
                this@MainActivity.launchIncomingCallScreen(
                    remotePartyHeading, remotePartySubheading, when {
                        imageUri.isNullOrBlank() -> null
                        else -> imageUri
                    }
                )
            }
        })

        Tones.setUp(
            binaryMessenger,
            SystemTones(this, App.logger)
        )

        NativeMetrics.setUp(binaryMessenger, object : NativeMetrics {
            override fun initialize() {
                App.segment.initialize()
            }
        })

        CallThrough.setUp(binaryMessenger, CallThroughCalling(this, App.logger, App.segment))

        CallScreenBehavior.setUp(binaryMessenger, this)

        val androidAppUpdates = AndroidFlexibleUpdateHandler(binaryMessenger)

        val updater = AppUpdater(
            this@MainActivity,
            onUpdateTypeKnown = { isFlexible ->
                androidAppUpdates.onUpdateTypeKnown(isFlexible) { return@onUpdateTypeKnown  }
            },
            onFlexibleUpdateDownloaded = {
                androidAppUpdates.onDownloaded {
                    Result.success(Unit)
                }
            }
        )

        AppUpdates.setUp(
            binaryMessenger,
            object : AppUpdates {
                override fun check() = updater.check()
                override fun completeAndroidFlexibleUpdate() = updater.completeFlexibleUpdate()
            }
        )

        Contacts.setUp(binaryMessenger, ContactImporter(this))

        GooglePlayServices.setUp(binaryMessenger, object : GooglePlayServices {
            override fun isAvailable(): Boolean {
                val googlePlayServices = GoogleApiAvailability.getInstance()
                val status = googlePlayServices.isGooglePlayServicesAvailable(this@MainActivity)
                return status == ConnectionResult.SUCCESS
            }
        })

        MiddlewareRegistrar.setUp(binaryMessenger, object : MiddlewareRegistrar {
            override fun register(token: String) = App.middleware.register(token)
            override fun unregister(appAccountId: Long) =
                App.middleware.unregister(appAccountId)
        })

        nativeToFlutter = NativeToFlutter(binaryMessenger);

        NativeSecureStorage.setUp(binaryMessenger, App.secureStorage)

        NativeClipboard.setUp(binaryMessenger, object : NativeClipboard {
            override fun hasPhoneNumber(callback: (Result<Boolean>) -> Unit) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    callback(Result.success(false))
                    return
                }


                try {
                    val clipboard = context.getSystemService(ClipboardManager::class.java)
                    val confidenceScore = clipboard.primaryClipDescription?.getConfidenceScore(
                        TextClassifier.TYPE_PHONE)
                    callback(Result.success(confidenceScore != null && confidenceScore > 0.8))
                } catch (e: IllegalStateException) {
                    callback(Result.success(false))
                }

            }
        })
    }

    override fun enable() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(legacyFlags)
        }
    }

    override fun disable() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            window.clearFlags(legacyFlags)
        }

        // We will make sure the incoming call screen has also finished
        sendBroadcast(Intent(INCOMING_CALL_CANCEL_INTENT))
    }

    protected override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.onCallAction { number, callStartAction -> call(number, callStartAction) }
        setIntent(intent);
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent.onCallAction { number, callStartAction -> call(number, callStartAction) }
    }

    private fun call(number: String, callStartAction: CallStartAction) {
        val normalizedNumber = number.replace(Regex("[^0-9\\+]"), "")
        if (normalizedNumber.isEmpty()) return
        when (callStartAction) {
            CallStartAction.IMMEDIATELY_START_CALL -> startCall(normalizedNumber)
            CallStartAction.FILL_NUMBER_IN_DIALER -> nativeToFlutter.launchDialerAndPopulateNumber(normalizedNumber) {}
        }
    }

    protected override fun onResume() {
        super.onResume()

        val pressedNotification = intent?.getBooleanExtra(PhoneLib.PRESSED_MISSED_CALL_NOTIFICATION_EXTRA, false)
        if (pressedNotification == true) {
            PhoneLib.notifyMissedCallNotificationPressed()
        }

        Firebase.messaging.token.addOnSuccessListener {
            it?.let {
                App.middleware.register(it)
            }
        }
    }

    companion object {
        /**
         * These are the flags required for call screen behaviour in <= Android 8.0
         */
        const val legacyFlags = (WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                or WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON)
    }
}

fun Intent.onCallAction(callback: (number: String, callStartAction: CallStartAction) -> Unit) {
    val number = data?.schemeSpecificPart ?: ""

    when (action) {
        VoysIntent.ACTION_CALL -> {
            val remotePartyNumber = getStringExtra(VoysIntent.EXTRA_REMOTE_PARTY_NUMBER) ?: ""
            val remotePartyName = getStringExtra(VoysIntent.EXTRA_REMOTE_PARTY_NAME) ?: ""

            // Giving vague hints about the data we have been provided for privacy reasons, log
            // to console if you need to debug this.
            App.logger.writeLog("Received ${VoysIntent.ACTION_CALL} so starting call")
            App.logger.writeLog("Remote party number starts with ${remotePartyNumber.take(3)}")
            App.logger.writeLog("Remote party name is ${remotePartyName.length} characters long")
            App.sendAppToBackgroundAfterCall = true
            callback(number, CallStartAction.IMMEDIATELY_START_CALL)
        }
        Intent.ACTION_CALL, Intent.ACTION_DIAL, Intent.ACTION_VIEW -> callback(number, CallStartAction.FILL_NUMBER_IN_DIALER)
        else -> {}
    }
}

enum class CallStartAction {
    IMMEDIATELY_START_CALL,
    FILL_NUMBER_IN_DIALER,
}

class VoysIntent {
    companion object {
        const val ACTION_CALL: String = "co.voys.action.CALL"
        const val EXTRA_REMOTE_PARTY_NUMBER: String = "co.voys.intent.extra.REMOTE_PARTY_NUMBER"
        const val EXTRA_REMOTE_PARTY_NAME: String = "co.voys.intent.extra.REMOTE_PARTY_NAME"
    }
}

