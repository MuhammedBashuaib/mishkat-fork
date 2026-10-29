import 'package:equatable/equatable.dart';

import '../../data/models/murajaah_models.dart';
import '../../data/models/visual_recall_models.dart';

/// State representation for transient In-Mushaf Visual Recall session orchestration.
class QuranVisualRecallState extends Equatable {
  const QuranVisualRecallState({
    this.phase = VisualRecallPhase.idle,
    this.sessionId,
    this.origin,
    this.planId,
    this.queue = const <int>[],
    this.currentIndex = 0,
    this.revealedGlobals = const <int>{},
    this.rangeSelectionStart,
    this.rangeSelectionEnd,
    this.assessmentOutcomes = const <int, ReviewOutcome>{},
    this.isAudioSyncEnabled = false,
    this.isAudioPlaying = false,
    this.isAudioPaused = false,
    this.isTimedMaskActive = false,
    this.remainingMaskDuration = 0,
    this.timerGeneration = 0,
    this.currentAudioAyah,
    this.hasCheckpointAvailable = false,
    this.checkpointToResume,
    this.error,
    this.isLoading = false,
  }) : assert(currentIndex >= 0);

  /// Current discrete lifecycle phase of the Visual Recall state machine.
  final VisualRecallPhase phase;

  /// Unique 128-bit session ID for the active drill.
  final String? sessionId;

  /// Context origin of this drill.
  final VisualRecallSessionOrigin? origin;

  /// Associated memorization plan ID, if any.
  final String? planId;

  /// Canonical ordered sequence of global Ayahs (1..6236) in the active drill.
  final List<int> queue;

  /// Current 0-based pointer within [queue].
  final int currentIndex;

  /// Set of canonical global Ayah indices currently revealed/unmasked.
  final Set<int> revealedGlobals;

  /// Starting Ayah of an interactive range selection (1..6236).
  final int? rangeSelectionStart;

  /// Ending Ayah of an interactive range selection (1..6236).
  final int? rangeSelectionEnd;

  /// Self-assessment outcomes recorded so far during this session.
  final Map<int, ReviewOutcome> assessmentOutcomes;

  /// Whether real-time audio recitation sync is toggled on.
  final bool isAudioSyncEnabled;

  /// Whether audio is actively playing for the current Ayah.
  final bool isAudioPlaying;

  /// Whether audio playback or the timed mask countdown is currently paused.
  final bool isAudioPaused;

  /// Whether the Tardid recitation delay countdown is actively running while Ayah is masked.
  final bool isTimedMaskActive;

  /// Remaining seconds in the Tardid recitation delay countdown before automatic reveal.
  final int remainingMaskDuration;

  /// Monotonic generation token guarding against stale timer callbacks.
  final int timerGeneration;

  /// The global Ayah index currently being recited by audio.
  final int? currentAudioAyah;

  /// Whether a valid (<24h) saved checkpoint exists and can be resumed.
  final bool hasCheckpointAvailable;

  /// Cached checkpoint metadata available for user prompt/resume.
  final VisualRecallSessionCheckpoint? checkpointToResume;

  /// User-facing localized error message on disk failure or validation rejection.
  final String? error;

  /// Whether an asynchronous I/O or repository operation is running.
  final bool isLoading;

  /// The active global Ayah index currently being recalled or evaluated.
  ///
  /// Strictly non-null during [VisualRecallPhase.activeRecall] and [VisualRecallPhase.evaluating].
  int? get currentGlobalAyah =>
      (phase == VisualRecallPhase.activeRecall ||
              phase == VisualRecallPhase.evaluating) &&
          (currentIndex >= 0 && currentIndex < queue.length)
      ? queue[currentIndex]
      : null;

  /// Whether the current active Ayah is currently unmasked.
  bool get isCurrentAyahRevealed =>
      currentGlobalAyah != null && revealedGlobals.contains(currentGlobalAyah);

  /// Set of all Ayah indices in [queue] that must currently have visual masks painted.
  ///
  /// Empty in [VisualRecallPhase.idle] and [VisualRecallPhase.completed].
  Set<int> get activeMaskedGlobals {
    if (phase != VisualRecallPhase.activeRecall &&
        phase != VisualRecallPhase.evaluating) {
      return const <int>{};
    }
    return queue.where((g) => !revealedGlobals.contains(g)).toSet();
  }

