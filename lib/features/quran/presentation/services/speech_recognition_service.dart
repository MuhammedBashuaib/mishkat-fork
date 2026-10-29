import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
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

enum SpeechPermissionState {
  granted,
  denied,
  permanentlyDenied,
  restricted;

  bool get isGranted => this == SpeechPermissionState.granted;
  bool get requiresSettings =>
      this == SpeechPermissionState.permanentlyDenied ||
      this == SpeechPermissionState.restricted;
}

enum SpeechRecognitionFailureType {
  noMatch,
  timeout,
  audio,
  busy,
  network,
  languageUnavailable,
  permissionDenied,
  unknown,
}

class SpeechRecognitionFailure {
  const SpeechRecognitionFailure({
    required this.type,
    required this.message,
    this.isPermanent = false,
  });

  final SpeechRecognitionFailureType type;
  final String message;
  final bool isPermanent;
}

/// Abstract contract decoupling speech recognition and microphone capture from the application.
abstract class SpeechRecognitionService {
  /// Initializes the recognition engine and checks hardware availability.
  Future<bool> initialize();

  /// Whether microphone and speech recognition permissions are currently granted.
  Future<bool> hasPermission();

  /// Explicitly requests microphone and speech recognition permissions from the OS.
  Future<SpeechPermissionState> requestPermission();

  /// Opens application system settings on the device so the user can grant permission manually.
  Future<bool> openAppSettings();

  /// Opens the closest system page for configuring the speech recognizer and
  /// installing recognition languages. Falls back to app settings.
  Future<bool> openSpeechRecognitionSettings();

  /// Whether an Arabic recognition locale is installed. Returns `null` when
  /// the platform cannot provide a reliable locale list.
  Future<bool?> hasArabicLocale();

  /// Whether the platform recognizer is available and ready.
  bool get isAvailable;

  /// Whether the recognizer is currently active and listening to the microphone.
  bool get isListening;

  /// Stream of recognized transcript results emitted in real-time.
  Stream<SpeechRecognitionResultData> get resultsStream;

  /// Stream of recognizer status changes ('listening', 'notListening', 'done').
  Stream<String> get statusStream;

