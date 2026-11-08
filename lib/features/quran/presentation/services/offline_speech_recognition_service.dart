import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import 'speech_recognition_service.dart';
import 'speech_segmenter.dart';
import 'recitation_pause_diagnostics.dart';

/// Optional microphone feedback, without making injected recognizers implement it.
abstract interface class OfflineSpeechDiagnostics {
  Stream<double> get soundLevelStream;
  Stream<bool> get processingStream;
  bool get isOffline;
}

/// Arabic FastConformer CTC bundled with Android, running entirely on the device.
///
/// Finals contain completed VAD segments; previews are replaceable snapshots of
/// the active segment. Expected Quran words
/// are deliberately never passed to the acoustic recognizer. No recording is
/// written to disk, uploaded, or sent to a system/cloud recognizer.
class OfflineSpeechRecognitionService
    implements
        SpeechRecognitionService,
        OfflineSpeechDiagnostics,
        RecitationPauseDiagnostics {
  OfflineSpeechRecognitionService({
    this.channel = const MethodChannel(
      'com.dakomn.mishkatapp/offline_recitation',
    ),
    Stream<Object?>? audioEvents,
    SpeechSegmenter? segmenter,
    int Function()? clockMs,
  }) : _audioEvents = audioEvents ?? _sharedAudioEvents,
       _segmenter = segmenter ?? SpeechSegmenter(),
       _clockMs = clockMs ?? _monotonicClock(),
       _clientId = '${DateTime.now().microsecondsSinceEpoch}-${_nextClient++}';

  static int Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMilliseconds;
  }

  static int _nextClient = 0;
  // Reopened pages can overlap async disposal. One native subscription prevents
  // an old page's cancellation from detaching the new page's microphone stream.
  static final Stream<Object?> _sharedAudioEvents = const EventChannel(
    'com.dakomn.mishkatapp/offline_recitation/audio',
  ).receiveBroadcastStream();
  static const _maxQueuedSegments = 4;
  // Opt-in numeric timing for physical-device profiling; never logs audio/text.
  static const _traceTiming = bool.fromEnvironment('MISHKAT_ASR_TIMING');
  final MethodChannel channel;
  final Stream<Object?> _audioEvents;
  final SpeechSegmenter _segmenter;
  final int Function() _clockMs;
  final String _clientId;
  final _results = StreamController<SpeechRecognitionResultData>.broadcast(
    sync: true,
  );
  final _statuses = StreamController<String>.broadcast(sync: true);
  final _errors = StreamController<SpeechRecognitionFailure>.broadcast(
    sync: true,
  );
  final _levels = StreamController<double>.broadcast(sync: true);
  final _processing = StreamController<bool>.broadcast(sync: true);
  final _feedbackQuiet = StreamController<bool>.broadcast(sync: true);
  bool _quietForFeedback = false;
  final _queue = Queue<_PendingSegment>();
  _PreviewRequest? _pendingPreview;
  _DecodedPreview? _decodedPreview;
  int _previewRevision = -1;
  int _lastPreviewMs = 0;
  int _lastPauseSamples = -1;
  int _previewGapMs = _previewIntervalMs;
  static const _firstPreviewMs = 900;
  static const _previewIntervalMs = 600;
  StreamSubscription<Object?>? _audioSubscription;
  Future<bool>? _initialization;
  Future<bool>? _startup;
  Future<void>? _release;
  Future<void>? _draining;
  bool _initialized = false;
  bool _listening = false;
  bool _acceptAudio = false;
  bool _stopRequested = false;
  bool _disposed = false;
  int _generation = 0;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get supportsPlatform => _supported;
  String _session(int generation) => '$_clientId:$generation';
  bool _current(int generation) => !_disposed && generation == _generation;

  @override
  bool get isOffline => true;
  @override
  bool get isAvailable => _initialized && !_disposed;
  @override
  bool get isListening => _listening && !_disposed;
  @override
  Stream<SpeechRecognitionResultData> get resultsStream => _results.stream;
  @override
  Stream<String> get statusStream => _statuses.stream;
  @override
  Stream<SpeechRecognitionFailure> get errorStream => _errors.stream;
  @override
  Stream<double> get soundLevelStream => _levels.stream;
  @override
  Stream<bool> get processingStream => _processing.stream;
  @override
  Stream<bool> get feedbackQuietStream => _feedbackQuiet.stream;
  @override
  bool get isQuietForFeedback => _listening && _quietForFeedback && !_disposed;

  void _setFeedbackQuiet(bool quiet) {
    if (_quietForFeedback == quiet) return;
    _quietForFeedback = quiet;
    if (!_disposed) _feedbackQuiet.add(quiet);
  }

  @override
  Future<bool> initialize() async {
    if (_disposed) return false;
    if (_initialized) return true;
    final pending = _initialization;
    if (pending != null) return pending;
    final operation = _initialize();
    _initialization = operation;
    try {
      return await operation;
    } finally {
      _initialization = null;
    }
  }

  Future<bool> _initialize() async {
    if (!_supported) {
      _fail(
        SpeechRecognitionFailureType.languageUnavailable,
        'التسميع بدون إنترنت متاح على أجهزة Android في هذه النسخة.',
        permanent: true,
      );
      return false;
    }
    _audioSubscription ??= _audioEvents.listen(
      _onAudio,
      onError: (_) {
        if (!_disposed) _captureFailed();
      },
    );
    try {
      final loaded = await channel
          .invokeMethod<bool>('initialize', {'clientId': _clientId})
          .timeout(const Duration(seconds: 40));
      if (_disposed) return false;
      _initialized = loaded == true;
      if (!_initialized) throw StateError('Model could not load');
      return true;
    } catch (_) {
      _initialized = false;
      // A timed-out native load can still finish on its worker. Queue a lease
      // release behind it rather than retaining a model no page can use.
      unawaited(
        channel
            .invokeMethod<void>('release', {'clientId': _clientId})
            .catchError((Object _) {}),
      );
      _fail(
        SpeechRecognitionFailureType.languageUnavailable,
        'تعذّر تجهيز نموذج التسميع المدمج. أغلق التطبيقات الأخرى وحاول مجددًا؛ '
        'إذا استمر التعذّر فأعد تثبيت التطبيق.',
        permanent: true,
      );
      return false;
    }
  }

  @override
  Future<bool> hasPermission() async {
    if (!_supported || _disposed) return false;
    try {
      return await channel.invokeMethod<bool>('hasPermission') == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SpeechPermissionState> requestPermission() async {
    if (!_supported) return SpeechPermissionState.restricted;
    final status = await permissions.Permission.microphone.request();
    if (status.isGranted) return SpeechPermissionState.granted;
    if (status.isPermanentlyDenied) {
      return SpeechPermissionState.permanentlyDenied;
    }
    if (status.isRestricted) return SpeechPermissionState.restricted;
    return SpeechPermissionState.denied;
  }

  @override
  Future<bool> openAppSettings() => permissions.openAppSettings();
  @override
  Future<bool> openSpeechRecognitionSettings() => openAppSettings();
  @override
  Future<bool?> hasArabicLocale() async => initialize();

  @override
  Future<bool> startListening({
    String localeId = 'ar_SA',
    List<String> contextualPhrases = const [],
  }) async {
    if (_disposed) return false;
    if (_listening) return true;
    final pending = _startup;
    if (pending != null) return pending;
    final generation = ++_generation;
    _stopRequested = false;
    final operation = _start(generation);
    _startup = operation;
    try {
      return await operation;
    } finally {
      _startup = null;
    }
  }

  Future<bool> _start(int generation) async {
    await _release;
    if (!_current(generation) || _stopRequested) return false;
    if (!await initialize()) return false;
    if (!_current(generation) || _stopRequested) return false;
    if (!await hasPermission()) {
      _fail(
        SpeechRecognitionFailureType.permissionDenied,
        'اسمح بالميكروفون لبدء التسميع داخل الجهاز.',
        permanent: true,
      );
      return false;
    }
    if (!_current(generation) || _stopRequested) return false;
    _segmenter.reset();
    _setFeedbackQuiet(false);
    _queue.clear();
    _pendingPreview = null;
    _decodedPreview = null;
    _previewRevision = -1;
    _lastPauseSamples = -1;
    _previewGapMs = _previewIntervalMs;
    _acceptAudio = true;
    try {
      final started = await channel
          .invokeMethod<bool>('start', {'sessionId': _session(generation)})
          .timeout(const Duration(seconds: 8));
      if (!_current(generation) || _stopRequested) {
        await _stopNative(generation);
        return false;
      }
      if (started != true) throw StateError('Microphone did not start');
      _listening = true;
      _statuses.add('listening');
      return true;
    } catch (_) {
      if (_current(generation) && !_stopRequested) {
        _acceptAudio = false;
        await _stopNative(generation);
        _fail(
          SpeechRecognitionFailureType.audio,
          'تعذّر فتح الميكروفون. أغلق أي تطبيق يستخدمه ثم حاول مجددًا.',
        );
      }
      return false;
    }
  }

  void _onAudio(Object? event) {
    if (_disposed ||
        !_acceptAudio ||
        event is! Map ||
        event['sessionId'] != _session(_generation)) {
      return;
    }
    if (event['type'] == 'interrupted' || event['type'] == 'error') {
      _captureFailed();
      return;
    }
    final raw = event['pcm'];
    if (raw is! Uint8List || raw.length.isOdd) return;
    final level = event['level'];
    if (level is num) _levels.add(level.toDouble().clamp(0, 1));
    final data = ByteData.sublistView(raw);
    final pcm = Int16List(raw.length ~/ 2);
    for (var index = 0; index < pcm.length; index++) {
      pcm[index] = data.getInt16(index * 2, Endian.little);
    }
    for (final segment in _segmenter.push(pcm)) {
      if (_queue.length >= _maxQueuedSegments) {
        // Never silently skip a segment while claiming the reader made a mistake.
        unawaited(cancelListening());
        _fail(
          SpeechRecognitionFailureType.audio,
          'تأخر تحليل التلاوة فتوقف الاستماع. خذ وقفة ثم تابع من آخر كلمة مؤكدة.',
        );
        return;
      }
      _queue.add(_PendingSegment(_generation, segment));
    }
    // Observe the existing VAD only. Never mute, skip or alter microphone PCM
    // for a UI cue: speech can resume at any instant during a short sound.
    _setFeedbackQuiet(!_stopRequested && _segmenter.isAtQuietBoundary);
    if (_previewRevision != _segmenter.revision) {
      _previewRevision = _segmenter.revision;
      _lastPreviewMs = 0;
      _lastPauseSamples = -1;
      _pendingPreview = null;
    }
    _requestPreview();
    if (_queue.isNotEmpty || _pendingPreview != null) unawaited(_pump());
  }

  void _requestPreview() {
    if (_stopRequested || _queue.isNotEmpty) return;
    if (_segmenter.hasPendingPause) {
      // Wait only for the same post-roll used by the eventual final. This does
      // not close the utterance or shorten the VAD's interruption protection.
      final sampleCount = _segmenter.pauseSnapshotSampleCount;
      _pendingPreview = sampleCount != null && sampleCount != _lastPauseSamples
          ? _PreviewRequest(_generation, _segmenter.revision, atPause: true)
          : null;
      return;
    }
    if (_pendingPreview?.atPause ?? false) _pendingPreview = null;
    final bufferedMs = _segmenter.bufferedDurationMs;
    if (_continuousPreviewDue(bufferedMs)) {
      // Store intent, not an aging PCM copy. The decoder snapshots the freshest
      // audio when it becomes free; at most one preview can be waiting.
      _pendingPreview = _PreviewRequest(_generation, _segmenter.revision);
    }
  }

  bool _continuousPreviewDue(int bufferedMs) =>
      bufferedMs >= _firstPreviewMs &&
      (_lastPreviewMs == 0 || bufferedMs - _lastPreviewMs >= _previewGapMs);

  void _captureFailed() {
    if (!_acceptAudio || _disposed) return;
    unawaited(cancelListening());
    _fail(
      SpeechRecognitionFailureType.audio,
      'توقف الميكروفون. ارجع إلى التطبيق واضغط متابعة لاستكمال التسميع.',
    );
  }

  Future<void> _pump() {
    final pending = _draining;
    if (pending != null) return pending;
    if (_queue.isEmpty && _pendingPreview == null) return Future.value();
    _processing.add(true);
    final operation = _drain().whenComplete(() {
      _draining = null;
      if (!_disposed) _processing.add(false);
    });
    _draining = operation;
    return operation;
  }

  Future<void> _drain() async {
    while ((_queue.isNotEmpty || _pendingPreview != null) && !_disposed) {
      // Completed speech always takes precedence over visual previews.
      final _PendingSegment item;
      if (_queue.isNotEmpty) {
        item = _queue.removeFirst();
      } else {
        final request = _pendingPreview!;
        _pendingPreview = null;
        if (!_current(request.generation) ||
            _stopRequested ||
            request.revision != _segmenter.revision) {
          continue;
        }
        final bufferedMs = _segmenter.bufferedDurationMs;
        if (!request.atPause &&
            (_segmenter.hasPendingPause ||
                !_continuousPreviewDue(bufferedMs))) {
          continue;
        }
        final snapshot = request.atPause
            ? _segmenter.pauseSnapshot()
            : _segmenter.snapshot();
        if (snapshot == null ||
            (request.atPause && snapshot.samples.length == _lastPauseSamples)) {
          continue;
        }
        _lastPreviewMs = bufferedMs;
        if (request.atPause) _lastPauseSamples = snapshot.samples.length;
        item = _PendingSegment(request.generation, snapshot, isFinal: false);
      }
      if (!_isUsable(item)) continue;
      try {
        final cached = _decodedPreview;
        final reuse =
            item.isFinal && cached != null && _sameAudio(cached.item, item);
        final startedMs = _clockMs();
        final String? text;
        if (reuse) {
          text = cached.text;
        } else {
          final bytes = ByteData(item.segment.samples.length * 2);
          for (var index = 0; index < item.segment.samples.length; index++) {
            bytes.setInt16(
              index * 2,
              item.segment.samples[index],
              Endian.little,
            );
          }
          text = await channel
              .invokeMethod<String>('transcribe', {
                'pcm': bytes.buffer.asUint8List(),
                'sessionId': _session(item.generation),
              })
              .timeout(const Duration(seconds: 30));
        }
        final decodeMs = (_clockMs() - startedMs).clamp(0, 30000);
        if (!item.isFinal && _current(item.generation)) {
          // A serial decoder already bounds work. Leave a small breathing room
          // on slower phones without adding another full decoding-time delay.
          _previewGapMs = (decodeMs * 1.1).round().clamp(
            _previewIntervalMs,
            2400,
          );
          // An in-flight preview may finish after VAD closes its utterance.
          // Keep its result for the queued final only if identity AND every PCM
          // sample match; no provisional text becomes a final by itself.
          if (text != null) _decodedPreview = _DecodedPreview(item, text);
        } else if (item.isFinal) {
          _decodedPreview = null;
        }
        if (!_isUsable(item)) continue;
        if (kDebugMode || _traceTiming) {
          debugPrint(
            '[MISHKAT_ASR_TIMING] final=${item.isFinal} '
            'audioMs=${item.segment.samples.length * 1000 ~/ 16000} '
            'decodeMs=$decodeMs reused=$reuse',
          );
        }
        if (text != null) {
          _results.add(
            SpeechRecognitionResultData(
              recognizedWords: text.trim(),
              isFinal: item.isFinal,
              // This CTC decoder supplies no calibrated confidence. The contract's
              // default 1.0 means unknown here; strict text alignment decides whether
              // anything is confirmed. Never invent acoustic confidence scores.
            ),
          );
        }
      } catch (_) {
        if (_isUsable(item)) {
          unawaited(cancelListening());
          _fail(
            SpeechRecognitionFailureType.audio,
            'تعذّر تحليل آخر مقطع. تابع من آخر كلمة مؤكدة بعد التأكد من وضوح الصوت.',
          );
        }
      }
    }
  }

  bool _isUsable(_PendingSegment item) =>
      _current(item.generation) &&
      (item.isFinal ||
          (!_stopRequested && item.segment.revision == _segmenter.revision));

  bool _sameAudio(_PendingSegment previous, _PendingSegment current) =>
      previous.generation == current.generation &&
      previous.segment.revision == current.segment.revision &&
      previous.segment.forced == current.segment.forced &&
      listEquals(previous.segment.samples, current.segment.samples);

  @override
  Future<void> stopListening() {
    _setFeedbackQuiet(false);
    _stopRequested = true;
    _pendingPreview = null;
    _listening = false;
    final pending = _release;
    if (pending != null) return pending;
    final operation = _stop(_generation);
    _release = operation;
    return operation.whenComplete(() {
      _release = null;
    });
  }

  Future<void> _stop(int generation) async {
    // Native stop joins the capture thread. Its already-posted PCM events arrive
    // before its method result, so the final consonant is included before flush.
    await _stopNative(generation);
    if (!_current(generation)) return;
    _acceptAudio = false;
    final last = _segmenter.flush();
    if (last != null) _queue.add(_PendingSegment(generation, last));
    while ((_draining != null || _queue.isNotEmpty) && _current(generation)) {
      await _pump();
    }
    if (_current(generation)) {
      _levels.add(0);
      _statuses.add('done');
    }
  }

  @override
  Future<void> cancelListening() async {
    _setFeedbackQuiet(false);
    final generation = _generation++;
    _stopRequested = true;
    _acceptAudio = false;
    _listening = false;
    _queue.clear();
    _pendingPreview = null;
    _decodedPreview = null;
    _segmenter.reset();
    if (!_disposed) _levels.add(0);
    final pending = _release;
    if (pending != null) return pending;
    final operation = _stopNative(generation);
    _release = operation;
    try {
      await operation;
    } finally {
      _release = null;
    }
  }

  Future<void> _stopNative(int generation) async {
    if (!_supported) return;
    try {
      await channel
          .invokeMethod<void>('stop', {'sessionId': _session(generation)})
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Native host-stop also releases capture if the activity/engine went away.
    }
  }

  void _fail(
    SpeechRecognitionFailureType type,
    String message, {
    bool permanent = false,
  }) {
    if (_disposed) return;
    _errors.add(
      SpeechRecognitionFailure(
        type: type,
        message: message,
        isPermanent: permanent,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancelListening();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    try {
      await channel.invokeMethod<void>('release', {'clientId': _clientId});
    } catch (_) {}
    await Future.wait([
      _results.close(),
      _statuses.close(),
      _errors.close(),
      _levels.close(),
      _processing.close(),
      _feedbackQuiet.close(),
    ]);
  }
}

class _PendingSegment {
  const _PendingSegment(this.generation, this.segment, {this.isFinal = true});
  final int generation;
  final SpeechSegment segment;
  final bool isFinal;
}

class _PreviewRequest {
  const _PreviewRequest(this.generation, this.revision, {this.atPause = false});
  final int generation;
  final int revision;
  final bool atPause;
}

class _DecodedPreview {
  const _DecodedPreview(this.item, this.text);
  final _PendingSegment item;
  final String text;
}
