package com.dakomn.mishkatapp

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.ModelDownloadListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Checks the same on-device service used by speech_to_text's onDevice mode.
 * Online language support must never be treated as an installed offline model.
 */
internal class ArabicSpeechModelManager(
    private val context: Context,
    private val channel: MethodChannel,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var disposed = false
    private var checkRecognizer: SpeechRecognizer? = null
    private var checkTimeout: Runnable? = null
    private val checkCallbacks = mutableListOf<(Map<String, Any>) -> Unit>()
    private var downloadRecognizer: SpeechRecognizer? = null
    private var downloadTimeout: Runnable? = null
    private var downloadGeneration = 0
    private var downloadStatus: Map<String, Any>? = null

    private fun status(
        value: String,
        locale: String = "ar-SA",
        reason: String? = null,
        progress: Int? = null,
        errorCode: Int? = null,
    ): Map<String, Any> = buildMap {
        put("status", value)
        put("localeId", locale)
        reason?.let { put("reason", it) }
        progress?.let { put("progress", it.coerceIn(0, 100)) }
        errorCode?.let { put("errorCode", it) }
    }

    private fun recognitionIntent(locale: String? = null) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            locale?.let { putExtra(RecognizerIntent.EXTRA_LANGUAGE, it) }
        }

    fun getStatus(callback: (Map<String, Any>) -> Unit) {
        if (disposed) {
            callback(status("unknown", reason = "checkUnavailable"))
            return
        }
        if (Build.VERSION.SDK_INT < 33) {
            callback(status("unsupported", reason = "requiresAndroid13"))
            return
        }
        try {
            if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
                callback(status("unsupported", reason = "noOnDeviceRecognizer"))
                return
            }
            checkCallbacks.add(callback)
            if (checkCallbacks.size > 1) return
            val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            checkRecognizer = recognizer
            val timeout = Runnable {
                if (checkRecognizer === recognizer) {
                    finishCheck(status("unknown", reason = "checkTimeout"))
                }
            }
            checkTimeout = timeout
            handler.postDelayed(timeout, 8000)
            // Omitting the locale requests the provider's language inventory.
            // Downloads and actual recognition use the Arabic locale selected below.
            recognizer.checkRecognitionSupport(
                recognitionIntent(),
                context.mainExecutor,
                object : RecognitionSupportCallback {
                    override fun onSupportResult(support: RecognitionSupport) {
                        if (disposed || checkRecognizer !== recognizer) return
                        val installed = arabicLocale(support.installedOnDeviceLanguages)
                        val pending = arabicLocale(support.pendingOnDeviceLanguages)
                        val downloadable = arabicLocale(support.supportedOnDeviceLanguages)
                        finishCheck(when {
                            installed != null -> status("installed", installed)
                            pending != null -> status("pending", pending)
                            downloadable != null -> status("downloadable", downloadable)
                            else -> status("unsupported", reason = "arabicUnsupported")
                        })
                    }

                    override fun onError(error: Int) {
                        if (disposed || checkRecognizer !== recognizer) return
                        finishCheck(status("unknown", reason = "checkUnavailable", errorCode = error))
                    }
                },
            )
        } catch (_: Exception) {
            if (checkCallbacks.isEmpty()) callback(status("unknown", reason = "checkUnavailable"))
            else finishCheck(status("unknown", reason = "checkUnavailable"))
        }
    }

    private fun arabicLocale(locales: List<String>): String? {
        val arabic = locales.map { it.replace('_', '-') }.filter {
            Locale.forLanguageTag(it).language == "ar"
        }
        return arabic.firstOrNull { it.equals("ar-SA", ignoreCase = true) }
            ?: arabic.firstOrNull()
    }

    private fun finishCheck(value: Map<String, Any>) {
        checkTimeout?.let(handler::removeCallbacks)
        checkTimeout = null
        val recognizer = checkRecognizer
        checkRecognizer = null
        try { recognizer?.destroy() } catch (_: Exception) { }
        val callbacks = checkCallbacks.toList()
        checkCallbacks.clear()
        if (value["status"] == "installed" && downloadRecognizer != null) {
            releaseDownload()
        }
        callbacks.forEach { it(value) }
    }

    fun download(callback: (Map<String, Any>) -> Unit) {
        // Recheck instead of accepting a stale or arbitrary locale from Dart.
        getStatus { available ->
            if (available["status"] != "downloadable" || disposed) {
                callback(available)
                return@getStatus
            }
            downloadStatus?.let {
                callback(it)
                return@getStatus
            }
            if (Build.VERSION.SDK_INT < 33) {
                callback(status("unsupported", reason = "requiresAndroid13"))
                return@getStatus
            }
            val locale = available["localeId"] as String
            val generation = ++downloadGeneration
            try {
                val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                downloadRecognizer = recognizer
                val pending = status("pending", locale)
                downloadStatus = pending
                // A silent provider must not leave the UI waiting forever.
                val timeout = Runnable {
                    if (generation == downloadGeneration && !disposed) {
                        finishDownload(status("unknown", locale, reason = "downloadFailed"))
                    }
                }
                downloadTimeout = timeout
                handler.postDelayed(timeout, 180000)
                if (Build.VERSION.SDK_INT >= 34) {
                    recognizer.triggerModelDownload(
                        recognitionIntent(locale),
                        context.mainExecutor,
                        object : ModelDownloadListener {
                            override fun onProgress(completedPercent: Int) {
                                if (disposed || generation != downloadGeneration) return
                                publish(status("pending", locale, progress = completedPercent))
                            }

                            override fun onSuccess() {
                                if (disposed || generation != downloadGeneration) return
                                // Success notification is still verified against the installed list.
                                releaseDownload()
                                getStatus { verified ->
                                    if (!disposed) channel.invokeMethod("arabicModelStatus", verified)
                                }
                            }

                            override fun onScheduled() {
                                if (disposed || generation != downloadGeneration) return
                                finishDownload(status("pending", locale))
                            }

                            override fun onError(error: Int) {
                                if (disposed || generation != downloadGeneration) return
                                val reason = if (error == SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS)
                                    "downloadEventsUnavailable" else "downloadFailed"
                                finishDownload(status("unknown", locale, reason = reason, errorCode = error))
                            }
                        },
                    )
                } else {
                    // API 33 has no download callbacks; the UI rechecks installation.
                    recognizer.triggerModelDownload(recognitionIntent(locale))
                }
                callback(pending)
            } catch (_: Exception) {
                releaseDownload()
                callback(status("unknown", locale, reason = "downloadFailed"))
            }
        }
    }

    private fun publish(value: Map<String, Any>) {
        downloadStatus = value
        channel.invokeMethod("arabicModelStatus", value)
    }

    private fun finishDownload(value: Map<String, Any>) {
        releaseDownload()
        if (!disposed) channel.invokeMethod("arabicModelStatus", value)
    }

    private fun releaseDownload() {
        downloadGeneration++
        downloadTimeout?.let(handler::removeCallbacks)
        downloadTimeout = null
        val recognizer = downloadRecognizer
        downloadRecognizer = null
        downloadStatus = null
        try { recognizer?.destroy() } catch (_: Exception) { }
    }

    fun dispose() {
        disposed = true
        finishCheck(status("unknown", reason = "checkUnavailable"))
        releaseDownload()
    }
}