  /// Stream of recognition errors.
  Stream<SpeechRecognitionFailure> get errorStream;

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

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.dakomn.mishkatapp/speech_settings',
  );

  final _resultsController =
      StreamController<SpeechRecognitionResultData>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _errorController =
      StreamController<SpeechRecognitionFailure>.broadcast();

  bool _isInitialized = false;
  bool _hasStartedListening = false;

  @override
  Stream<SpeechRecognitionResultData> get resultsStream =>
      _resultsController.stream;

  @override
  Stream<String> get statusStream => _statusController.stream;

  @override
  Stream<SpeechRecognitionFailure> get errorStream => _errorController.stream;

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
      _errorController.add(
        SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.unknown,
          message: 'فشل تهيئة محرك التعرف الصوتي: $e',
        ),
      );
      _isInitialized = false;
      return false;
    }
  }

  @override
  Future<bool> hasPermission() async {
    try {
      if (kIsWeb) return await _stt.hasPermission;

      final microphone = await permissions.Permission.microphone.status;
      if (!microphone.isGranted) return false;

      if (Platform.isIOS) {
        final speech = await permissions.Permission.speech.status;
        return speech.isGranted;
      }
      return true;
    } catch (_) {
      try {
        return await _stt.hasPermission;
      } catch (_) {
        return false;
      }
    }
  }

  @override
  Future<SpeechPermissionState> requestPermission() async {
    try {
      final already = await hasPermission();
      if (already) return SpeechPermissionState.granted;

      if (!kIsWeb) {
        final microphone = await permissions.Permission.microphone.request();
        final microphoneState = _permissionState(microphone);
        if (!microphoneState.isGranted) return microphoneState;

        if (Platform.isIOS) {
          final speech = await permissions.Permission.speech.request();
          return _permissionState(speech);
        }
        return SpeechPermissionState.granted;
      }

      final available = await initialize();
      final hasPerm = await hasPermission();
      return hasPerm || available
          ? SpeechPermissionState.granted
          : SpeechPermissionState.denied;
    } catch (e) {
      _errorController.add(
        SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.permissionDenied,
          message: 'فشل طلب إذن الميكروفون: $e',
        ),
      );
      return SpeechPermissionState.denied;
    }
  }

  SpeechPermissionState _permissionState(permissions.PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return SpeechPermissionState.granted;
    }
    if (status.isPermanentlyDenied) {
      return SpeechPermissionState.permanentlyDenied;
    }
    if (status.isRestricted) return SpeechPermissionState.restricted;
    return SpeechPermissionState.denied;
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await permissions.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openSpeechRecognitionSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final opened = await _settingsChannel.invokeMethod<bool>(
          'openVoiceInputSettings',
        );
        if (opened == true) return true;
      } on PlatformException {
        // Fall through to the universally available application settings.
      } on MissingPluginException {
        // Fall through when running on an older native shell.
      }
    }
    return openAppSettings();
  }

  @override
  Future<bool?> hasArabicLocale() async {
    try {
      if (!_isInitialized) {
        final available = await initialize();
        if (!available) return null;
      }
      final locales = await _stt.locales().timeout(const Duration(seconds: 4));
      if (locales.isEmpty) return null;
      return locales.any(
        (locale) => locale.localeId.toLowerCase().startsWith('ar'),
      );
    } catch (_) {
      return null;
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
        SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.unknown,
          message:
              'تعذّر بدء الاستماع. تأكد من تفعيل خدمة التعرف على الكلام في الجهاز ثم حاول مجددًا: $e',
        ),
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
      final failure = switch (error.errorMsg) {
        'error_no_match' => const SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.noMatch,
          message: 'لم أتمكن من تمييز الكلام بوضوح. اقترب من الميكروفون وحاول مجددًا.',
        ),
        'error_speech_timeout' => const SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.timeout,
          message: 'لم يُسمع صوت لفترة. اضغط متابعة عندما تكون مستعدًا.',
        ),
        'error_audio' => const SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.audio,
          message:
              'تعذّر الوصول إلى الميكروفون. تحقق من عدم استخدامه في تطبيق آخر.',
        ),
        'error_busy' || 'error_client' => const SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.busy,
          message: 'محرك التعرف الصوتي مشغول مؤقتًا. سيُعاد تشغيل الاستماع تلقائيًا.',
        ),
        'error_network' ||
        'error_network_timeout' => const SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.network,
          message: 'تعذّر الوصول إلى خدمة التعرف على الكلام. تحقق من الاتصال أو نزّل حزمة العربية للتعرف دون اتصال.',
        ),
        'error_language_not_supported' ||
        'error_language_unavailable' => SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.languageUnavailable,
          message: 'العربية غير مفعّلة في خدمة التعرف الصوتي. افتح إعدادات الإدخال الصوتي وأضف العربية، ثم ارجع إلى مشكاة.',
          isPermanent: error.permanent,
        ),
        'error_permission' ||
        'error_permission_denied' => SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.permissionDenied,
          message: 'إذن الميكروفون أو التعرف على الكلام غير متاح. اسمح به من إعدادات التطبيق للمتابعة.',
          isPermanent: error.permanent,
        ),
        _ => SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.unknown,
          message: 'توقف محرك التعرف الصوتي. حاول بدء التسميع مرة أخرى.',
          isPermanent: error.permanent,
        ),
      };
      _errorController.add(failure);
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
    bool? initialArabicLocale = true,
  }) : _isAvailable = initialAvailable,
       _hasPermission = initialPermission,
       _hasArabicLocale = initialArabicLocale;

  bool _isAvailable;
  bool _hasPermission;
  bool _isListening = false;
  bool _isPermanentlyDenied = false;
  bool? _hasArabicLocale;

  bool autoGrantOnRequest = false;

  int permissionRequestCount = 0;
  int openAppSettingsCount = 0;
  int openSpeechRecognitionSettingsCount = 0;
  int initializeCount = 0;
  int startListeningCount = 0;
  String? lastLocaleId;
  List<String> lastContextualPhrases = const [];

  final _resultsController =
      StreamController<SpeechRecognitionResultData>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _errorController =
      StreamController<SpeechRecognitionFailure>.broadcast();

  void setAvailable(bool value) => _isAvailable = value;
  void setPermission(bool value) => _hasPermission = value;
  void setPermanentlyDenied(bool value) => _isPermanentlyDenied = value;
  void setArabicLocale(bool? value) => _hasArabicLocale = value;

  @override
  Stream<SpeechRecognitionResultData> get resultsStream =>
      _resultsController.stream;

  @override
  Stream<String> get statusStream => _statusController.stream;

  @override
  Stream<SpeechRecognitionFailure> get errorStream => _errorController.stream;

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
  Future<SpeechPermissionState> requestPermission() async {
    permissionRequestCount++;
    if (_isPermanentlyDenied) {
      _hasPermission = false;
      return SpeechPermissionState.permanentlyDenied;
    }
    if (autoGrantOnRequest) {
      _hasPermission = true;
    }
    return _hasPermission
        ? SpeechPermissionState.granted
        : SpeechPermissionState.denied;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCount++;
    return true;
  }

  @override
  Future<bool> openSpeechRecognitionSettings() async {
    openSpeechRecognitionSettingsCount++;
    return true;
  }

  @override
  Future<bool?> hasArabicLocale() async => _hasArabicLocale;

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
  void emitError(
    String error, {
    SpeechRecognitionFailureType type = SpeechRecognitionFailureType.unknown,
    bool isPermanent = false,
  }) {
    if (!_errorController.isClosed) {
      final resolvedType = type != SpeechRecognitionFailureType.unknown
          ? type
          : error.startsWith('لم أتمكن من تمييز الكلام')
          ? SpeechRecognitionFailureType.noMatch
          : error.startsWith('لم يُسمع صوت لفترة')
          ? SpeechRecognitionFailureType.timeout
          : error.startsWith('محرك التعرف الصوتي مشغول مؤقتًا')
          ? SpeechRecognitionFailureType.busy
          : SpeechRecognitionFailureType.unknown;
      _errorController.add(
        SpeechRecognitionFailure(
          type: resolvedType,
          message: error,
          isPermanent: isPermanent,
        ),
      );
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
