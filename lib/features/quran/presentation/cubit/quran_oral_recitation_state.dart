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
    this.summary,
    this.errorMessage,
    this.isCommittingToMemorization = false,
    this.isMemorizationCommitted = false,
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
  final OralRecitationSessionSummary? summary;
  final String? errorMessage;
  final bool isCommittingToMemorization;
  final bool isMemorizationCommitted;

  bool get isListening => lifecycle.isListening;
  bool get isPaused => lifecycle.isPaused;
  bool get isCompleted => lifecycle.isCompleted;
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
    OralRecitationSessionSummary? summary,
    String? errorMessage,
    bool clearError = false,
    bool? isCommittingToMemorization,
    bool? isMemorizationCommitted,
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
      summary: summary ?? this.summary,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isCommittingToMemorization:
          isCommittingToMemorization ?? this.isCommittingToMemorization,
      isMemorizationCommitted:
          isMemorizationCommitted ?? this.isMemorizationCommitted,
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
    summary,
    errorMessage,
    isCommittingToMemorization,
    isMemorizationCommitted,
  ];
}
