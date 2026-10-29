import 'dart:async';

import '../../features/quran/domain/models/audio_repeat_config.dart';

/// Pure, isolated controller managing Quran audio repetition, range loops,
/// Tardid delay countdowns, and progression sequences.
class AudioRepeatController {
  AudioRepeatController({this.onPlayAyahRequested, this.onSequenceCompleted});

  final Future<void> Function(int globalAyah)? onPlayAyahRequested;
  final void Function()? onSequenceCompleted;

  AudioRepeatState _state = const AudioRepeatState();
  final _stateController = StreamController<AudioRepeatState>.broadcast();

  Timer? _delayTimer;
  bool _continuous = false;
  bool _isDisposed = false;

  AudioRepeatState get state => _state;
  Stream<AudioRepeatState> get stateStream => _stateController.stream;

  bool get isContinuous => _continuous;
  void setContinuous(bool value) => _continuous = value;

  void _emit(AudioRepeatState newState) {
    if (_isDisposed) return;
    _state = newState;
    _stateController.add(_state);
  }

  /// Initiates repeat playback with [config].
  ///
  /// If [customQueue] is provided (e.g. from DailyHifzJourney), it is used
  /// instead of the contiguous range.
  Future<void> start({
    required AudioRepeatConfig config,
    int? initialGlobalAyah,
    List<int>? customQueue,
    bool continuous = false,
  }) async {
    _cancelDelayTimer();
    _continuous = continuous;

    final queue = (customQueue != null && customQueue.isNotEmpty)
        ? customQueue
        : config.rangeQueue;

    final initialAyah =
        initialGlobalAyah ??
        (queue.isNotEmpty ? queue.first : config.startGlobalAyah);

    final queueIndex = queue.indexOf(initialAyah);
    final safeIndex = queueIndex != -1 ? queueIndex : 0;
    final activeAyah = queue.isNotEmpty ? queue[safeIndex] : initialAyah;

    _emit(
      AudioRepeatState(
        status: AudioRepeatStatus.playing,
        config: config,
        currentAyah: activeAyah,
        currentAyahRepeat: 1,
        currentRangeCycle: 1,
        remainingDelaySeconds: 0,
        queueIndex: safeIndex,
        queue: queue,
      ),
    );

    final callback = onPlayAyahRequested;
    if (callback != null) {
      await callback(activeAyah);
    }
  }

  /// Called when the player finishes reciting the current Ayah.
  void onAyahPlaybackFinished() {
    if (_state.status == AudioRepeatStatus.idle ||
        _state.status == AudioRepeatStatus.completed) {
      return;
    }

    final hasNext = _determineNextStep();
    if (!hasNext.hasMore) {
      _complete();
      return;
    }

    if (_state.config.hasDelay) {
      _startDelay(hasNext);
    } else {
      _advanceTo(hasNext);
    }
  }

