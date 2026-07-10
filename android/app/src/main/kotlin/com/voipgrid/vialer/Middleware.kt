package com.voipgrid.vialer

import com.voipgrid.vialer.BuildConfig
import android.content.Context
import android.os.Build
import com.google.firebase.messaging.RemoteMessage
import com.voipgrid.vialer.logging.Logger
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import org.openvoipalliance.flutterphonelib.NativeMiddleware
import org.openvoipalliance.flutterphonelib.NativeMiddlewareUnavailableReason
import java.io.IOException
import java.math.BigDecimal
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

class Middleware(
    private val context: Context,
    private val logger: Logger,
    private val prefs: FlutterSharedPreferences,
    private val segment: Segment,
) : NativeMiddleware {
    private val client = OkHttpClient()

    /**
     * Store the information from the push message that was received so we can submit this at the
     * end of the call to provide better metrics regarding our reliability.
     */
    var currentCallInfo: CurrentCallInfo? = null

    /**
     * We want to make sure to not process multiple push notifications for the same call (as the
     * middleware will send up to 8). So we'll track the calls we are currently handling and make
     * sure to ignore any with the same id in the future.
     */
    private var callIdsBeingHandled = mutableListOf<String>()

    /**
     * Guards against overlapping registration requests. Several triggers
     * (tokenReceived, StartVoip, the use-voip settings listener, user-data
     * refresh) can call register() at the same time; at first login the stored
     * registration token is still null, so each would POST /register with the
     * same push token and race callwaker's one-active-registration unique index.
     * Coalescing them into a single in-flight request avoids that.
     */
    private val isRegistering = AtomicBoolean(false)

    val baseUrl: String
        get() {
            val environment =
                if (context.getString(R.string.identifier) == "vialerStaging") "staging" else "production"
            return "https://api.eu-$environment.holodeck.voys.nl/callwaker"
        }

    override fun tokenReceived(token: String) {
        segment.track("push-token-received", mapOf(
            "push-token" to maskPushToken(token)
        ))

        register(token)
    }

    fun register(token: String) {
        prefs.pushToken = token

        val middlewareCredentials = middlewareCredentials

        if (middlewareCredentials == null) {
            log("Registration cancelled: Middleware credentials are not set.")
            return
        }

        val appAccountId = middlewareCredentials.sipUserId.toLongOrNull()
        if (appAccountId == null) {
            log("Registration cancelled: sipUserId is not a number.")
            return
        }

        // Generate a stable installation id on first registration if one isn't
        // set yet; it is persisted so Dart can read it back when unregistering.
        if (prefs.installationId == null) {
            prefs.installationId = UUID.randomUUID().toString()
        }

        // Coalesce overlapping triggers: if a registration is already in flight,
        // skip this one rather than firing a second, racing /register.
        if (!isRegistering.compareAndSet(false, true)) {
            log("Registration already in progress, skipping duplicate request")
            return
        }

        sendRegistration(
            token = token,
            apiToken = middlewareCredentials.loginToken,
            appAccountId = appAccountId,
            registrationToken = prefs.middlewareRegistrationToken,
        )
    }

    private fun sendRegistration(
        token: String,
        apiToken: String,
        appAccountId: Long,
        registrationToken: String?,
    ) {
        // A registration token proves a prior registration, allowing the
        // cheaper refresh endpoint to be used instead.
        val urlString = if (registrationToken != null) {
            "$baseUrl/refresh_register"
        } else {
            "$baseUrl/register"
        }

        log("Registering to middleware: $urlString")

        val jsonObject = JSONObject().apply {
            put("platform", "android")
            put("app_id", context.packageName)
            put("app_account_id", appAccountId)
            put("push_token", token)
            put("os_version", Build.VERSION.RELEASE)
            put("app_version", BuildConfig.VERSION_NAME.split('-').first())
            put("installation_id", prefs.installationId)
            if (registrationToken != null) put("registration_token", registrationToken)
        }

        val requestBody = jsonObject.toString().toRequestBody("application/json".toMediaType())

        val request = createMiddlewareRequest(apiToken, url = urlString)
            .post(requestBody)
            .build()

        client.newCall(request).enqueue(
            object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    isRegistering.set(false)
                    trackRegistrationFailed(statusCode = null, error = e.localizedMessage)
                    log("Registration failed: ${e.localizedMessage}")
                }

                override fun onResponse(call: Call, response: Response) = response.use {
                    when {
                        response.isSuccessful -> {
                            val newRegistrationToken = response.body?.string()
                                ?.let { runCatching { JSONObject(it).optString("registration_token") }.getOrNull() }
                            if (!newRegistrationToken.isNullOrEmpty()) {
                                prefs.middlewareRegistrationToken = newRegistrationToken
                            }
                            log("Registration successful")
                            isRegistering.set(false)
                        }
                        registrationToken != null && response.code == 409 -> {
                            // 409 = account registered on another device; log out.
                            log("Refresh returned 409: account registered on another device, logging out")
                            prefs.isLoggedInSomewhereElse = true
                            isRegistering.set(false)
                        }
                        registrationToken != null && response.code in listOf(403, 404) -> {
                            // The stored registration token is no longer valid,
                            // fall back to a full registration. Keep isRegistering
                            // held: the fallback is the same in-flight registration
                            // and releases it when it completes.
                            log("Refresh failed with status code: ${response.code}, falling back to full registration")
                            prefs.middlewareRegistrationToken = null
                            sendRegistration(
                                token = token,
                                apiToken = apiToken,
                                appAccountId = appAccountId,
                                registrationToken = null,
                            )
                        }
                        else -> {
                            trackRegistrationFailed(statusCode = response.code, error = null)
                            log("Registration failed: response code was ${response.code}")
                            isRegistering.set(false)
                        }
                    }
                }
            }
        )
    }

    fun unregister(appAccountId: Long) {
        val installationId = prefs.installationId
        val registrationToken = prefs.middlewareRegistrationToken
        val apiToken = middlewareCredentials?.loginToken

        if (installationId == null || registrationToken == null || apiToken == null) {
            log("Skipping unregister: no active registration")
            return
        }

        val urlString = "$baseUrl/unregister"
        log("Unregistering from middleware: $urlString")

        val jsonObject = JSONObject().apply {
            put("app_account_id", appAccountId)
            put("installation_id", installationId)
            put("registration_token", registrationToken)
        }

        val requestBody = jsonObject.toString().toRequestBody("application/json".toMediaType())

        val request = createMiddlewareRequest(apiToken, url = urlString)
            .post(requestBody)
            .build()

        client.newCall(request).enqueue(
            object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    log("Unregister failed: ${e.localizedMessage}")
                }

                override fun onResponse(call: Call, response: Response) = response.use {
                    if (response.isSuccessful) {
                        prefs.middlewareRegistrationToken = null
                        log("Unregister successful")
                    } else {
                        log("Unregister failed: response code was ${response.code}")
                    }
                }
            }
        )
    }

    override fun respond(
        remoteMessage: RemoteMessage,
        available: Boolean,
        reason: NativeMiddlewareUnavailableReason?,
    ) {
        val middlewareCredentials = middlewareCredentials
        val callId = remoteMessage.callId!!
        val correlationId = remoteMessage.correlationId!!
        val pushSentTime = remoteMessage.pushSentTime
        val pushResponseTime = remoteMessage.secondsSincePushWasSent
        val responseUrl = remoteMessage.responseUrl!!

        log("Middleware Respond: Attempting for call=$callId, correlationId=$correlationId, available=$available, sent at=$pushSentTime, response time=$pushResponseTime")

        if (middlewareCredentials == null) {
            log("Middleware credentials are not set, not responding.")
            return
        }

        if (pushResponseTime > MIDDLEWARE_SECONDS_BEFORE_REJECTED) {
            log("The response time is $pushResponseTime, it is likely we are too late for this call.")
        }

        val data = JSONObject().apply {
            put("call_id", callId)
            put("available", available)
        }

        val request = Request.Builder()
            .url(responseUrl)
            .post(data.toString().toRequestBody("application/json".toMediaType()))
            .build()

        // Capturing as a callback just to cut down on some code duplication.
        val track: (middlewareResponse: String) -> Unit = {
            trackNotificationResult(
                remoteMessage,
                it,
                available,
                reason,
                pushResponseTime,
            )
        }

        client.newCall(request).enqueue(
            object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    track("error")
                    trackResponseFailed(remoteMessage, statusCode = null, error = e.localizedMessage, available, reason)
                    log("Middleware respond Failed: with ${e.localizedMessage}")
                }

                override fun onResponse(call: Call, response: Response) {
                    track(response.code.toString())

                    when (response.isSuccessful) {
                        true -> log("Middleware respond success: $callId")
                        false -> {
                            trackResponseFailed(remoteMessage, statusCode = response.code, error = null, available, reason)
                            log("Middleware respond failed: response code was ${response.code}")
                        }
                    }
                }
            }
        )

        // If we are responding as available, we are going to store this data to submit at the
        // end of the call. We don't want to update this when available=false because this would
        // overwrite the data if we have an ongoing call.
        if (available) {
            currentCallInfo = remoteMessage.toCurrentCallInfo()
        }
    }

    override fun inspect(remoteMessage: RemoteMessage): Boolean {
        if (!remoteMessage.isCall) return false

        if (isCallAlreadyBeingHandled(remoteMessage)) {
            log("Ignoring push message as we are already handling it: ${remoteMessage.callId}")
            return false
        }

        return true.also {
            segment.track(
                "middleware-notification-received", remoteMessage.trackingProperties + mapOf(
                    "seconds_from_call_to_received" to remoteMessage.secondsSincePushWasSent.toString(),
                    "is_ignoring_battery_optimizations" to context.isIgnoringBatteryOptimizations.toString(),
                    "middleware_url" to baseUrl,
                    "service" to "callwaker",
                )
            )
        }
    }

    private fun trackNotificationResult(
        remoteMessage: RemoteMessage,
        middlewareResponse: String,
        available: Boolean,
        reason: NativeMiddlewareUnavailableReason? = null,
        responseTime: Long,
    ) =
        segment.track(
            "middleware-responded", remoteMessage.trackingProperties + mapOf(
                "middleware_response" to middlewareResponse,
                "available" to available.toString(),
                "unavailable_reason" to (reason?.name ?: ""),
                "seconds_from_call_to_responded" to responseTime.toString(),
                "is_ignoring_battery_optimizations" to context.isIgnoringBatteryOptimizations.toString(),
                "middleware_url" to baseUrl,
                "service" to "callwaker",
            )
        )

    private fun trackRegistrationFailed(statusCode: Int?, error: String?) =
        segment.track(
            "middleware-registration-failed", mapOf(
                "status_code" to (statusCode?.toString() ?: ""),
                "error" to (error ?: ""),
                "middleware_url" to baseUrl,
                "service" to "callwaker",
            )
        )

    private fun trackResponseFailed(
        remoteMessage: RemoteMessage,
        statusCode: Int?,
        error: String?,
        available: Boolean,
        reason: NativeMiddlewareUnavailableReason?,
    ) =
        segment.track(
            "middleware-response-failed", remoteMessage.trackingProperties + mapOf(
                "status_code" to (statusCode?.toString() ?: ""),
                "error" to (error ?: ""),
                "available" to available.toString(),
                "unavailable_reason" to (reason?.name ?: ""),
                "middleware_url" to baseUrl,
                "service" to "callwaker",
            )
        )

    /**
     * Check to see if a call is being handled currently, if we are handling the call already
     * we do not want to process future push notifications.
     *
     * The id being tracked will also be updated here.
     */
    private fun isCallAlreadyBeingHandled(remoteMessage: RemoteMessage) =
        callIdsBeingHandled.contains(remoteMessage.callId).also {
            log("Handling inbound call: ${remoteMessage.callId}")
            remoteMessage.callId?.let { callIdsBeingHandled.add(it) }
        }

    private fun createMiddlewareRequest(token: String, url: String) =
        Request.Builder().url(url).addHeader("Authorization", "Bearer $token")

    private fun log(message: String) = logger.writeLog("NATIVE-MIDDLEWARE: $message")

    private fun maskPushToken(token: String): String {
        return if (token.length > 6) {
            "*".repeat(token.length - 6) + token.takeLast(6)
        } else {
            "*".repeat(token.length)
        }
    }

    private val middlewareCredentials
        get() = prefs.user?.let { user ->
            user.voip?.let { voip ->
                MiddlewareCredentials(
                    sipUserId = voip.sipUserId,
                    loginToken = user.token
                )
            }
        }

    companion object {
        /**
         * The number of seconds that the Middleware will wait for us to respond before the call
         * will be rejected.
         */
        private const val MIDDLEWARE_SECONDS_BEFORE_REJECTED = 8
    }

    private data class MiddlewareCredentials(
        val loginToken: String,
        val sipUserId: String
    )

    data class CurrentCallInfo(
        val callId: String,
        val correlationId: String,
        val pushReceivedTime: String,
    )
}

private val RemoteMessage.callId
    get() = data["call_id"]

private val RemoteMessage.correlationId
    get() = data["vg_cid"]

private val RemoteMessage.messageStartTime
    get() = data["message_start_time"]

private val RemoteMessage.isCall
    get() = data["type"] == "call"

private val RemoteMessage.responseUrl
    get() = data["response_api"]

private val RemoteMessage.pushSentTime
    get() = try {
        val startTime = messageStartTime

        when {
            startTime == null -> 0
            else -> BigDecimal(messageStartTime).toLong()
        }
    } catch (e: Throwable) {
        0
    }

private val RemoteMessage.secondsSincePushWasSent
    get() = (System.currentTimeMillis() / 1000) - pushSentTime

private val RemoteMessage.trackingProperties
    get() = mapOf(
        "call_id" to callId,
        "correlation_id" to correlationId,
        "message_start_time" to messageStartTime,
        "push_sent_time" to pushSentTime.toString(),
        "response_url" to responseUrl,
    )

private fun RemoteMessage.toCurrentCallInfo() = Middleware.CurrentCallInfo(
    callId ?: "",
    correlationId ?: "",
    System.currentTimeMillis().toString()
)