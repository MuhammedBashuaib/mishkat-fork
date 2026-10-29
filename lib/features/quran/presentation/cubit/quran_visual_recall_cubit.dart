import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/services/audio_service.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../data/models/murajaah_models.dart';
import '../../data/models/visual_recall_models.dart';
import '../../data/repositories/mushaf_layout_repository.dart';
import 'quran_memorization_cubit.dart';
import 'quran_visual_recall_state.dart';

/// Cubit responsible for In-Mushaf Visual Recall session orchestration.
///
/// Strictly manages transient drill lifecycle, queue progression, per-Ayah reveal states,
/// range selection, and 24-hour crash recovery checkpoints.
///
/// Delegates all durable spaced-repetition mastery and review history commits to [QuranMemorizationCubit].
class QuranVisualRecallCubit extends Cubit<QuranVisualRecallState> {
  QuranVisualRecallCubit({
    required this.memorizationCubit,
    required this.storage,
    MushafLayoutRepository? layoutRepository,
    this.audioService,
    this.reciter = 'ar.alafasy',
    this.defaultTardidDelaySeconds = 3,
  }) : layoutRepository = layoutRepository ?? MushafLayoutRepository.instance,
       super(const QuranVisualRecallState()) {
    _initAudioListener();
  }

  final QuranMemorizationCubit memorizationCubit;
  final LocalStorageService storage;
  final MushafLayoutRepository layoutRepository;
  final QuranAudioService? audioService;
  final String reciter;
  final int defaultTardidDelaySeconds;

  StreamSubscription<PlayerState>? _playerSubscription;
  Timer? _tardidTimer;
  int _syncGeneration = 0;

  static const String checkpointKey = 'quran_visual_recall_checkpoint';

  final Map<String, Completer<void>> _inFlightAssessments = {};

  void _initAudioListener() {
    if (audioService != null) {
      _playerSubscription = audioService!.playerState.listen(
        _onPlayerStateChanged,
        onError: (_) {},
      );
    }
  }

