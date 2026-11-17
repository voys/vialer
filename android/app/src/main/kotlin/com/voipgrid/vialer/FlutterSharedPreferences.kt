package com.voipgrid.vialer

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.PowerManager
import kotlinx.coroutines.channels.Channel
import org.json.JSONObject

class FlutterSharedPreferences(private val context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    val user: UserJson?
        get() {
            val pref = prefs.getString(USER_KEY, null) ?: return null
            return UserJson(JSONObject(pref))
        }

    var pushToken
        get() = prefs.getString(PUSH_TOKEN_KEY, "")
        set(value) = prefs.edit().putString(PUSH_TOKEN_KEY, value).apply()

    var isLoggedInSomewhereElse
        get() = prefs.getBoolean(IS_LOGGED_IN_SOMEWHERE_ELSE_KEY, false)
        set(value) = prefs.edit().putBoolean(IS_LOGGED_IN_SOMEWHERE_ELSE_KEY, value)
            .apply()

    var installationId: String?
        get() = prefs.getString(INSTALLATION_ID_KEY, null)
        set(value) = prefs.edit().apply {
            if (value != null) {
                putString(INSTALLATION_ID_KEY, value)
            } else {
                remove(INSTALLATION_ID_KEY)
            }
        }.apply()

    var middlewareRegistrationToken: String?
        get() = prefs.getString(MIDDLEWARE_REGISTRATION_TOKEN_KEY, null)
        set(value) = prefs.edit().apply {
            if (value != null) {
                putString(MIDDLEWARE_REGISTRATION_TOKEN_KEY, value)
            } else {
                remove(MIDDLEWARE_REGISTRATION_TOKEN_KEY)
            }
        }.apply()

    private var logs
        get() = prefs.getString(LOGS_KEY, "")
        set(value) = prefs.edit().putString(LOGS_KEY, value).apply()

    suspend fun appendLogs(log: String) {
        if (!isAppendingLogs) {
            startAppending()
        }

        appendLogsChannel.send(log)
    }

    private val appendLogsChannel = Channel<String>()
    private var isAppendingLogs: Boolean = false

    // We have to queue append operations, otherwise logs will be missing.
    private suspend fun startAppending() {
        isAppendingLogs = true
        while (isAppendingLogs) {
            val log = appendLogsChannel.receive()
            logs += "\n$log"
        }
    }

    companion object {
        private const val KEY_PREFIX = "flutter."
        private const val USER_KEY = "${KEY_PREFIX}system_user"
        private const val PUSH_TOKEN_KEY = "${KEY_PREFIX}push_token"
        private const val LOGS_KEY = "${KEY_PREFIX}logs"
        private const val IS_LOGGED_IN_SOMEWHERE_ELSE_KEY =
            "${KEY_PREFIX}is_logged_in_somewhere_else"
        private const val INSTALLATION_ID_KEY = "${KEY_PREFIX}installation_id"
        private const val MIDDLEWARE_REGISTRATION_TOKEN_KEY =
            "${KEY_PREFIX}middleware_registration_token"
    }
}

val Context.isIgnoringBatteryOptimizations: Boolean
    get() {
        val pm: PowerManager = this.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return pm.isIgnoringBatteryOptimizations(this.getPackageName())
        }
        return true;
    }

@JvmInline
value class UserJson(private val json: JSONObject) {
    /**
     * Versions up to 7.75.0 stored the API token here, it's moved to secure storage once Flutter
     * starts. Remove once almost all users have upgraded from 7.75.0.
     */
    val legacyToken: String?
        get() = (json.opt("token") as? String)?.takeIf { it.isNotEmpty() }

    val uuid: String
        get() = json.getString("uuid")

    val voip: UserVoipConfigJson?
        get() = json.optJSONObject("voip")?.let { UserVoipConfigJson(it) }

    val client: ClientJson
        get() = ClientJson(json.getJSONObject("client"))
}

@JvmInline
value class SettingsJson(val json: JSONObject) {
    inline fun <reified T> get(key: String): T = json.get(key) as T
}

@JvmInline
value class ClientJson(val json: JSONObject) {
    val voip: ClientVoipConfigJson?
        get() = json.optJSONObject("voip")?.let { ClientVoipConfigJson(it) }
}

@JvmInline
value class ClientVoipConfigJson(val json: JSONObject) {
    // Fallback will be stored here as well.
    val middlewareUrl: String
        get() = json.getString("MIDDLEWARE")
}

@JvmInline
value class UserVoipConfigJson(val json: JSONObject) {
    val sipUserId: String
        get() = json.getString("appaccount_account_id")
}