import 'package:equatable/equatable.dart';

import '../../data/models/oral_recitation_models.dart';

class QuranOralRecitationState extends Equatable {
  const QuranOralRecitationState({
    this.lifecycle = OralRecitationLifecycle.idle,
    this.sessionId,
    this.surahNumber = 1,
    this.surahName = 'الفاتحة',
    this.startGlobalAyah = 1,
    this.endGlobalAyah = 7,
    this.planId,
    this.targetWords = const [],
    this.alignedWords = const [],
    this.discrepancies = const [],
    this.currentGlobalAyah = 1,
    this.currentWordIndex = 0,
    this.committedTargetIndex = 0,
    this.liveTranscript = '',
    this.progressPercentage = 0.0,
    this.matchedWordsCount = 0,
    this.omissionsCount = 0,
    this.substitutionsCount = 0,
    this.uncertainCount = 0,
    this.durationSeconds = 0,
    this.revealedGlobals = const {},
    this.completedGlobalAyahs = const {},
    this.previewCompletedGlobalAyahs = const {},
    this.visibleWordIndices = const {},
    this.mistakeWordIndices = const {},
    this.unresolvedMistakeWordIndices = const {},
    this.summary,
    this.errorMessage,
    this.isCommittingToMemorization = false,
    this.isMemorizationCommitted = false,
    this.mode = OralRecitationMode.hidden,
    this.isOfflineEngine = false,
    this.audioLevel = 0,
    this.isProcessingSpeech = false,
    this.isDraining = false,
    this.hintCount = 0,
    this.hintedGlobalAyahs = const {},
    this.hintedWordIndices = const {},
    this.assistedWordIndices = const {},
    this.correctionWordIndex,
    this.isCorrectionProvisional = false,
  });

  final OralRecitationLifecycle lifecycle;
  final String? sessionId;
  final int surahNumber;
  final String surahName;
  final int startGlobalAyah;
  final int endGlobalAyah;
  final String? planId;

  final List<AuthoritativeWord> targetWords;
  final List<RecitationWordAlignment> alignedWords;
  final List<RecitationDiscrepancy> discrepancies;

  final int currentGlobalAyah;
  final int currentWordIndex;
  final int committedTargetIndex;
  final String liveTranscript;
  final double progressPercentage;
  final int matchedWordsCount;
  final int omissionsCount;
  final int substitutionsCount;
  final int uncertainCount;
  final int durationSeconds;

  final Set<int> revealedGlobals;
  final Set<int> completedGlobalAyahs;

  /// Stable live display only; never used for saved progress or scoring.
  final Set<int> previewCompletedGlobalAyahs;

  /// Authoritative words supported by final speech or a stable live hypothesis.
  /// Visibility is independent of the listening cursor and saved progress.
  final Set<int> visibleWordIndices;

  /// Confirmed mistakes stay red for review after the reader corrects them.
  final Set<int> mistakeWordIndices;

  /// A dotted underline distinguishes mistakes still needing correction.
  final Set<int> unresolvedMistakeWordIndices;
  final OralRecitationSessionSummary? summary;
  final String? errorMessage;
  final bool isCommittingToMemorization;
  final bool isMemorizationCommitted;
  final OralRecitationMode mode;
  final bool isOfflineEngine;
  final double audioLevel;
  final bool isProcessingSpeech;
  final bool isDraining;
  final int hintCount;
  final Set<int> hintedGlobalAyahs;
  final Set<int> hintedWordIndices;
  final Set<int> assistedWordIndices;
  final int? correctionWordIndex;

  /// An unfinished ASR hypothesis can locate a word without asking the reader
  /// to repeat it. Only final uncertainty or a confirmed mistake prompts them.
  final bool isCorrectionProvisional;

  int get attemptedWords =>
      alignedWords.where((w) => !w.status.isUpcoming).length;
  double get coveragePercentage =>
      targetWords.isEmpty ? 0 : attemptedWords / targetWords.length * 100;

  bool get isListening => lifecycle.isListening;
  bool get isPaused => lifecycle.isPaused;
  bool get isCompleted => lifecycle.isCompleted;
  // Keep the chosen assistance level for the whole attempt, including pauses.
  bool get canChangeMode =>
      !isListening &&
      !isPaused &&
      !isCompleted &&
      !isDraining &&
      attemptedWords == 0 &&
      committedTargetIndex == 0;
  bool get hasActiveSession =>
      sessionId != null && !lifecycle.isIdle && !lifecycle.isCompleted;

