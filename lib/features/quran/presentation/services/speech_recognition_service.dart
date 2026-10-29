import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Transcribed speech result payload emitted by a [SpeechRecognitionService].
class SpeechRecognitionResultData {
  const SpeechRecognitionResultData({
    required this.recognizedWords,
    required this.isFinal,
    this.confidence = 1.0,
    this.alternates = const [],
  });

  final String recognizedWords;
  final bool isFinal;
  final double confidence;
  final List<String> alternates;

  @override
  String toString() =>
      'SpeechRecognitionResultData(words: $recognizedWords, isFinal: $isFinal, conf: $confidence)';
}

/// Abstract contract decoupling speech recognition and microphone capture from the application.
abstract class SpeechRecognitionService {
  /// Initializes the recognition engine and checks hardware availability.
  Future<bool> initialize();

  /// Whether microphone and speech recognition permissions are currently granted.
  Future<bool> hasPermission();

  /// Explicitly requests microphone and speech recognition permissions from the OS.
  Future<bool> requestPermission();

  /// Opens application system settings on the device so the user can grant permission manually.
  Future<bool> openAppSettings();

  /// Whether the platform recognizer is available and ready.
  bool get isAvailable;

  /// Whether the recognizer is currently active and listening to the microphone.
  bool get isListening;

  /// Stream of recognized transcript results emitted in real-time.
  Stream<SpeechRecognitionResultData> get resultsStream;

  /// Stream of recognizer status changes ('listening', 'notListening', 'done').
  Stream<String> get statusStream;

  /// Stream of recognition errors.
  Stream<String> get errorStream;

  /// Starts capturing microphone audio and streaming recognized speech.
  Future<bool> startListening({
    String localeId = 'ar_SA',
    List<String> contextualPhrases = const [],
  });

  /// Stops capturing microphone audio, completing the current stream.
  Future<void> stopListening();

  /// Immediately cancels audio capture and discards any pending recognition.
  Future<void> cancelListening();

  /// Releases platform resources and closes streams.
  Future<void> dispose();
}

/// Production implementation of [SpeechRecognitionService] backed by native platform ASR ([SpeechToText]).
class NativeSpeechRecognitionService implements SpeechRecognitionService {
  NativeSpeechRecognitionService({SpeechToText? speechToText})
    : _stt = speechToText ?? SpeechToText();

  final SpeechToText _stt;

  final _resultsController =
      StreamController<SpeechRecognitionResultData>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  bool _isInitialized = false;
  bool _hasStartedListening = false;

  @override
  Stream<SpeechRecognitionResultData> get resultsStream =>
      _resultsController.stream;

  @override
  Stream<String> get statusStream => _statusController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  bool get isAvailable => _isInitialized && _stt.isAvailable;

  @override
  bool get isListening => _stt.isListening;

  @override
  Future<bool> initialize() async {
    if (_isInitialized && _stt.isAvailable) return true;

    try {
      final available = await _stt.initialize(
        onError: _onError,
        onStatus: _onStatus,
        debugLogging: kDebugMode,
        options: [
          // Tasmee uses the phone microphone, not a Bluetooth audio route.
          // Disabling Bluetooth here avoids an unrelated runtime permission
          // preventing recognition on Android 12+ devices.
          SpeechToText.androidNoBluetooth,
          // A few Android vendors do not expose their default recognizer
          // through the standard intent lookup path.
          SpeechToText.androidIntentLookup,
        ],
      );
      _isInitialized = available;
      return available;
    } catch (e) {
      _errorController.add('فشل تهيئة محرك التعرف الصوتي: $e');
      _isInitialized = false;
      return false;
    }
  }

