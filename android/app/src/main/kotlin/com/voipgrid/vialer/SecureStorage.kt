package com.voipgrid.vialer

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.util.Base64
import com.voipgrid.vialer.logging.Logger
import org.openvoipalliance.flutterphonelib.PhoneLibLogLevel.ERROR
import org.openvoipalliance.flutterphonelib.PhoneLibLogLevel.WARNING
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps credentials encrypted with an AES key that never leaves the Android Keystore, for both
 * Flutter and native code.
 *
 * Synchronized because it's used from both the Flutter and the push message threads, and the key
 * must only be generated once.
 */
class SecureStorage(context: Context, private val logger: Logger) : NativeSecureStorage {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val keyStore by lazy { KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) } }
    private var cachedKey: SecretKey? = null

    private val key: SecretKey
        get() = cachedKey
            ?: ((keyStore.getKey(KEY_ALIAS, null) as? SecretKey) ?: generateKey())
                .also { cachedKey = it }

    @get:Synchronized
    val credentials: Credentials
        get() = Credentials(apiToken = decrypt(API_TOKEN), sipPassword = decrypt(SIP_PASSWORD))

    override suspend fun read() = credentials

    override suspend fun write(credentials: Credentials) = store(credentials)

    override suspend fun clear() = remove()

    override suspend fun keySecurityLevel(): String? = runCatching { securityLevel() }.getOrNull()

    @Synchronized
    private fun store(credentials: Credentials) {
        val values = listOfNotNull(
            credentials.apiToken?.let { API_TOKEN to it },
            credentials.sipPassword?.let { SIP_PASSWORD to it },
        )
        if (values.isEmpty()) return

        val encrypted = try {
            values.map { (name, value) -> name to encrypt(value) }
        } catch (e: Exception) {
            // On some devices the key breaks, e.g. after an OS update. Without a new key the user
            // would be logged out on every start.
            logger.writeLog("Unable to encrypt credentials, replacing the key: $e", WARNING)
            resetKey()
            values.map { (name, value) -> name to encrypt(value) }
        }

        val editor = prefs.edit()
        encrypted.forEach { (name, value) -> editor.putString(name, value) }
        check(editor.commit()) { "Unable to store credentials" }
    }

    @Synchronized
    private fun remove() {
        check(prefs.edit().clear().commit()) { "Unable to remove credentials" }
    }

    /** Anything encrypted with the old key can't be decrypted anymore, so it's removed too. */
    private fun resetKey() {
        cachedKey = null
        keyStore.deleteEntry(KEY_ALIAS)
        remove()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key) }
        val payload = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    private fun decrypt(name: String): String? {
        val stored = prefs.getString(name, null) ?: return null

        return try {
            val payload = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_LENGTH, payload, 0, IV_LENGTH))
            }
            String(cipher.doFinal(payload, IV_LENGTH, payload.size - IV_LENGTH), Charsets.UTF_8)
        } catch (e: Exception) {
            // Treated as logged out, logging in again replaces the key if it's broken.
            logger.writeLog("Unable to decrypt $name: $e", ERROR)
            null
        }
    }

    private fun generateKey(): SecretKey = KeyGenerator
        .getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        .apply {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    // Incoming calls must be able to read credentials without the user present.
                    .setUserAuthenticationRequired(false)
                    .build()
            )
        }
        .generateKey()

    @Synchronized
    private fun securityLevel(): String {
        val secretKey = key
        val info = SecretKeyFactory.getInstance(secretKey.algorithm, ANDROID_KEYSTORE)
            .getKeySpec(secretKey, KeyInfo::class.java) as KeyInfo

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            @Suppress("DEPRECATION")
            return if (info.isInsideSecureHardware) "secure-hardware" else "software"
        }

        return when (info.securityLevel) {
            KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
            KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "trusted-environment"
            KeyProperties.SECURITY_LEVEL_UNKNOWN_SECURE -> "unknown-secure"
            KeyProperties.SECURITY_LEVEL_SOFTWARE -> "software"
            else -> "unknown"
        }
    }

    companion object {
        private const val PREFS_NAME = "VialerSecureStorage"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "vialer_secure_storage"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_LENGTH = 12
        private const val TAG_LENGTH = 128
        private const val API_TOKEN = "api_token"
        private const val SIP_PASSWORD = "sip_password"
    }
}