  /// Total number of Ayahs in this drill.
  int get totalCount => queue.length;

  /// Number of Ayahs completed and assessed in this drill.
  int get completedCount => assessmentOutcomes.length;

  /// Remaining Ayahs in this drill including the current one.
  int get remainingCount => (totalCount - currentIndex).clamp(0, totalCount);

  /// Fractional progress through the queue (0.0 .. 1.0).
  double get progress =>
      totalCount == 0 ? 0.0 : (currentIndex / totalCount).clamp(0.0, 1.0);

  /// Whether a recall drill is actively in flight.
  bool get hasActiveSession =>
      phase == VisualRecallPhase.activeRecall ||
      phase == VisualRecallPhase.evaluating;

  bool get isIdle => phase == VisualRecallPhase.idle;
  bool get isRangeSelecting => phase == VisualRecallPhase.rangeSelection;
  bool get isActiveRecall => phase == VisualRecallPhase.activeRecall;
  bool get isEvaluating => phase == VisualRecallPhase.evaluating;
  bool get isCompleted => phase == VisualRecallPhase.completed;

  QuranVisualRecallState copyWith({
    VisualRecallPhase? phase,
    String? sessionId,
    VisualRecallSessionOrigin? origin,
    String? planId,
    List<int>? queue,
    int? currentIndex,
    Set<int>? revealedGlobals,
    int? rangeSelectionStart,
    int? rangeSelectionEnd,
    Map<int, ReviewOutcome>? assessmentOutcomes,
    bool? isAudioSyncEnabled,
    bool? isAudioPlaying,
    bool? isAudioPaused,
    bool? isTimedMaskActive,
    int? remainingMaskDuration,
    int? timerGeneration,
    int? currentAudioAyah,
    bool? hasCheckpointAvailable,
    VisualRecallSessionCheckpoint? checkpointToResume,
    String? error,
    bool? isLoading,
    bool clearSessionId = false,
    bool clearPlanId = false,
    bool clearRangeSelection = false,
    bool clearCheckpoint = false,
    bool clearError = false,
    bool clearCurrentAudioAyah = false,
  }) {
    return QuranVisualRecallState(
      phase: phase ?? this.phase,
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      origin: origin ?? this.origin,
      planId: clearPlanId ? null : (planId ?? this.planId),
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      revealedGlobals: revealedGlobals ?? this.revealedGlobals,
      rangeSelectionStart: clearRangeSelection
          ? null
          : (rangeSelectionStart ?? this.rangeSelectionStart),
      rangeSelectionEnd: clearRangeSelection
          ? null
          : (rangeSelectionEnd ?? this.rangeSelectionEnd),
      assessmentOutcomes: assessmentOutcomes ?? this.assessmentOutcomes,
      isAudioSyncEnabled: isAudioSyncEnabled ?? this.isAudioSyncEnabled,
      isAudioPlaying: isAudioPlaying ?? this.isAudioPlaying,
      isAudioPaused: isAudioPaused ?? this.isAudioPaused,
      isTimedMaskActive: isTimedMaskActive ?? this.isTimedMaskActive,
      remainingMaskDuration:
          remainingMaskDuration ?? this.remainingMaskDuration,
      timerGeneration: timerGeneration ?? this.timerGeneration,
      currentAudioAyah: clearCurrentAudioAyah
          ? null
          : (currentAudioAyah ?? this.currentAudioAyah),
      hasCheckpointAvailable: clearCheckpoint
          ? false
          : (hasCheckpointAvailable ?? this.hasCheckpointAvailable),
      checkpointToResume: clearCheckpoint
          ? null
          : (checkpointToResume ?? this.checkpointToResume),
      error: clearError ? null : (error ?? this.error),
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [
    phase,
    sessionId,
    origin,
    planId,
    queue,
    currentIndex,
    revealedGlobals,
    rangeSelectionStart,
    rangeSelectionEnd,
    assessmentOutcomes,
    isAudioSyncEnabled,
    isAudioPlaying,
    isAudioPaused,
    isTimedMaskActive,
    remainingMaskDuration,
    timerGeneration,
    currentAudioAyah,
    hasCheckpointAvailable,
    checkpointToResume,
    error,
    isLoading,
  ];
}