  @override
  Future<bool> hasPermission() async {
    try {
      return await _stt.hasPermission;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final already = await hasPermission();
      if (already) return true;

      // On Android & iOS, SpeechToText.initialize triggers the native OS permission prompt
      final available = await initialize();
      final hasPerm = await hasPermission();
      return hasPerm || available;
    } catch (e) {
      _errorController.add('فشل طلب إذن الميكروفون: $e');
      return false;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> startListening({
    String localeId = 'ar_SA',
    List<String> contextualPhrases = const [],
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return false;
    }

    // speech_to_text requires every completed/timed-out session to be ended
    // with stop/cancel before another listen call. `isListening` is already
    // false by the time the platform emits `done`, so checking it alone leaves
    // the native recognizer busy on the next cycle.
    if (_hasStartedListening) {
      try {
        await _stt.cancel();
      } catch (_) {}
    }

    // Determine best available Arabic locale
    var targetLocale = localeId;
    try {
      final locales = await _stt.locales();
      final arabicLocales = locales
          .where((l) => l.localeId.toLowerCase().startsWith('ar'))
          .toList();
      if (arabicLocales.isNotEmpty) {
        final normalizedRequested = localeId.toLowerCase().replaceAll('-', '_');
        final exactMatches = arabicLocales.where(
          (locale) =>
              locale.localeId.toLowerCase().replaceAll('-', '_') ==
              normalizedRequested,
        );
        targetLocale = exactMatches.isNotEmpty
            ? exactMatches.first.localeId
            : arabicLocales.first.localeId;
      }
    } catch (_) {}

    try {
      await _stt.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          // Do not force offline recognition. Many otherwise-supported phones
          // do not have the Arabic on-device model installed and silently
          // produce no words when `onDevice` is forced. The system recognizer
          // can still choose its local engine when it is available.
          onDevice: false,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 4),
          localeId: targetLocale,
          contextualPhrases: contextualPhrases.isEmpty
              ? null
              : contextualPhrases,
        ),
      );
      _hasStartedListening = true;
      // `SpeechToText.isListening` only becomes true after the platform emits
      // its asynchronous "listening" status. Reading it immediately here
      // incorrectly reports a successful native listen call as failed on real
      // devices. Reaching this line means the platform accepted the request;
      // later failures are delivered through `_onError`.
      return true;
    } catch (e) {
      _errorController.add(
        'تعذّر بدء الاستماع. تأكد من تفعيل خدمة التعرف على الكلام في الجهاز ثم حاول مجددًا: $e',
      );
      return false;
    }
  }

  @override
  Future<void> stopListening() async {
    if (_stt.isListening) {
      await _stt.stop();
    }
  }

  @override
  Future<void> cancelListening() async {
    if (_stt.isListening) {
      await _stt.cancel();
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (_resultsController.isClosed) return;

    if (kDebugMode) {
      debugPrint(
        '[Q14_STT_CALLBACK] isFinal=${result.finalResult} conf=${result.confidence} words="${result.recognizedWords}"',
      );
    }

    final alternates = result.alternates.map((a) => a.recognizedWords).toList();
    _resultsController.add(
      SpeechRecognitionResultData(
        recognizedWords: result.recognizedWords,
        isFinal: result.finalResult,
        confidence: result.confidence > 0 ? result.confidence : 1.0,
        alternates: alternates,
      ),
    );
  }

  void _onStatus(String status) {
    if (kDebugMode) {
      debugPrint('[Q14_STT_STATUS] status="$status"');
    }
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (!_errorController.isClosed) {
      final message = switch (error.errorMsg) {
        'error_no_match' =>
          'لم أتمكن من تمييز الكلام بوضوح. اقترب من الميكروفون وحاول مجددًا.',
        'error_speech_timeout' =>
          'لم يُسمع صوت لفترة. اضغط متابعة عندما تكون مستعدًا.',
        'error_audio' =>
          'تعذّر الوصول إلى الميكروفون. تحقق من عدم استخدامه في تطبيق آخر.',
        'error_busy' || 'error_client' =>
          'محرك التعرف الصوتي مشغول مؤقتًا. سيُعاد تشغيل الاستماع تلقائيًا.',
        'error_network' || 'error_network_timeout' => 'تعذّر الوصول إلى خدمة التعرف على الكلام. تحقق من الاتصال أو نزّل حزمة العربية للتعرف دون اتصال.',
        'error_language_not_supported' || 'error_language_unavailable' => 'اللغة العربية غير مفعّلة في خدمة التعرف على الكلام في الجهاز. أضف العربية من إعدادات اللغة ثم حاول مجددًا.',
        'error_permission' || 'error_permission_denied' =>
          'إذن الميكروفون أو التعرف على الكلام غير متاح.',
        _ => 'توقف محرك التعرف الصوتي. حاول بدء التسميع مرة أخرى.',
      };
      _errorController.add(message);
    }
  }

  @override
  Future<void> dispose() async {
    await cancelListening();
    await _resultsController.close();
    await _statusController.close();
    await _errorController.close();
  }
}

