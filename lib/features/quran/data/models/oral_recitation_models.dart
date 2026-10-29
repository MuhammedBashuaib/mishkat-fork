import 'package:equatable/equatable.dart';

import 'murajaah_models.dart';

/// The status of an individual word in the target Quranic sequence after speech alignment.
enum WordAlignmentStatus {
  /// Word was recited correctly and matches the authoritative Quranic text.
  matched,

  /// Expected Quranic word was skipped or omitted by the reciter.
  omission,

  /// Reciter substituted the expected word with a different word or pronunciation.
  substitution,

  /// Reciter repeated a previously recited word or phrase (e.g. self-correction).
  repetition,

  /// Recognition confidence is borderline or phonetically ambiguous.
  uncertain,

  /// Word has not yet been recited in the active sequence.
  upcoming;

  bool get isMatched => this == WordAlignmentStatus.matched;
  bool get isOmission => this == WordAlignmentStatus.omission;
  bool get isSubstitution => this == WordAlignmentStatus.substitution;
  bool get isRepetition => this == WordAlignmentStatus.repetition;
  bool get isUncertain => this == WordAlignmentStatus.uncertain;
  bool get isUpcoming => this == WordAlignmentStatus.upcoming;

  String get arabicLabel => switch (this) {
    WordAlignmentStatus.matched => 'صحيح',
    WordAlignmentStatus.omission => 'سقط / نسيان',
    WordAlignmentStatus.substitution => 'خطأ / استبدال',
    WordAlignmentStatus.repetition => 'تكرار / استدراك',
    WordAlignmentStatus.uncertain => 'غير مؤكد',
    WordAlignmentStatus.upcoming => 'قادم',
  };
}

/// Represents an authoritative word token from the canonical Quran text.
class AuthoritativeWord extends Equatable {
  const AuthoritativeWord({
    required this.globalAyah,
    required this.surah,
    required this.ayahInSurah,
    required this.wordIndex,
    required this.uthmaniText,
    required this.normalizedText,
  });

  /// Global Ayah index (1..6236).
  final int globalAyah;

  /// Surah number (1..114).
  final int surah;

  /// Ayah number within Surah.
  final int ayahInSurah;

  /// 0-based word index in the Ayah or target sequence.
  final int wordIndex;

  /// Authoritative text in Uthmani script with full diacritics.
  final String uthmaniText;

  /// Stripped, normalized text used strictly for comparison.
  final String normalizedText;

  @override
  List<Object?> get props => [
    globalAyah,
    surah,
    ayahInSurah,
    wordIndex,
    uthmaniText,
    normalizedText,
  ];
}

/// Represents the aligned state of an individual word during an oral recitation session.
class RecitationWordAlignment extends Equatable {
  const RecitationWordAlignment({
    required this.authoritativeWord,
    required this.status,
    this.recognizedWord,
    this.confidence = 1.0,
  });

  final AuthoritativeWord authoritativeWord;
  final WordAlignmentStatus status;
  final String? recognizedWord;
  final double confidence;

