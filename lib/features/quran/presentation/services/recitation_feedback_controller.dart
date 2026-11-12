import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../settings/data/models/app_settings.dart';
import '../../data/models/recitation_feedback_event.dart';
import '../cubit/quran_oral_recitation_cubit.dart';
import '../cubit/quran_oral_recitation_state.dart';
import 'recitation_pause_diagnostics.dart';
import 'speech_recognition_service.dart';

void _traceFeedback(String message) {
  if (kDebugMode) debugPrint('[MISHKAT_FEEDBACK] $message');
}

/// Foreground effects are independent of the Quran/background audio player.
abstract interface class RecitationFeedbackOutput {
  Future<void> prepare();
  Future<bool> play(RecitationCue cue);
  Future<void> vibrate(RecitationCue cue);
  Future<void> stop();
  Future<void> dispose();
}

class NativeRecitationFeedbackOutput implements RecitationFeedbackOutput {
  NativeRecitationFeedbackOutput({
    this.channel = const MethodChannel(
      'com.dakomn.mishkatapp/recitation_feedback',
    ),
  });

  static int _nextOwner = 0;
  final MethodChannel channel;
  final String _owner =
      '${DateTime.now().microsecondsSinceEpoch}:${_nextOwner++}';
  Future<void>? _ready;
  Future<void>? _loading;
  bool _prepared = false;
  bool _disposed = false;

  bool get _supportsSound =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> prepare() async {
    if (_disposed || !_supportsSound) return;
    // Native audio can be disarmed by an interruption without a page change.
    // Refresh arming on each explicit prepare; native players cache the assets.
    // Only concurrent preparations share a call.
    final pending = _loading ??= channel.invokeMethod<void>('prepare', {
      'ownerId': _owner,
    });
    _ready = pending;
    _prepared = false;
    try {
      await pending;
      // Stopping, replacing or disposing a preparation must not let its late
      // completion re-arm sound for a session that has already moved on.
      if (!_disposed && identical(_ready, pending)) _prepared = true;
    } on Object catch (error) {
      _traceFeedback('native prepare failed: $error');
      if (identical(_ready, pending)) {
        _ready = null;
        _prepared = false;
      }
    } finally {
      if (identical(_loading, pending)) _loading = null;
    }
  }

  @override
  Future<bool> play(RecitationCue cue) async {
    // Never queue playback behind asset loading. The controller rechecks the
    // speech pause, cue expiry and session after awaiting prepare itself.
    if (_disposed || !_supportsSound || !_prepared) return false;
    final preparation = _ready;
    try {
      final played = await channel.invokeMethod<bool>('play', {
        'ownerId': _owner,
        'cue': cue.name,
      });
      return played == true &&
          !_disposed &&
          _prepared &&
          identical(_ready, preparation);
    } on Object catch (error) {
      _traceFeedback('native play failed cue=${cue.name}: $error');
      return false;
    }
  }

  @override
  Future<void> vibrate(RecitationCue cue) async {
    if (_disposed) return;
    try {
      if (cue == RecitationCue.mistake) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.lightImpact();
      }
    } on Object {
      // Feedback never owns recognition or changes a successful session.
    }
  }

  @override
  Future<void> stop() async {
    _ready = null;
    _loading = null;
    _prepared = false;
    if (_disposed || !_supportsSound) return;
    try {
      await channel.invokeMethod<void>('stop', {'ownerId': _owner});
    } on Object {
      // The activity may already have stopped or detached.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ready = null;
    _loading = null;
    _prepared = false;
    if (!_supportsSound) return;
    try {
      await channel.invokeMethod<void>('dispose', {'ownerId': _owner});
    } on Object {
      // Native teardown may precede this page's disposal.
    }
  }
}

/// Consumes confirmed guidance events; it never writes to the recitation Cubit.
/// One recent cue may wait for a real VAD pause, with no queue of old mistakes.
class RecitationFeedbackController {
  RecitationFeedbackController({
    required QuranOralRecitationCubit cubit,
    RecitationFeedbackMode mode = RecitationFeedbackMode.sound,
    RecitationFeedbackOutput? output,
  }) : this.bind(
         events: cubit.feedbackStream,
         states: cubit.stream,
         currentState: () => cubit.state,
         speechService: cubit.speechService,
         mode: mode,
         output: output,
       );