  void _onPlayerStateChanged(PlayerState player) {
    if (isClosed) return;
    if (!state.hasActiveSession || !state.isAudioSyncEnabled) return;

    final current = state.currentGlobalAyah;
    final sessionId = state.sessionId;
    if (current == null || sessionId == null) return;

    // Stale guard: ignore player events if not targeted at the current active Ayah
    if (state.currentAudioAyah != current) {
      return;
    }

    final token = _syncGeneration;

    if (player.processingState == ProcessingState.completed) {
      // Recitation of current Ayah finished
      if (state.isTimedMaskActive) return; // already in countdown

      // If current Ayah was already manually revealed, keep revealed
      if (state.revealedGlobals.contains(current)) {
        emit(state.copyWith(isAudioPlaying: false, isAudioPaused: false));
        return;
      }

      // Start Q12 Tardid Recitation Window:
      // Ayah remains masked during the delay window while the learner recites aloud.
      _cancelTimedMaskTimer();
      final delay = defaultTardidDelaySeconds;

      emit(
        state.copyWith(
          isAudioPlaying: false,
          isAudioPaused: false,
          isTimedMaskActive: true,
          remainingMaskDuration: delay,
          timerGeneration: token,
        ),
      );

      _tardidTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (isClosed ||
            _syncGeneration != token ||
            state.sessionId != sessionId ||
            state.currentGlobalAyah != current) {
          timer.cancel();
          return;
        }

        final remaining = state.remainingMaskDuration - 1;
        if (remaining <= 0) {
          timer.cancel();
          _tardidTimer = null;
          // Timer expires: reveal Ayah and enter evaluating phase for self-assessment!
          emit(
            state.copyWith(isTimedMaskActive: false, remainingMaskDuration: 0),
          );
          revealCurrentAyah();
        } else {
          emit(state.copyWith(remainingMaskDuration: remaining));
        }
      });
    } else if (player.playing) {
      if (!state.isAudioPlaying) {
        emit(state.copyWith(isAudioPlaying: true, isAudioPaused: false));
      }
    } else if (state.isAudioPlaying && !player.playing) {
      emit(state.copyWith(isAudioPlaying: false, isAudioPaused: true));
    }
  }

  void _cancelTimedMaskTimer() {
    _tardidTimer?.cancel();
    _tardidTimer = null;
  }

  void _invalidateAudioSync() {
    _syncGeneration++;
    _cancelTimedMaskTimer();
  }

  /// Inspects storage for a valid, non-expired (<24h) checkpoint and reconciles against durable history.
  Future<void> init() async {
    try {
      final raw = storage.readMap(checkpointKey);
      if (raw.isEmpty) return;

      final checkpoint = VisualRecallSessionCheckpoint.fromJson(raw);

      // Checkpoint must match schema version 1 and not be expired
      if (checkpoint.version != 1 || checkpoint.isExpired) {
        await storage.remove(checkpointKey);
        return;
      }

      // Reconcile against durable history in QuranMemorizationCubit
      final history = memorizationCubit.state.history;
      final reconciledOutcomes = Map<int, ReviewOutcome>.from(
        checkpoint.assessmentOutcomes,
      );

      for (final g in checkpoint.queue) {
        if (!reconciledOutcomes.containsKey(g)) {
          final recorded = history.cast<dynamic>().firstWhere(
            (r) =>
                (r.sessionId == checkpoint.sessionId && r.globalAyah == g) ||
                r.id == 'rev_${checkpoint.sessionId}_$g',
            orElse: () => null,
          );
          if (recorded != null) {
            reconciledOutcomes[g] = recorded.outcome as ReviewOutcome;
          }
        }
      }

      // If every Ayah in queue is already committed to history, drill is finished -> purge
      final allCommitted = checkpoint.queue.every(
        (g) => reconciledOutcomes.containsKey(g),
      );
      if (allCommitted) {
        await storage.remove(checkpointKey);
        return;
      }

      // Auto-advance pointer past already assessed Ayahs if it was lagging behind
      var reconciledIndex = checkpoint.currentIndex;
      while (reconciledIndex < checkpoint.queue.length &&
          reconciledOutcomes.containsKey(checkpoint.queue[reconciledIndex])) {
        reconciledIndex++;
      }

      final reconciledCheckpoint = checkpoint.copyWith(
        currentIndex: reconciledIndex,
        assessmentOutcomes: reconciledOutcomes,
      );

      emit(
        state.copyWith(
          hasCheckpointAvailable: true,
          checkpointToResume: reconciledCheckpoint,
        ),
      );
    } catch (_) {
      // Best-effort inspection; do not throw
    }
  }

  /// Restores practice drill from the active checkpoint.
  Future<void> restoreCheckpoint() async {
    final cp = state.checkpointToResume;
    if (cp == null) return;

    final currentGlobal = cp.currentGlobalAyah;
    final isRevealed =
        currentGlobal != null && cp.revealedGlobals.contains(currentGlobal);

    _invalidateAudioSync();
    if (audioService != null) {
      try {
        await audioService!.stop();
      } catch (_) {}
    }

    emit(
      state.copyWith(
        phase: isRevealed
            ? VisualRecallPhase.evaluating
            : VisualRecallPhase.activeRecall,
        sessionId: cp.sessionId,
        origin: cp.origin,
        planId: cp.planId,
        queue: cp.queue,
        currentIndex: cp.currentIndex,
        revealedGlobals: cp.revealedGlobals,
        assessmentOutcomes: cp.assessmentOutcomes,
        isAudioSyncEnabled: cp.isAudioSyncEnabled,
        isAudioPlaying: false,
        isAudioPaused: false,
        isTimedMaskActive: false,
        remainingMaskDuration: 0,
        clearCurrentAudioAyah: true,
        clearCheckpoint: true,
        clearError: true,
      ),
    );
  }

  /// Discards the cached checkpoint from storage and state.
  Future<void> discardCheckpoint() async {
    try {
      await storage.remove(checkpointKey);
    } catch (_) {}
    emit(state.copyWith(clearCheckpoint: true));
  }

  /// Starts an ad-hoc single-Ayah Visual Recall drill.
  Future<void> startSingleAyah(int globalAyah) async {
    if (globalAyah < 1 || globalAyah > 6236) {
      throw ArgumentError(
        'Ayah index must be between 1 and 6236 (got $globalAyah)',
      );
    }

    _invalidateAudioSync();
    if (audioService != null) {
      try {
        await audioService!.stop();
      } catch (_) {}
    }

    final sessionId = generateVisualRecallSessionId(
      origin: 'adhoc',
      startGlobal: globalAyah,
      endGlobal: globalAyah,
    );

    emit(
      state.copyWith(
        phase: VisualRecallPhase.activeRecall,
        sessionId: sessionId,
        origin: VisualRecallSessionOrigin.adhoc,
        clearPlanId: true,
        queue: [globalAyah],
        currentIndex: 0,
        revealedGlobals: <int>{},
        assessmentOutcomes: <int, ReviewOutcome>{},
        isAudioPlaying: false,
        isAudioPaused: false,
        isTimedMaskActive: false,
        remainingMaskDuration: 0,
        clearCurrentAudioAyah: true,
        clearError: true,
      ),
    );

    await _saveCheckpoint();
  }

  /// Starts a multi-Ayah range Visual Recall drill over contiguous indices [startGlobal..endGlobal].
  Future<void> startRange(int startGlobal, int endGlobal) async {
    if (startGlobal < 1 || startGlobal > 6236) {
      throw ArgumentError(
        'startGlobal must be between 1 and 6236 (got $startGlobal)',
      );
    }
    if (endGlobal < 1 || endGlobal > 6236) {
      throw ArgumentError(
        'endGlobal must be between 1 and 6236 (got $endGlobal)',
      );
    }
    if (startGlobal > endGlobal) {
      throw ArgumentError(
        'startGlobal ($startGlobal) cannot exceed endGlobal ($endGlobal)',
      );
    }

    _invalidateAudioSync();
    if (audioService != null) {
      try {
        await audioService!.stop();
      } catch (_) {}
    }

    final sessionId = generateVisualRecallSessionId(
      origin: 'range',
      startGlobal: startGlobal,
      endGlobal: endGlobal,
    );

    final queue = List.generate(
      endGlobal - startGlobal + 1,
      (i) => startGlobal + i,
    );

    emit(
      state.copyWith(
        phase: VisualRecallPhase.activeRecall,
        sessionId: sessionId,
        origin: VisualRecallSessionOrigin.range,
        clearPlanId: true,
        queue: queue,
        currentIndex: 0,
        revealedGlobals: <int>{},
        assessmentOutcomes: <int, ReviewOutcome>{},
        isAudioPlaying: false,
        isAudioPaused: false,
        isTimedMaskActive: false,
        remainingMaskDuration: 0,
        clearCurrentAudioAyah: true,
        clearError: true,
      ),
    );

    await _saveCheckpoint();
  }

  /// Starts a Visual Recall drill from a Daily Journey or Plan queue.
  Future<void> startJourney(List<int> rawQueue, {String? planId}) async {
    if (rawQueue.isEmpty) {
      throw ArgumentError('Journey queue cannot be empty');
    }
    for (final g in rawQueue) {
      if (g < 1 || g > 6236) {
        throw ArgumentError('Invalid Ayah index in journey queue: $g');
      }
    }

    _invalidateAudioSync();
    if (audioService != null) {
      try {
        await audioService!.stop();
      } catch (_) {}
    }

    // Deduplicate while strictly preserving order
    final seen = <int>{};
    final queue = <int>[];
    for (final g in rawQueue) {
      if (seen.add(g)) queue.add(g);
    }

    final sessionId = generateVisualRecallSessionId(
      origin: planId != null ? 'plan' : 'journey',
      startGlobal: queue.first,
      endGlobal: queue.last,
    );

    emit(
      state.copyWith(
        phase: VisualRecallPhase.activeRecall,
        sessionId: sessionId,
        origin: planId != null
            ? VisualRecallSessionOrigin.plan
            : VisualRecallSessionOrigin.dailyJourney,
        planId: planId,
        queue: queue,
        currentIndex: 0,
        revealedGlobals: <int>{},
        assessmentOutcomes: <int, ReviewOutcome>{},
        isAudioPlaying: false,
        isAudioPaused: false,
        isTimedMaskActive: false,
        remainingMaskDuration: 0,
        clearCurrentAudioAyah: true,
        clearError: true,
      ),
    );

    await _saveCheckpoint();
  }

  /// Enters interactive range selection mode starting at [startGlobal].
  void enterRangeSelection(int startGlobal) {
    final clamped = startGlobal.clamp(1, 6236);
    emit(
      state.copyWith(
        phase: VisualRecallPhase.rangeSelection,
        rangeSelectionStart: clamped,
        rangeSelectionEnd: clamped,
        clearError: true,
      ),
    );
  }

  /// Updates the selection end point in range selection mode.
  void updateRangeEnd(int endGlobal) {
    if (state.phase != VisualRecallPhase.rangeSelection) return;
    final clamped = endGlobal.clamp(1, 6236);
    emit(state.copyWith(rangeSelectionEnd: clamped));
  }

  /// Confirms the active range selection and launches a range drill.
  Future<void> confirmRangeSelection() async {
    if (state.phase != VisualRecallPhase.rangeSelection ||
        state.rangeSelectionStart == null ||
        state.rangeSelectionEnd == null) {
      return;
    }

    final start = min(state.rangeSelectionStart!, state.rangeSelectionEnd!);
    final end = max(state.rangeSelectionStart!, state.rangeSelectionEnd!);

    emit(state.copyWith(clearRangeSelection: true));
    await startRange(start, end);
  }

  /// Cancels range selection and returns to [VisualRecallPhase.idle].
  void cancelRangeSelection() {
    emit(
      state.copyWith(phase: VisualRecallPhase.idle, clearRangeSelection: true),
    );
  }

  /// Unmasks/reveals the current active Ayah and transitions to [VisualRecallPhase.evaluating].
  void revealCurrentAyah() {
    final current = state.currentGlobalAyah;
    if (current == null) return;

    if (state.isTimedMaskActive) {
      _cancelTimedMaskTimer();
    }

    final updated = Set<int>.from(state.revealedGlobals)..add(current);
    emit(
      state.copyWith(
        phase: VisualRecallPhase.evaluating,
        revealedGlobals: updated,
        isTimedMaskActive: false,
        remainingMaskDuration: 0,
      ),
    );
  }

  /// Unmasks/reveals all Ayahs in the drill queue.
  void revealAllAyahs() {
    if (!state.hasActiveSession) return;

    if (state.isTimedMaskActive) {
      _cancelTimedMaskTimer();
    }

    final updated = Set<int>.from(state.revealedGlobals)..addAll(state.queue);
    emit(
      state.copyWith(
        phase: VisualRecallPhase.evaluating,
        revealedGlobals: updated,
        isTimedMaskActive: false,
        remainingMaskDuration: 0,
      ),
    );
  }

  /// Masks/hides the current active Ayah again and transitions back to [VisualRecallPhase.activeRecall].
  void hideCurrentAyah() {
    final current = state.currentGlobalAyah;
    if (current == null) return;

    if (state.isTimedMaskActive) {
      _cancelTimedMaskTimer();
    }

    final updated = Set<int>.from(state.revealedGlobals)..remove(current);
    emit(
      state.copyWith(
        phase: VisualRecallPhase.activeRecall,
        revealedGlobals: updated,
        isTimedMaskActive: false,
        remainingMaskDuration: 0,
      ),
    );
  }

  /// Toggles reveal state of an individual Ayah in the session queue.
  void toggleAyahReveal(int globalAyah) {
    if (!state.hasActiveSession || !state.queue.contains(globalAyah)) return;

    if (globalAyah == state.currentGlobalAyah && state.isTimedMaskActive) {
      _cancelTimedMaskTimer();
    }

    final updated = Set<int>.from(state.revealedGlobals);
    if (updated.contains(globalAyah)) {
      updated.remove(globalAyah);
    } else {
      updated.add(globalAyah);
    }

    // If this affects the active Ayah, update phase accordingly
    var nextPhase = state.phase;
    if (globalAyah == state.currentGlobalAyah) {
      nextPhase = updated.contains(globalAyah)
          ? VisualRecallPhase.evaluating
          : VisualRecallPhase.activeRecall;
    }

    emit(
      state.copyWith(
        phase: nextPhase,
        revealedGlobals: updated,
        isTimedMaskActive: globalAyah == state.currentGlobalAyah
            ? false
            : state.isTimedMaskActive,
        remainingMaskDuration: globalAyah == state.currentGlobalAyah
            ? 0
            : state.remainingMaskDuration,
      ),
    );
  }

  /// Records self-assessment outcome for the current Ayah and advances the drill.
  ///
  /// Strictly delegates persistent mastery and history recording to [QuranMemorizationCubit.recordReviewOutcome].
  ///
  /// On persistence failure, advances are BLOCKED, retaining the uncommitted state and displaying an actionable error.
  Future<void> recordOutcome(ReviewOutcome outcome) async {
    // 1. Validation checks (Reject invalid state)
    if (!state.hasActiveSession || state.isCompleted) return;
    if (state.queue.isEmpty) return;
    if (state.currentIndex < 0 || state.currentIndex >= state.queue.length) {
      return;
    }

    final current = state.currentGlobalAyah;
    final sessionId = state.sessionId;
    if (current == null || sessionId == null) return;
    if (!state.queue.contains(current)) return;

    final operationId = 'rev_${sessionId}_$current';

    // 2. In-flight operation guard: await existing operation if already in flight
    final inFlight = _inFlightAssessments[operationId];
    if (inFlight != null) {
      await inFlight.future;
      return;
    }

    final completer = Completer<void>();
    completer.future.ignore();
    _inFlightAssessments[operationId] = completer;

    emit(state.copyWith(isLoading: true, clearError: true));

    try {
      await memorizationCubit.recordReviewOutcome(
        globalAyah: current,
        outcome: outcome,
        sessionId: sessionId,
        planId: state.planId,
        operationId: operationId,
      );

      final updatedOutcomes = Map<int, ReviewOutcome>.from(
        state.assessmentOutcomes,
      )..[current] = outcome;

      final nextIndex = state.currentIndex + 1;

      _invalidateAudioSync();
      if (audioService != null) {
        try {
          await audioService!.stop();
        } catch (_) {}
      }

      if (nextIndex >= state.queue.length) {
        // Drill complete! Purge checkpoint and transition to completed summary
        String? cleanupError;
        try {
          await storage.remove(checkpointKey);
        } catch (e) {
          cleanupError = 'تعذر حذف نقطة الاستعادة المؤقتة: $e';
        }

        emit(
          state.copyWith(
            phase: VisualRecallPhase.completed,
            currentIndex: nextIndex,
            assessmentOutcomes: updatedOutcomes,
            isAudioPlaying: false,
            isAudioPaused: false,
            isTimedMaskActive: false,
            remainingMaskDuration: 0,
            clearCurrentAudioAyah: true,
            isLoading: false,
            error: cleanupError,
            clearError: cleanupError == null,
          ),
        );
      } else {
        final nextGlobal = state.queue[nextIndex];
        final isNextRevealed = state.revealedGlobals.contains(nextGlobal);

        emit(
          state.copyWith(
            phase: isNextRevealed
                ? VisualRecallPhase.evaluating
                : VisualRecallPhase.activeRecall,
            currentIndex: nextIndex,
            assessmentOutcomes: updatedOutcomes,
            isAudioPlaying: false,
            isAudioPaused: false,
            isTimedMaskActive: false,
            remainingMaskDuration: 0,
            clearCurrentAudioAyah: true,
            isLoading: false,
            clearError: true,
          ),
        );

        await _saveCheckpoint();
      }
      completer.complete();
    } catch (e, st) {
      // BLOCK advance: retain current state and prompt user to retry
      emit(
        state.copyWith(
          isLoading: false,
          error: 'تعذر حفظ نتيجة التسميع على القرص: $e',
        ),
      );
      completer.completeError(e, st);
      rethrow;
    } finally {
      _inFlightAssessments.remove(operationId);
    }
  }

  /// Records confirmed recall outcome ("أعرفها ومحفوظة").
  Future<void> recordKnown() => recordOutcome(ReviewOutcome.good);

  /// Records difficulty outcome ("تحتاج مراجعة").
  Future<void> recordNeedsRevision() => recordOutcome(ReviewOutcome.difficult);

  /// Records forgotten outcome ("لم أتذكر").
  Future<void> recordFailed() => recordOutcome(ReviewOutcome.failed);

  /// Retries assessment for the current uncommitted Ayah after a failure.
  Future<void> retryLastOutcome([ReviewOutcome? fallbackOutcome]) =>
      recordOutcome(fallbackOutcome ?? ReviewOutcome.good);

  /// Jumps the current pointer to a specific Ayah within the queue.
  void jumpToAyah(int globalAyah) {
    if (!state.hasActiveSession || !state.queue.contains(globalAyah)) return;

    _invalidateAudioSync();
    if (audioService != null) {
      try {
        unawaited(audioService!.stop());
      } catch (_) {}
    }

    final targetIndex = state.queue.indexOf(globalAyah);
    final isRevealed = state.revealedGlobals.contains(globalAyah);

    emit(
      state.copyWith(
        phase: isRevealed
            ? VisualRecallPhase.evaluating
            : VisualRecallPhase.activeRecall,
        currentIndex: targetIndex,
        isAudioPlaying: false,
        isAudioPaused: false,
        isTimedMaskActive: false,
        remainingMaskDuration: 0,
        clearCurrentAudioAyah: true,
      ),
    );
  }

  /// Plays audio for the current active Ayah using the existing [QuranAudioService].
  Future<void> playCurrentAyahAudio() async {
    if (!state.hasActiveSession || state.currentGlobalAyah == null) return;
    if (audioService == null) return;

    final current = state.currentGlobalAyah!;
    _invalidateAudioSync();
    final token = _syncGeneration;

    emit(
      state.copyWith(
        isAudioSyncEnabled: true,
        isAudioPlaying: true,
        isAudioPaused: false,
        isTimedMaskActive: false,
        remainingMaskDuration: 0,
        timerGeneration: token,
        currentAudioAyah: current,
        clearError: true,
      ),
    );

    try {
      await audioService!.playAyah(reciter: reciter, globalAyah: current);
    } catch (e) {
      if (token != _syncGeneration) return;
      emit(
        state.copyWith(
          isAudioPlaying: false,
          isAudioPaused: false,
          error: 'تعذر تشغيل الصوت: $e',
        ),
      );
    }
  }

  /// Toggles play / pause for the current active Ayah.
  Future<void> toggleAudioPlayback() async {
    if (state.isTimedMaskActive) {
      if (state.isAudioPaused) {
        await resumeAudio();
      } else {
        await pauseAudio();
      }
      return;
    }

    if (state.isAudioPlaying) {
      await pauseAudio();
    } else if (state.isAudioPaused) {
      await resumeAudio();
    } else {
      await playCurrentAyahAudio();
    }
  }

  /// Pauses audio playback or freezes the Tardid recitation delay countdown.
  Future<void> pauseAudio() async {
    if (state.isTimedMaskActive) {
      _cancelTimedMaskTimer();
      emit(state.copyWith(isAudioPaused: true));
      return;
    }
    if (audioService != null && state.isAudioPlaying) {
      await audioService!.pause();
      emit(state.copyWith(isAudioPlaying: false, isAudioPaused: true));
    }
  }

  /// Resumes audio playback or continues the frozen Tardid delay countdown.
  Future<void> resumeAudio() async {
    if (state.isTimedMaskActive && state.isAudioPaused) {
      emit(state.copyWith(isAudioPaused: false));
      final token = _syncGeneration;
      final current = state.currentGlobalAyah;
      final sessionId = state.sessionId;

      _cancelTimedMaskTimer();
      _tardidTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (isClosed ||
            _syncGeneration != token ||
            state.sessionId != sessionId ||
            state.currentGlobalAyah != current) {
          timer.cancel();
          return;
        }

        final remaining = state.remainingMaskDuration - 1;
        if (remaining <= 0) {
          timer.cancel();
          _tardidTimer = null;
          emit(
            state.copyWith(isTimedMaskActive: false, remainingMaskDuration: 0),
          );
          revealCurrentAyah();
        } else {
          emit(state.copyWith(remainingMaskDuration: remaining));
        }
      });
      return;
    }

    if (audioService != null && state.isAudioPaused) {
      await audioService!.resume();
      emit(state.copyWith(isAudioPlaying: true, isAudioPaused: false));
    }
  }

  /// Skips the remaining Tardid recitation delay immediately and reveals the Ayah.
  void skipTimedMaskDelay() {
    if (state.isTimedMaskActive) {
      _cancelTimedMaskTimer();
      emit(state.copyWith(isTimedMaskActive: false, remainingMaskDuration: 0));
      revealCurrentAyah();
    }
  }

  /// Seeks the audio player to [position].
  Future<void> seekAudio(Duration position) async {
    if (audioService != null) {
      await audioService!.seek(position);
    }
  }

  /// Stops audio playback and cancels any active timed mask countdown.
  Future<void> stopAudio() async {
    _invalidateAudioSync();
    if (audioService != null) {
      try {
        await audioService!.stop();
      } catch (_) {}
    }
    emit(
      state.copyWith(
        isAudioPlaying: false,
        isAudioPaused: false,
        isTimedMaskActive: false,
        remainingMaskDuration: 0,
        clearCurrentAudioAyah: true,
      ),
    );
  }

  /// Toggles real-time audio synchronization.
  Future<void> toggleAudioSync() async {
    final next = !state.isAudioSyncEnabled;
    emit(state.copyWith(isAudioSyncEnabled: next));
    if (!next) {
      await stopAudio();
    }
  }

  /// Explicitly terminates active drill and purges checkpoint from storage.
  Future<void> endSession() async {
    _invalidateAudioSync();
    if (audioService != null) {
      try {
        await audioService!.stop();
      } catch (_) {}
    }
    try {
      await storage.remove(checkpointKey);
    } catch (_) {}
    emit(const QuranVisualRecallState());
  }

  /// Dismisses drill completion summary and resets to [VisualRecallPhase.idle].
  Future<void> dismissSummary() async {
    _invalidateAudioSync();
    if (audioService != null) {
      try {
        await audioService!.stop();
      } catch (_) {}
    }
    emit(const QuranVisualRecallState());
  }

  /// Writes current drill state to checkpoint in local storage.
  Future<void> _saveCheckpoint() async {
    final sessionId = state.sessionId;
    if (sessionId == null || state.queue.isEmpty || state.isCompleted) return;

    try {
      final checkpoint = VisualRecallSessionCheckpoint(
        sessionId: sessionId,
        origin: state.origin ?? VisualRecallSessionOrigin.adhoc,
        planId: state.planId,
        queue: state.queue,
        currentIndex: state.currentIndex,
        revealedGlobals: state.revealedGlobals,
        assessmentOutcomes: state.assessmentOutcomes,
        isAudioSyncEnabled: state.isAudioSyncEnabled,
        savedAt: DateTime.now(),
      );
      await storage.writeMap(checkpointKey, checkpoint.toJson());
    } catch (_) {
      // Non-fatal: practice continues in-memory
    }
  }

  @override
  Future<void> close() async {
    _invalidateAudioSync();
    final closeFuture = super.close();
    await _playerSubscription?.cancel();
    return closeFuture;
  }
}