  RecitationWordAlignment copyWith({
    AuthoritativeWord? authoritativeWord,
    WordAlignmentStatus? status,
    String? recognizedWord,
    double? confidence,
  }) {
    return RecitationWordAlignment(
      authoritativeWord: authoritativeWord ?? this.authoritativeWord,
      status: status ?? this.status,
      recognizedWord: recognizedWord ?? this.recognizedWord,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  List<Object?> get props => [
    authoritativeWord,
    status,
    recognizedWord,
    confidence,
  ];
}

/// Structured discrepancy information for inspection when a word is flagged.
class RecitationDiscrepancy extends Equatable {
  const RecitationDiscrepancy({
    required this.id,
    required this.globalAyah,
    required this.surah,
    required this.ayahInSurah,
    required this.wordIndex,
    required this.expectedUthmani,
    required this.expectedNormalized,
    this.recognizedWord,
    required this.status,
    required this.explanation,
  });

  final String id;
  final int globalAyah;
  final int surah;
  final int ayahInSurah;
  final int wordIndex;
  final String expectedUthmani;
  final String expectedNormalized;
  final String? recognizedWord;
  final WordAlignmentStatus status;
  final String explanation;

  @override
  List<Object?> get props => [
    id,
    globalAyah,
    surah,
    ayahInSurah,
    wordIndex,
    expectedUthmani,
    expectedNormalized,
    recognizedWord,
    status,
    explanation,
  ];
}

/// Comprehensive summary of a completed Oral Recitation session.
class OralRecitationSessionSummary extends Equatable {
  const OralRecitationSessionSummary({
    required this.sessionId,
    required this.startGlobalAyah,
    required this.endGlobalAyah,
    required this.surahNumber,
    required this.surahName,
    required this.totalAyahs,
    required this.matchedAyahs,
    required this.totalWords,
    required this.matchedWords,
    required this.omissionsCount,
    required this.substitutionsCount,
    required this.uncertainCount,
    required this.accuracyPercentage,
    required this.durationSeconds,
    required this.discrepancies,
    required this.completedAt,
  });

  final String sessionId;
  final int startGlobalAyah;
  final int endGlobalAyah;
  final int surahNumber;
  final String surahName;
  final int totalAyahs;
  final int matchedAyahs;
  final int totalWords;
  final int matchedWords;
  final int omissionsCount;
  final int substitutionsCount;
  final int uncertainCount;
  final double accuracyPercentage;
  final int durationSeconds;
  final List<RecitationDiscrepancy> discrepancies;
  final DateTime completedAt;

  ReviewOutcome get suggestedOutcome {
    if (accuracyPercentage >= 95.0 &&
        omissionsCount == 0 &&
        substitutionsCount == 0) {
      return ReviewOutcome.easy;
    }
    if (accuracyPercentage >= 85.0 && substitutionsCount <= 1) {
      return ReviewOutcome.good;
    }
    if (accuracyPercentage >= 65.0) {
      return ReviewOutcome.difficult;
    }
    return ReviewOutcome.failed;
  }

  @override
  List<Object?> get props => [
    sessionId,
    startGlobalAyah,
    endGlobalAyah,
    surahNumber,
    surahName,
    totalAyahs,
    matchedAyahs,
    totalWords,
    matchedWords,
    omissionsCount,
    substitutionsCount,
    uncertainCount,
    accuracyPercentage,
    durationSeconds,
    discrepancies,
    completedAt,
  ];
}

/// Lifecycle states of the Oral Recitation Cubit.
enum OralRecitationLifecycle {
  /// Session has not started; idle / initial.
  idle,

  /// Prompting for or requesting microphone and speech recognition permissions.
  requestingPermission,

  /// Permission was granted by the user.
  permissionGranted,

  /// Initializing the platform speech recognition engine.
  initializingSpeechEngine,

  /// Permission was denied by the user.
  permissionDenied,

  /// Permission was permanently denied; requires opening app settings.
  permissionPermanentlyDenied,

  /// Speech recognizer is not available on this platform/device.
  recognizerUnavailable,

  /// The recognizer exists, but Arabic is not installed/enabled for it.
  languageUnavailable,

  /// Permissions granted, target passage loaded, ready to begin recitation.
  ready,

  /// Actively capturing audio from the microphone and processing speech.
  listening,

  /// Audio capture momentarily paused by the user.
  paused,

  /// Processing final alignment before closing.
  processing,

  /// Session completed; summary ready for inspection and memorization commit.
  completed,

  /// An unrecoverable runtime error occurred.
  error;

  bool get isIdle => this == OralRecitationLifecycle.idle;
  bool get isRequestingPermission =>
      this == OralRecitationLifecycle.requestingPermission;
  bool get isPermissionGranted =>
      this == OralRecitationLifecycle.permissionGranted;
  bool get isInitializingSpeechEngine =>
      this == OralRecitationLifecycle.initializingSpeechEngine;
  bool get isPermissionDenied =>
      this == OralRecitationLifecycle.permissionDenied;
  bool get isPermissionPermanentlyDenied =>
      this == OralRecitationLifecycle.permissionPermanentlyDenied;
  bool get isRecognizerUnavailable =>
      this == OralRecitationLifecycle.recognizerUnavailable;
  bool get isLanguageUnavailable =>
      this == OralRecitationLifecycle.languageUnavailable;
  bool get isReady => this == OralRecitationLifecycle.ready;
  bool get isListening => this == OralRecitationLifecycle.listening;
  bool get isPaused => this == OralRecitationLifecycle.paused;
  bool get isCompleted => this == OralRecitationLifecycle.completed;
  bool get isError => this == OralRecitationLifecycle.error;
}