  void _startDelay(_NextStep nextStep) {
    _cancelDelayTimer();
    final delay = _state.config.delaySeconds;

    _emit(
      _state.copyWith(
        status: AudioRepeatStatus.delaying,
        remainingDelaySeconds: delay,
      ),
    );

    _delayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = _state.remainingDelaySeconds - 1;
      if (remaining <= 0) {
        timer.cancel();
        _delayTimer = null;
        _advanceTo(nextStep);
      } else {
        _emit(_state.copyWith(remainingDelaySeconds: remaining));
      }
    });
  }

  void _advanceTo(_NextStep nextStep) {
    _cancelDelayTimer();
    _emit(
      _state.copyWith(
        status: AudioRepeatStatus.playing,
        currentAyah: nextStep.nextAyah,
        currentAyahRepeat: nextStep.nextAyahRepeat,
        currentRangeCycle: nextStep.nextRangeCycle,
        queueIndex: nextStep.nextQueueIndex,
        remainingDelaySeconds: 0,
      ),
    );

    final callback = onPlayAyahRequested;
    if (callback != null) {
      unawaited(callback(nextStep.nextAyah));
    }
  }

  _NextStep _determineNextStep() {
    final mode = _state.config.mode;
    final config = _state.config;

    switch (mode) {
      case AudioRepeatMode.none:
        // Regular playback: 1 iteration per Ayah.
        if (_continuous && _state.currentAyah < 6236) {
          final next = _state.currentAyah + 1;
          return _NextStep(
            hasMore: true,
            nextAyah: next,
            nextAyahRepeat: 1,
            nextRangeCycle: 1,
            nextQueueIndex: _state.queueIndex + 1,
          );
        }
        return const _NextStep(hasMore: false);

      case AudioRepeatMode.singleAyah:
        final targetRepeats = config.ayahRepeatCount;
        final isInfinite = config.isInfiniteAyah;

        // Still repetitions remaining for this Ayah
        if (isInfinite || _state.currentAyahRepeat < targetRepeats) {
          return _NextStep(
            hasMore: true,
            nextAyah: _state.currentAyah,
            nextAyahRepeat: _state.currentAyahRepeat + 1,
            nextRangeCycle: 1,
            nextQueueIndex: _state.queueIndex,
          );
        }

        // Ayah repeats finished; check continuous mode to advance to next Ayah
        if (_continuous && _state.currentAyah < 6236) {
          final next = _state.currentAyah + 1;
          return _NextStep(
            hasMore: true,
            nextAyah: next,
            nextAyahRepeat: 1,
            nextRangeCycle: 1,
            nextQueueIndex: _state.queueIndex + 1,
          );
        }
        return const _NextStep(hasMore: false);

      case AudioRepeatMode.rangeLoop:
        // Each Ayah plays 1 time in the sequence. The whole range loops M times.
        final queue = _state.queue;
        final hasNextInQueue = _state.queueIndex < queue.length - 1;

        if (hasNextInQueue) {
          final nextIndex = _state.queueIndex + 1;
          return _NextStep(
            hasMore: true,
            nextAyah: queue[nextIndex],
            nextAyahRepeat: 1,
            nextRangeCycle: _state.currentRangeCycle,
            nextQueueIndex: nextIndex,
          );
        }

        // End of range reached: check if another range cycle is due
        final targetCycles = config.rangeRepeatCount;
        final isInfiniteRange = config.isInfiniteRange;

        if (isInfiniteRange || _state.currentRangeCycle < targetCycles) {
          return _NextStep(
            hasMore: true,
            nextAyah: queue.isNotEmpty ? queue.first : config.startGlobalAyah,
            nextAyahRepeat: 1,
            nextRangeCycle: _state.currentRangeCycle + 1,
            nextQueueIndex: 0,
          );
        }
        return const _NextStep(hasMore: false);

      case AudioRepeatMode.perAyahRange:
        // Each Ayah repeats N times before advancing to the next.
        // Range loops M times.
        final targetRepeats = config.ayahRepeatCount;
        final isInfiniteAyah = config.isInfiniteAyah;

        if (isInfiniteAyah || _state.currentAyahRepeat < targetRepeats) {
          return _NextStep(
            hasMore: true,
            nextAyah: _state.currentAyah,
            nextAyahRepeat: _state.currentAyahRepeat + 1,
            nextRangeCycle: _state.currentRangeCycle,
            nextQueueIndex: _state.queueIndex,
          );
        }

        // This Ayah's repetitions completed. Move to next Ayah in queue.
        final queue = _state.queue;
        final hasNextInQueue = _state.queueIndex < queue.length - 1;

        if (hasNextInQueue) {
          final nextIndex = _state.queueIndex + 1;
          return _NextStep(
            hasMore: true,
            nextAyah: queue[nextIndex],
            nextAyahRepeat: 1,
            nextRangeCycle: _state.currentRangeCycle,
            nextQueueIndex: nextIndex,
          );
        }

        // End of range reached: check if another range cycle is due
        final targetCycles = config.rangeRepeatCount;
        final isInfiniteRange = config.isInfiniteRange;

        if (isInfiniteRange || _state.currentRangeCycle < targetCycles) {
          return _NextStep(
            hasMore: true,
            nextAyah: queue.isNotEmpty ? queue.first : config.startGlobalAyah,
            nextAyahRepeat: 1,
            nextRangeCycle: _state.currentRangeCycle + 1,
            nextQueueIndex: 0,
          );
        }
        return const _NextStep(hasMore: false);
    }
  }

  /// Pauses playback or freezes the delay countdown.
  void pause() {
    if (_state.status == AudioRepeatStatus.delaying) {
      _delayTimer?.cancel();
      _delayTimer = null;
      _emit(_state.copyWith(status: AudioRepeatStatus.paused));
    } else if (_state.status == AudioRepeatStatus.playing) {
      _emit(_state.copyWith(status: AudioRepeatStatus.paused));
    }
  }

  /// Resumes playback or continues from frozen delay countdown.
  void resume() {
    if (_state.status != AudioRepeatStatus.paused) return;

    if (_state.remainingDelaySeconds > 0) {
      // Resume remaining delay
      _emit(_state.copyWith(status: AudioRepeatStatus.delaying));
      _delayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final remaining = _state.remainingDelaySeconds - 1;
        if (remaining <= 0) {
          timer.cancel();
          _delayTimer = null;
          final next = _determineNextStep();
          if (next.hasMore) {
            _advanceTo(next);
          } else {
            _complete();
          }
        } else {
          _emit(_state.copyWith(remainingDelaySeconds: remaining));
        }
      });
    } else {
      _emit(_state.copyWith(status: AudioRepeatStatus.playing));
    }
  }

  /// Skips the delay period immediately and starts the next recitation.
  void skipDelay() {
    if (_state.status == AudioRepeatStatus.delaying ||
        (_state.status == AudioRepeatStatus.paused &&
            _state.remainingDelaySeconds > 0)) {
      _cancelDelayTimer();
      final next = _determineNextStep();
      if (next.hasMore) {
        _advanceTo(next);
      } else {
        _complete();
      }
    }
  }

  /// Manually advance to the next Ayah.
  void next() {
    _cancelDelayTimer();
    final queue = _state.queue;
    if (_state.queueIndex < queue.length - 1) {
      final nextIndex = _state.queueIndex + 1;
      _advanceTo(
        _NextStep(
          hasMore: true,
          nextAyah: queue[nextIndex],
          nextAyahRepeat: 1,
          nextRangeCycle: _state.currentRangeCycle,
          nextQueueIndex: nextIndex,
        ),
      );
    } else if (_continuous && _state.currentAyah < 6236) {
      final next = _state.currentAyah + 1;
      _advanceTo(
        _NextStep(
          hasMore: true,
          nextAyah: next,
          nextAyahRepeat: 1,
          nextRangeCycle: _state.currentRangeCycle,
          nextQueueIndex: _state.queueIndex + 1,
        ),
      );
    } else {
      _complete();
    }
  }

  /// Manually return to the previous Ayah.
  void previous() {
    _cancelDelayTimer();
    final queue = _state.queue;
    if (_state.queueIndex > 0) {
      final prevIndex = _state.queueIndex - 1;
      _advanceTo(
        _NextStep(
          hasMore: true,
          nextAyah: queue[prevIndex],
          nextAyahRepeat: 1,
          nextRangeCycle: _state.currentRangeCycle,
          nextQueueIndex: prevIndex,
        ),
      );
    } else if (_state.currentAyah > 1) {
      final prev = _state.currentAyah - 1;
      _advanceTo(
        _NextStep(
          hasMore: true,
          nextAyah: prev,
          nextAyahRepeat: 1,
          nextRangeCycle: _state.currentRangeCycle,
          nextQueueIndex: 0,
        ),
      );
    }
  }

  /// Dynamically updates configuration without interrupting current playback if applicable.
  void updateConfig(AudioRepeatConfig newConfig) {
    _emit(_state.copyWith(config: newConfig));
  }

  /// Stops all repetition and resets to idle.
  void stop() {
    _cancelDelayTimer();
    _emit(
      _state.copyWith(
        status: AudioRepeatStatus.idle,
        remainingDelaySeconds: 0,
        currentAyahRepeat: 1,
        currentRangeCycle: 1,
      ),
    );
  }

  void _complete() {
    _cancelDelayTimer();
    _emit(
      _state.copyWith(
        status: AudioRepeatStatus.completed,
        remainingDelaySeconds: 0,
      ),
    );
    onSequenceCompleted?.call();
  }

  void _cancelDelayTimer() {
    _delayTimer?.cancel();
    _delayTimer = null;
  }

  void dispose() {
    _isDisposed = true;
    _cancelDelayTimer();
    _stateController.close();
  }
}

class _NextStep {
  const _NextStep({
    required this.hasMore,
    this.nextAyah = 1,
    this.nextAyahRepeat = 1,
    this.nextRangeCycle = 1,
    this.nextQueueIndex = 0,
  });

  final bool hasMore;
  final int nextAyah;
  final int nextAyahRepeat;
  final int nextRangeCycle;
  final int nextQueueIndex;
}