  QuranOralRecitationState copyWith({
    OralRecitationLifecycle? lifecycle,
    String? sessionId,
    int? surahNumber,
    String? surahName,
    int? startGlobalAyah,
    int? endGlobalAyah,
    String? planId,
    List<AuthoritativeWord>? targetWords,
    List<RecitationWordAlignment>? alignedWords,
    List<RecitationDiscrepancy>? discrepancies,
    int? currentGlobalAyah,
    int? currentWordIndex,
    int? committedTargetIndex,
    String? liveTranscript,
    double? progressPercentage,
    int? matchedWordsCount,
    int? omissionsCount,
    int? substitutionsCount,
    int? uncertainCount,
    int? durationSeconds,
    Set<int>? revealedGlobals,
    Set<int>? completedGlobalAyahs,
    Set<int>? previewCompletedGlobalAyahs,
    Set<int>? visibleWordIndices,
    Set<int>? mistakeWordIndices,
    Set<int>? unresolvedMistakeWordIndices,
    OralRecitationSessionSummary? summary,
    String? errorMessage,
    bool clearError = false,
    bool? isCommittingToMemorization,
    bool? isMemorizationCommitted,
    OralRecitationMode? mode,
    bool? isOfflineEngine,
    double? audioLevel,
    bool? isProcessingSpeech,
    bool? isDraining,
    int? hintCount,
    Set<int>? hintedGlobalAyahs,
    Set<int>? hintedWordIndices,
    Set<int>? assistedWordIndices,
    int? correctionWordIndex,
    bool? isCorrectionProvisional,
    bool clearCorrection = false,
    bool clearSummary = false,
  }) {
    return QuranOralRecitationState(
      lifecycle: lifecycle ?? this.lifecycle,
      sessionId: sessionId ?? this.sessionId,
      surahNumber: surahNumber ?? this.surahNumber,
      surahName: surahName ?? this.surahName,
      startGlobalAyah: startGlobalAyah ?? this.startGlobalAyah,
      endGlobalAyah: endGlobalAyah ?? this.endGlobalAyah,
      planId: planId ?? this.planId,
      targetWords: targetWords ?? this.targetWords,
      alignedWords: alignedWords ?? this.alignedWords,
      discrepancies: discrepancies ?? this.discrepancies,
      currentGlobalAyah: currentGlobalAyah ?? this.currentGlobalAyah,
      currentWordIndex: currentWordIndex ?? this.currentWordIndex,
      committedTargetIndex: committedTargetIndex ?? this.committedTargetIndex,
      liveTranscript: liveTranscript ?? this.liveTranscript,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      matchedWordsCount: matchedWordsCount ?? this.matchedWordsCount,
      omissionsCount: omissionsCount ?? this.omissionsCount,
      substitutionsCount: substitutionsCount ?? this.substitutionsCount,
      uncertainCount: uncertainCount ?? this.uncertainCount,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      revealedGlobals: revealedGlobals ?? this.revealedGlobals,
      completedGlobalAyahs: completedGlobalAyahs ?? this.completedGlobalAyahs,
      previewCompletedGlobalAyahs:
          previewCompletedGlobalAyahs ?? this.previewCompletedGlobalAyahs,
      visibleWordIndices: visibleWordIndices ?? this.visibleWordIndices,
      mistakeWordIndices: mistakeWordIndices ?? this.mistakeWordIndices,
      unresolvedMistakeWordIndices:
          unresolvedMistakeWordIndices ?? this.unresolvedMistakeWordIndices,
      summary: clearSummary ? null : (summary ?? this.summary),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isCommittingToMemorization:
          isCommittingToMemorization ?? this.isCommittingToMemorization,
      isMemorizationCommitted:
          isMemorizationCommitted ?? this.isMemorizationCommitted,
      mode: mode ?? this.mode,
      isOfflineEngine: isOfflineEngine ?? this.isOfflineEngine,
      audioLevel: audioLevel ?? this.audioLevel,
      isProcessingSpeech: isProcessingSpeech ?? this.isProcessingSpeech,
      isDraining: isDraining ?? this.isDraining,
      hintCount: hintCount ?? this.hintCount,
      hintedGlobalAyahs: hintedGlobalAyahs ?? this.hintedGlobalAyahs,
      hintedWordIndices: hintedWordIndices ?? this.hintedWordIndices,
      assistedWordIndices: assistedWordIndices ?? this.assistedWordIndices,
      correctionWordIndex: clearCorrection
          ? null
          : (correctionWordIndex ?? this.correctionWordIndex),
      isCorrectionProvisional: clearCorrection
          ? false
          : (isCorrectionProvisional ?? this.isCorrectionProvisional),
    );
  }

  @override
  List<Object?> get props => [
    lifecycle,
    sessionId,
    surahNumber,
    surahName,
    startGlobalAyah,
    endGlobalAyah,
    planId,
    targetWords,
    alignedWords,
    discrepancies,
    currentGlobalAyah,
    currentWordIndex,
    committedTargetIndex,
    liveTranscript,
    progressPercentage,
    matchedWordsCount,
    omissionsCount,
    substitutionsCount,
    uncertainCount,
    durationSeconds,
    revealedGlobals,
    completedGlobalAyahs,
    previewCompletedGlobalAyahs,
    visibleWordIndices,
    mistakeWordIndices,
    unresolvedMistakeWordIndices,
    summary,
    errorMessage,
    isCommittingToMemorization,
    isMemorizationCommitted,
    mode,
    isOfflineEngine,
    audioLevel,
    isProcessingSpeech,
    isDraining,
    hintCount,
    hintedGlobalAyahs,
    hintedWordIndices,
    assistedWordIndices,
    correctionWordIndex,
    isCorrectionProvisional,
  ];
}