  @visibleForTesting
  RecitationFeedbackController.bind({
    required Stream<RecitationFeedbackEvent> events,
    required Stream<QuranOralRecitationState> states,
    required QuranOralRecitationState Function() currentState,
    required SpeechRecognitionService speechService,
    this._mode = RecitationFeedbackMode.sound,
    RecitationFeedbackOutput? output,
    int Function()? nowMs,
  }) : _state = currentState,
       _speech = speechService,
       _output = output ?? NativeRecitationFeedbackOutput(),
       _nowMs = nowMs ?? _monotonicClock() {
    _session = _state().sessionId;
    _eventSubscription = events.listen(_receive);
    _stateSubscription = states.listen(_onState);
    if (_speech is RecitationPauseDiagnostics) {
      _quietSubscription = (_speech as RecitationPauseDiagnostics)
          .feedbackQuietStream
          .listen((_) => _flush());
    }
    if (_mode == RecitationFeedbackMode.sound) unawaited(_prepare());
  }

  static int Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMilliseconds;
  }

  final QuranOralRecitationState Function() _state;
  final SpeechRecognitionService _speech;
  final RecitationFeedbackOutput _output;
  final int Function() _nowMs;
  late final StreamSubscription<RecitationFeedbackEvent> _eventSubscription;
  late final StreamSubscription<QuranOralRecitationState> _stateSubscription;
  StreamSubscription<bool>? _quietSubscription;
  RecitationFeedbackMode _mode;
  RecitationFeedbackEvent? _pending;
  String? _session;
  Timer? _timer;
  int _expiresAt = 0;
  int _generation = 0;
  int _lastCueAt = -100000;
  int _lastMistakeAt = -100000;
  bool _foreground = true;
  bool _disposed = false;
  bool _flushing = false;

  Future<void> _prepare() async {
    try {
      await _output.prepare();
    } on Object {
      // Preparation is optional and must not delay or fail recognition.
    }
  }

  void setMode(RecitationFeedbackMode mode) {
    if (_disposed || _mode == mode) return;
    _mode = mode;
    _cancel();
    if (_foreground && mode == RecitationFeedbackMode.sound) {
      unawaited(_prepare());
    }
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    _cancel();
    if (foreground && _mode == RecitationFeedbackMode.sound) {
      unawaited(_prepare());
    }
  }

  void _onState(QuranOralRecitationState _) {
    if (_disposed) return;
    // Cubit delivers state snapshots asynchronously, while confirmed feedback
    // is synchronous. A queued draining snapshot may arrive after completion
    // has already prepared its cue; only the current state can disarm it.
    final state = _state();
    if (_session != state.sessionId) {
      _traceFeedback('cancel: session changed');
      _session = state.sessionId;
      _cancel();
      _lastCueAt = _lastMistakeAt = -100000;
    }
    if (state.isDraining ||
        (!state.isListening && !state.isPaused && !state.isCompleted)) {
      if (_pending != null) {
        _traceFeedback('cancel pending: draining=${state.isDraining}');
      }
      _cancel();
    } else if (_pending != null && !_relevant(_pending!)) {
      _clearPending();
    }
  }

  void _receive(RecitationFeedbackEvent event) {
    _traceFeedback(
      'event=${event.cue.name} mode=${_mode.name} '
      'foreground=$_foreground disposed=$_disposed '
      'relevant=${_relevant(event)} quiet=$_maySound '
      'capture=${_speech.isListening}',
    );
    if (_disposed || !_foreground || _mode == RecitationFeedbackMode.silent) {
      return;
    }
    if (!_relevant(event)) return;
    // A positive cue must never hide a simultaneous unresolved error.
    if (_pending?.cue == RecitationCue.mistake &&
        _relevant(_pending!) &&
        event.cue != RecitationCue.mistake &&
        event.cue != RecitationCue.paused &&
        event.cue != RecitationCue.complete) {
      return;
    }
    _pending = event;
    final lifetimeMs = event.cue == RecitationCue.ready ? 350 : 2200;
    _expiresAt = _nowMs() + lifetimeMs;
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: lifetimeMs), _flush);
    unawaited(_flush());
  }

  bool _relevant(RecitationFeedbackEvent event) {
    final state = _state();
    if (state.sessionId != event.sessionId || state.isDraining) return false;
    return switch (event.cue) {
      RecitationCue.ready => state.isListening && _speech.isListening,
      RecitationCue.mistake =>
        ((state.isListening && _speech.isListening) ||
                (state.isCompleted && !_speech.isListening)) &&
            event.wordIndices.any(state.unresolvedMistakeWordIndices.contains),
      RecitationCue.corrected =>
        state.isListening &&
            _speech.isListening &&
            state.unresolvedMistakeWordIndices.isEmpty &&
            event.wordIndices.isNotEmpty,
      RecitationCue.paused =>
        !state.isListening &&
            !_speech.isListening &&
            (state.isPaused || state.isCompleted),
      RecitationCue.complete => state.isCompleted && !_speech.isListening,
    };
  }

  bool get _maySound {
    if (!_speech.isListening) return true;
    // No guessing from loudness. Use the same VAD as the offline recognizer.
    return _speech is RecitationPauseDiagnostics &&
        (_speech as RecitationPauseDiagnostics).isQuietForFeedback;
  }

  Future<void> _flush() async {
    if (_flushing || _disposed || !_foreground || _pending == null) return;
    final event = _pending!;
    if (_mode == RecitationFeedbackMode.silent ||
        _nowMs() >= _expiresAt ||
        !_relevant(event)) {
      _traceFeedback(
        'drop=${event.cue.name} mode=${_mode.name} '
        'expired=${_nowMs() >= _expiresAt} relevant=${_relevant(event)}',
      );
      _clearPending();
      return;
    }
    final gap = event.cue == RecitationCue.mistake
        ? 1200 - (_nowMs() - _lastMistakeAt)
        : 0;
    final spacing = 320 - (_nowMs() - _lastCueAt);
    final delay = gap > spacing ? gap : spacing;
    if (delay > 0) {
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: delay), _flush);
      return;
    }
    if (_mode == RecitationFeedbackMode.sound && !_maySound) {
      _traceFeedback('wait for quiet: ${event.cue.name}');
      return;
    }
    final generation = _generation;
    _flushing = true;
    try {
      if (_mode == RecitationFeedbackMode.sound) await _prepare();
      if (_disposed ||
          !_foreground ||
          generation != _generation ||
          !identical(event, _pending) ||
          !_relevant(event)) {
        _traceFeedback('cancel after preparation: ${event.cue.name}');
        return;
      }
      if (_nowMs() >= _expiresAt) {
        _clearPending();
        return;
      }
      if (_mode == RecitationFeedbackMode.sound && !_maySound) return;
      _clearPending();
      _lastCueAt = _nowMs();
      if (event.cue == RecitationCue.mistake) _lastMistakeAt = _lastCueAt;
      if (_mode == RecitationFeedbackMode.vibration) {
        await _output.vibrate(event.cue);
      } else {
        final played = await _output.play(event.cue);
        _traceFeedback('play=${event.cue.name} success=$played');
      }
    } on Object {
      // A missing asset/device/audio route must never interrupt recitation.
    } finally {
      _flushing = false;
      if (_pending != null && !identical(event, _pending)) unawaited(_flush());
    }
  }

  /// Audition is explicit and only allowed with capture fully stopped.
  Future<void> preview() async {
    _traceFeedback(
      'preview mode=${_mode.name} foreground=$_foreground '
      'capture=${_speech.isListening} listening=${_state().isListening} '
      'draining=${_state().isDraining}',
    );
    if (_disposed ||
        !_foreground ||
        _mode == RecitationFeedbackMode.silent ||
        _speech.isListening ||
        _state().isListening ||
        _state().isDraining) {
      return;
    }
    _cancel();
    final generation = _generation;
    try {
      if (_mode == RecitationFeedbackMode.sound) await _prepare();
      if (_disposed ||
          !_foreground ||
          generation != _generation ||
          _speech.isListening ||
          _state().isListening ||
          _state().isDraining) {
        return;
      }
      if (_mode == RecitationFeedbackMode.vibration) {
        await _output.vibrate(RecitationCue.mistake);
      } else {
        final played = await _output.play(RecitationCue.mistake);
        _traceFeedback('preview success=$played');
      }
    } on Object {
      // An unavailable preview does not change the saved feedback preference.
    }
  }

  void _clearPending() {
    _pending = null;
    _timer?.cancel();
    _timer = null;
  }

  void _cancel() {
    _generation++;
    _clearPending();
    unawaited(_stopOutput());
  }

  Future<void> _stopOutput() async {
    try {
      await _output.stop();
    } on Object {
      // Capture teardown remains independent of optional sound playback.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancel();
    await _eventSubscription.cancel();
    await _stateSubscription.cancel();
    await _quietSubscription?.cancel();
    try {
      await _output.dispose();
    } on Object {
      // The platform channel may already be unavailable during page disposal.
    }
  }
}