/// Controllable mock implementation of [SpeechRecognitionService] for deterministic testing.
class MockSpeechRecognitionService implements SpeechRecognitionService {
  MockSpeechRecognitionService({
    bool initialAvailable = true,
    bool initialPermission = true,
  }) : _isAvailable = initialAvailable,
       _hasPermission = initialPermission;

  bool _isAvailable;
  bool _hasPermission;
  bool _isListening = false;
  bool _isPermanentlyDenied = false;

  bool autoGrantOnRequest = false;

  int permissionRequestCount = 0;
  int openAppSettingsCount = 0;
  int initializeCount = 0;
  int startListeningCount = 0;
  String? lastLocaleId;
  List<String> lastContextualPhrases = const [];

  final _resultsController =
      StreamController<SpeechRecognitionResultData>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  void setAvailable(bool value) => _isAvailable = value;
  void setPermission(bool value) => _hasPermission = value;
  void setPermanentlyDenied(bool value) => _isPermanentlyDenied = value;

  @override
  Stream<SpeechRecognitionResultData> get resultsStream =>
      _resultsController.stream;

  @override
  Stream<String> get statusStream => _statusController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  bool get isAvailable => _isAvailable;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> initialize() async {
    initializeCount++;
    return _isAvailable && _hasPermission;
  }

  @override
  Future<bool> hasPermission() async => _hasPermission;

  @override
  Future<bool> requestPermission() async {
    permissionRequestCount++;
    if (_isPermanentlyDenied) {
      _hasPermission = false;
      return false;
    }
    if (autoGrantOnRequest) {
      _hasPermission = true;
    }
    return _hasPermission;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCount++;
    return true;
  }

  @override
  Future<bool> startListening({
    String localeId = 'ar_SA',
    List<String> contextualPhrases = const [],
  }) async {
    startListeningCount++;
    lastLocaleId = localeId;
    lastContextualPhrases = List.unmodifiable(contextualPhrases);
    if (!_hasPermission || !_isAvailable) return false;
    _isListening = true;
    _statusController.add('listening');
    return true;
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
    _statusController.add('notListening');
  }

  @override
  Future<void> cancelListening() async {
    _isListening = false;
    _statusController.add('notListening');
  }

  /// Injects simulated speech transcripts during tests.
  void emitTranscript(
    String words, {
    bool isFinal = false,
    double confidence = 1.0,
  }) {
    if (!_resultsController.isClosed) {
      _resultsController.add(
        SpeechRecognitionResultData(
          recognizedWords: words,
          isFinal: isFinal,
          confidence: confidence,
        ),
      );
    }
  }

  /// Injects simulated status events.
  void emitStatus(String status) {
    if (!_statusController.isClosed) {
      if (status == 'listening') {
        _isListening = true;
      } else if (status == 'notListening' || status == 'done') {
        _isListening = false;
      }
      _statusController.add(status);
    }
  }

  /// Injects simulated error events.
  void emitError(String error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
  }

  @override
  Future<void> dispose() async {
    _isListening = false;
    await _resultsController.close();
    await _statusController.close();
    await _errorController.close();
  }
}
