package com.dakomn.mishkatapp

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import android.os.Process
import androidx.core.content.ContextCompat
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineNemoEncDecCtcModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import kotlin.math.ln
import kotlin.math.sqrt

/**
 * Bundled Arabic CTC recognition. No network client, system recognizer, prompt,
 * or audio file is used. The model is read directly from APK assets.
 */
internal class OfflineRecitationPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val main = Handler(Looper.getMainLooper())
    private val decoder = Executors.newSingleThreadExecutor()
    private val captureControl = Executors.newSingleThreadExecutor()
    private val methods = MethodChannel(messenger, "com.dakomn.mishkatapp/offline_recitation")
    private val events = EventChannel(messenger, "com.dakomn.mishkatapp/offline_recitation/audio")
    private var sink: EventChannel.EventSink? = null
    private var recognizer: OfflineRecognizer? = null
    // Accessed only by decoder. A disposed page cannot release another page's model.
    private val clients = mutableSetOf<String>()
    @Volatile private var closed = false
    @Volatile private var recording = false
    @Volatile private var session: String? = null
    private var recorder: AudioRecord? = null
    private var audioThread: Thread? = null
    private val effects = mutableListOf<AudioEffect>()

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                sink = eventSink
            }
            override fun onCancel(arguments: Any?) {
                sink = null
                if (!closed) captureControl.execute { stopCapture(null) }
            }
        })
        methods.setMethodCallHandler { call, result ->
            if (closed) {
                result.error("disposed", "Recognition engine disposed", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "hasPermission" -> result.success(hasPermission())
                "initialize" -> decoder.execute {
                    try {
                        if (recognizer == null) loadModel()
                        clients.add(call.argument<String>("clientId") ?: "default")
                        reply(result, true)
                    } catch (error: Throwable) {
                        fail(result, "model_unavailable", error)
                    }
                }
                "start" -> captureControl.execute {
                    try {
                        val id = call.argument<String>("sessionId")
                            ?: throw IllegalArgumentException("Missing session")
                        startCapture(id)
                        reply(result, true)
                    } catch (error: Throwable) {
                        fail(result, if (hasPermission()) "audio_start" else "permission_denied", error)
                    }
                }
                "stop" -> captureControl.execute {
                    stopCapture(call.argument<String>("sessionId"))
                    reply(result, null)
                }
                "transcribe" -> {
                    val bytes = call.argument<ByteArray>("pcm")
                    if (bytes == null || bytes.size > SAMPLE_RATE * 2 * 15 || bytes.size % 2 != 0) {
                        result.error("invalid_audio", "Expected at most 15 seconds of mono PCM16", null)
                    } else {
                        decoder.execute { transcribe(bytes, result) }
                    }
                }
                "release" -> decoder.execute {
                    clients.remove(call.argument<String>("clientId") ?: "default")
                    if (clients.isEmpty()) releaseModel()
                    reply(result, null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasPermission() = ContextCompat.checkSelfPermission(
        activity, Manifest.permission.RECORD_AUDIO,
    ) == PackageManager.PERMISSION_GRANTED

    private fun loadModel() {
        check(!closed) { "Recognition engine disposed" }
        // openFd also verifies these large assets were packaged uncompressed.
        activity.assets.openFd("asr/model.int8.onnx").use {
            check(it.length > 100_000_000) { "Bundled model is incomplete" }
        }
        activity.assets.open("asr/tokens.txt").use { check(it.read() != -1) }
        val config = OfflineRecognizerConfig().apply {
            featConfig = FeatureConfig().apply {
                sampleRate = SAMPLE_RATE
                featureDim = 80
            }
            modelConfig = OfflineModelConfig().apply {
                nemo = OfflineNemoEncDecCtcModelConfig().apply { model = "asr/model.int8.onnx" }
                tokens = "asr/tokens.txt"
                modelType = "nemo_ctc"
                numThreads = (Runtime.getRuntime().availableProcessors() / 2).coerceIn(1, 4)
                debug = false
                provider = "cpu"
            }
            decodingMethod = "greedy_search"
        }
        recognizer = OfflineRecognizer(assetManager = activity.assets, config = config)
    }

    private fun transcribe(bytes: ByteArray, result: MethodChannel.Result) {
        try {
            val engine = recognizer ?: throw IllegalStateException("Model not loaded")
            val samples = FloatArray(bytes.size / 2) { index ->
                val low = bytes[index * 2].toInt() and 0xff
                val high = bytes[index * 2 + 1].toInt()
                ((high shl 8) or low).toShort() / 32768f
            }
            val stream = engine.createStream()
            try {
                stream.acceptWaveform(samples, SAMPLE_RATE)
                engine.decode(stream)
                reply(result, engine.getResult(stream).text)
            } finally {
                stream.release()
            }
        } catch (error: Throwable) {
            fail(result, "decode_failed", error)
        }
    }

    private fun startCapture(id: String) {
        check(!closed) { "Recognition engine disposed" }
        if (recording && session == id) return
        check(!recording) { "Another recitation owns the microphone" }
        check(hasPermission()) { "Microphone permission required" }
        check(sink != null) { "Audio listener is not attached" }
        val min = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        check(min > 0) { "16 kHz audio recording unavailable" }
        var capture: AudioRecord? = null
        for (source in listOf(MediaRecorder.AudioSource.VOICE_RECOGNITION, MediaRecorder.AudioSource.MIC)) {
            try {
                val candidate = AudioRecord(
                    source, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, maxOf(min, CHUNK_SAMPLES * 8),
                )
                if (candidate.state == AudioRecord.STATE_INITIALIZED) {
                    capture = candidate
                    break
                }
                candidate.release()
            } catch (_: Exception) {
                // Some vendors do not support VOICE_RECOGNITION; use MIC next.
            }
        }
        val input = capture ?: throw IllegalStateException("Cannot open microphone")
        try {
            disableProcessing(input.audioSessionId)
            input.startRecording()
            check(input.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Microphone did not start" }
            recorder = input
            session = id
            recording = true
            audioThread = Thread({
                Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
                val buffer = ShortArray(CHUNK_SAMPLES)
                try {
                    while (recording && session == id) {
                        val count = input.read(buffer, 0, buffer.size)
                        if (count < 0) {
                            if (recording) throw IllegalStateException("Microphone read failed ($count)")
                            break
                        }
                        if (count == 0) continue
                        val bytes = ByteArray(count * 2)
                        var energy = 0.0
                        for (index in 0 until count) {
                            val value = buffer[index].toInt()
                            energy += value.toDouble() * value
                            bytes[index * 2] = (value and 0xff).toByte()
                            bytes[index * 2 + 1] = (value shr 8).toByte()
                        }
                        val rms = sqrt(energy / count)
                        val decibels = if (rms > 0) 20 * ln(rms / 32768) / ln(10.0) else -60.0
                        emit(mapOf("type" to "audio", "sessionId" to id,
                            "pcm" to bytes, "level" to ((decibels + 60) / 60).coerceIn(0.0, 1.0)))
                    }
                } catch (_: Throwable) {
                    if (!closed && recording && session == id) {
                        emit(mapOf("type" to "error", "sessionId" to id))
                        runCatching { captureControl.execute { stopCapture(id) } }
                    }
                }
            }, "MishkatRecitationAudio").also { it.start() }
        } catch (error: Throwable) {
            recording = false
            session = null
            recorder = null
            audioThread = null
            input.release()
            effects.forEach { runCatching { it.release() } }
            effects.clear()
            throw error
        }
    }

    private fun disableProcessing(id: Int) {
        fun disable(available: Boolean, create: () -> AudioEffect?) {
            if (!available) return
            runCatching {
                create()?.let { effect ->
                    effects.add(effect)
                    effect.enabled = false
                }
            }
        }
        disable(AutomaticGainControl.isAvailable()) { AutomaticGainControl.create(id) }
        disable(NoiseSuppressor.isAvailable()) { NoiseSuppressor.create(id) }
        disable(AcousticEchoCanceler.isAvailable()) { AcousticEchoCanceler.create(id) }
    }

    /** Stop AudioRecord before joining, so a blocking read is unblocked. */
    private fun stopCapture(expectedSession: String?) {
        if (expectedSession != null && session != expectedSession) return
        recording = false
        val input = recorder
        runCatching { input?.stop() }
        runCatching { audioThread?.join(1500) }
        audioThread = null
        runCatching { input?.release() }
        recorder = null
        effects.forEach { runCatching { it.release() } }
        effects.clear()
        session = null
    }

    /** Android also releases capture if Dart is suspended before its lifecycle callback. */
    fun onHostStop() {
        if (closed) return
        val id = session ?: return
        captureControl.execute {
            stopCapture(id)
            emit(mapOf("type" to "interrupted", "sessionId" to id))
        }
    }

    private fun emit(event: Map<String, Any>) {
        main.post { if (!closed) sink?.success(event) }
    }

    private fun reply(result: MethodChannel.Result, value: Any?) {
        main.post { result.success(value) }
    }

    private fun fail(result: MethodChannel.Result, code: String, error: Throwable) {
        main.post { result.error(code, error.message ?: code, null) }
    }

    private fun releaseModel() {
        runCatching { recognizer?.release() }
        recognizer = null
    }

    fun dispose() {
        if (closed) return
        closed = true
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        captureControl.execute { stopCapture(null) }
        captureControl.shutdown()
        decoder.execute { clients.clear(); releaseModel() }
        decoder.shutdown()
    }

    companion object {
        private const val SAMPLE_RATE = 16000
        private const val CHUNK_SAMPLES = 1600
    }
}
