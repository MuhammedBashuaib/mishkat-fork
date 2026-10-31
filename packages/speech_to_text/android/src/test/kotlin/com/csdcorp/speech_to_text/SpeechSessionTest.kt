package com.csdcorp.speech_to_text

import android.content.Context
import android.content.Intent
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.mockito.ArgumentCaptor
import org.mockito.Mockito.*

class SpeechSessionTest {
    private fun set(plugin: SpeechToTextPlugin, name: String, value: Any) {
        plugin.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(plugin, value)
    }

    private fun call(plugin: SpeechToTextPlugin, name: String, vararg values: Any) {
        val method = plugin.javaClass.declaredMethods.single { it.name == name }
        method.isAccessible = true
        method.invoke(plugin, *values)
    }

    @Test
    fun cancellationReleasesRecognizerEvenAfterListeningFlagIsFalse() {
        val plugin = SpeechToTextPlugin()
        val recognizer = mock(SpeechRecognizer::class.java)
        val result = mock(MethodChannel.Result::class.java)
        set(plugin, "initializedSuccessfully", true)
        set(plugin, "minSdkForSpeechSupport", 0)
        set(plugin, "speechRecognizer", recognizer)
        set(plugin, "listening", false)

        call(plugin, "cancelListening", result)

        verify(recognizer).cancel()
        verify(recognizer).destroy()
        verify(result).success(true)
    }

    @Test
    fun cancelledSessionCannotDestroyOrReportErrorsForItsReplacement() {
        val plugin = SpeechToTextPlugin()
        val context = mock(Context::class.java)
        val first = mock(SpeechRecognizer::class.java)
        val second = mock(SpeechRecognizer::class.java)
        set(plugin, "pluginContext", context)
        mockStatic(SpeechRecognizer::class.java).use { factory ->
            factory.`when`<SpeechRecognizer> { SpeechRecognizer.createSpeechRecognizer(context) }
                .thenReturn(first, second)
            call(plugin, "createRecognizer", false)
            val oldListener = ArgumentCaptor.forClass(RecognitionListener::class.java)
            verify(first).setRecognitionListener(oldListener.capture())

            call(plugin, "createRecognizer", false)
            verify(first).cancel()
            verify(first).destroy()
            val currentListener = ArgumentCaptor.forClass(RecognitionListener::class.java)
            verify(second).setRecognitionListener(currentListener.capture())

            oldListener.value.onError(SpeechRecognizer.ERROR_SERVER_DISCONNECTED)
            oldListener.value.onEndOfSpeech()
            verify(second, never()).cancel()
            verify(second, never()).destroy()

            currentListener.value.onError(SpeechRecognizer.ERROR_RECOGNIZER_BUSY)
            verify(second).cancel()
            verify(second).destroy()
        }
    }

    @Test
    fun offlineRequestNeverFallsBackToDefaultRecognizerOnUnsupportedDevice() {
        val plugin = SpeechToTextPlugin()
        val result = mock(MethodChannel.Result::class.java)
        set(plugin, "initializedSuccessfully", true)
        set(plugin, "minSdkForSpeechSupport", 0)
        mockStatic(SpeechRecognizer::class.java).use { factory ->
            call(plugin, "startListening", result, "ar-SA", true, 0, true, 4000)

            verify(result).success(false)
            factory.verifyNoInteractions()
        }
    }

    @Test
    fun offlinePreferenceChangesEvenWhenLanguageAndPauseAreUnchanged() {
        val plugin = SpeechToTextPlugin()
        mockConstruction(Intent::class.java).use { intents ->
            call(plugin, "setupRecognizerIntent", "ar-SA", true, ListenMode.dictation, false, 4000)
            call(plugin, "setupRecognizerIntent", "ar-SA", true, ListenMode.dictation, true, 4000)
            call(plugin, "setupRecognizerIntent", "ar-SA", true, ListenMode.dictation, false, 4000)

            assertEquals(3, intents.constructed().size)
            verify(intents.constructed()[0]).putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            verify(intents.constructed()[1]).putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            verify(intents.constructed()[2]).putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
        }
    }
}
