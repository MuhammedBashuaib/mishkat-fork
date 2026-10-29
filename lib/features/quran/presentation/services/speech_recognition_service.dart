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
  bool _isDisposed = false;
  bool _acceptRecognitionEvents = false;
  int _sessionGeneration = 0;
  int? _lastNativeStartGeneration;
  Future<bool>? _initialization;
  Future<bool>? _startOperation;
  Completer<bool>? _startAcknowledgement;

  static const _startupTimeout = Duration(seconds: 6);
  static const _localeTimeout = Duration(seconds: 3);

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<SpeechRecognitionResultData> get resultsStream =>
      _resultsController.stream;

  @override
  Stream<String> get statusStream => _statusController.stream;

  @override
  Stream<SpeechRecognitionFailure> get errorStream => _errorController.stream;

  @override
  bool get isAvailable => !_isDisposed && _isInitialized && _stt.isAvailable;

  @override
  bool get isListening => _acceptRecognitionEvents && _stt.isListening;

  @override
  Future<bool> initialize() async {
    if (_isDisposed) return false;
    if (_isInitialized && _stt.isAvailable) {
      _bindCallbacks();
      return true;
    }
    final pending = _initialization;
    if (pending != null) return pending;
    final initialization = _initializeEngine();
    _initialization = initialization;
    try {
      return await initialization;
    } finally {
      _initialization = null;
    }
  }

  Future<bool> _initializeEngine() async {
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
          // Use the system's configured recognizer. androidIntentLookup
          // selects the first installed service, which can select a different
          // (or unsupported) engine on phones with several voice services.
        ],
      );
      if (_isDisposed) return false;
      // SpeechToText() is a singleton and its initialize() ignores callbacks
      // after its first successful call. A reopened recitation page must own
      // the callbacks instead of sending them to the disposed previous page.
      _bindCallbacks();
      _isInitialized = available;
      return available;
    } catch (e) {
      if (!_errorController.isClosed) {
        _errorController.add(
          SpeechRecognitionFailure(
            type: SpeechRecognitionFailureType.unknown,
            message: 'فشل تهيئة محرك التعرف الصوتي: $e',
          ),
        );
      }
      _isInitialized = false;
      return false;
    }
  }

  void _bindCallbacks() {
    _stt.errorListener = _onError;
    _stt.statusListener = _onStatus;
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
    if (_isDisposed) return SpeechPermissionState.denied;
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
      if (!_errorController.isClosed) {
        _errorController.add(
          SpeechRecognitionFailure(
            type: SpeechRecognitionFailureType.permissionDenied,
            message: 'فشل طلب إذن الميكروفون: $e',
          ),
        );
      }
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
    // Android 13+ only enumerates the on-device model's languages. Missing
    // Arabic there does not mean that online Arabic recognition is unavailable.
    // In speech_to_text 7.5 the native locale call also never replies when the
    // device has no on-device service or its support check fails.
    if (_isAndroid || _isDisposed) return null;
    try {
      if (!_isInitialized) {
        final available = await initialize();
        if (!available) return null;
      }
      final locales = await _stt.locales().timeout(_localeTimeout);
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
    if (_isDisposed) return false;
    final pending = _startOperation;
    if (pending != null) return pending;
    final operation = _startListening(localeId, contextualPhrases);
    _startOperation = operation;
    try {
      return await operation;
    } finally {
      _startOperation = null;
    }
  }

  Future<bool> _startListening(
    String localeId,
    List<String> contextualPhrases,
  ) async {
    final generation = ++_sessionGeneration;
    final initialized = await initialize();
    if (!initialized || !_isCurrentSession(generation)) return false;

    // speech_to_text requires every completed/timed-out session to be ended
    // with stop/cancel before another listen call. `isListening` is already
    // false by the time the platform emits `done`, so checking it alone leaves
    // the native recognizer busy on the next cycle.
    if (_hasStartedListening) {
      _acceptRecognitionEvents = false;
      try {
        await _stt.cancel();
      } catch (_) {}
      _hasStartedListening = false;
    }
    if (!_isCurrentSession(generation)) return false;

    // Android accepts a BCP-47 locale directly, including online-only Arabic.
    // Never put its unreliable on-device language enumeration on the startup
    // path: this used to prevent the microphone opening on Android 13+ phones.
    var targetLocale = _isAndroid ? localeId.replaceAll('_', '-') : localeId;
    if (!_isAndroid) {
      try {
        final locales = await _stt.locales().timeout(_localeTimeout);
        final arabicLocales = locales
            .where((l) => l.localeId.toLowerCase().startsWith('ar'))
            .toList();
        if (arabicLocales.isNotEmpty) {
          final normalizedRequested = localeId.toLowerCase().replaceAll(
            '-',
            '_',
          );
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
    }
    if (!_isCurrentSession(generation)) return false;

    final acknowledgement = Completer<bool>();
    _startAcknowledgement = acknowledgement;
    _acceptRecognitionEvents = true;
    _hasStartedListening = true;
    _lastNativeStartGeneration = generation;
    try {
      await _stt
          .listen(
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
          )
          .then((_) async {
            // The plugin installs its pause timer after the platform replies.
            // A late reply after cancel/dispose must not leave that timer alive.
            // Only clean up while this adapter/session still owns the engine.
            if (!_isCurrentSession(generation) &&
                _lastNativeStartGeneration == generation &&
                _stt.statusListener == _onStatus) {
              try {
                await _stt.cancel();
              } catch (_) {}
            }
          })
          .timeout(_startupTimeout);
      // listen() discards the platform's bool result. Waiting for its status
      // callback catches both silent rejection and delayed native startup,
      // without incorrectly treating an asynchronous start as a failure.
      final started = await acknowledgement.future.timeout(_startupTimeout);
      return started && _isCurrentSession(generation);
    } catch (e) {
      if (_isCurrentSession(generation)) {
        _errorController.add(
          SpeechRecognitionFailure(
            type: SpeechRecognitionFailureType.unknown,
            message: e is TimeoutException
                ? 'لم تبدأ خدمة التعرف على الكلام. تحقق من تفعيل الميكروفون وخدمة الإدخال الصوتي ثم أعد المحاولة.'
                : 'تعذّر بدء الاستماع. تأكد من تفعيل خدمة التعرف على الكلام في الجهاز ثم حاول مجددًا: $e',
          ),
        );
        await cancelListening();
      }
      return false;
    } finally {
      if (identical(_startAcknowledgement, acknowledgement)) {
        _startAcknowledgement = null;
      }
    }
  }

  bool _isCurrentSession(int generation) =>
      !_isDisposed && generation == _sessionGeneration;

  void _acknowledgeStart(bool started) {
    final acknowledgement = _startAcknowledgement;
    if (acknowledgement != null && !acknowledgement.isCompleted) {
      acknowledgement.complete(started);
    }
  }

  void _invalidateSession() {
    _sessionGeneration++;
    _acceptRecognitionEvents = false;
    _acknowledgeStart(false);
  }

  @override
  Future<void> stopListening() async {
    _invalidateSession();
    // The native microphone may already be starting before isListening is
    // reported. End that request as well as an acknowledged listening session.
    if (_hasStartedListening) {
      await _stt.stop();
    }
  }

  @override
  Future<void> cancelListening() async {
    _invalidateSession();
    if (_hasStartedListening) {
      _hasStartedListening = false;
      await _stt.cancel();
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (_resultsController.isClosed || !_acceptRecognitionEvents) return;
    _acknowledgeStart(true);

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
    if (!_acceptRecognitionEvents) return;
    if (status == SpeechToText.listeningStatus) _acknowledgeStart(true);
    if (kDebugMode) {
      debugPrint('[Q14_STT_STATUS] status="$status"');
    }
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (!_acceptRecognitionEvents) return;
    _acknowledgeStart(false);
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
        'error_audio' || 'error_audio_error' => const SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.audio,
          message:
              'تعذّر الوصول إلى الميكروفون. تحقق من عدم استخدامه في تطبيق آخر.',
        ),
        'error_busy' || 'error_client' => const SpeechRecognitionFailure(
          type: SpeechRecognitionFailureType.busy,
          message: 'محرك التعرف الصوتي مشغول مؤقتًا. سيُعاد تشغيل الاستماع تلقائيًا.',
        ),
        'error_network' ||
        'error_server' ||
        'error_server_disconnected' ||
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
    if (_isDisposed) return;
    _isDisposed = true;
    try {
      await cancelListening();
    } catch (_) {
      // Closing a page must still release its listeners if the OS is already
      // tearing down the microphone service.
    }

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
