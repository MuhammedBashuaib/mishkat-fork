import 'package:equatable/equatable.dart';

import 'memorization_status.dart';

/// The four discrete assessment outcomes of an Ayah recall or review drill.
enum ReviewOutcome {
  /// Ayah recalled effortlessly with high confidence.
  easy,

  /// Ayah recalled correctly with normal effort.
  good,

  /// Ayah recalled with hesitation, stumbles, or required minor assistance.
  difficult,

  /// Ayah could not be recalled, had serious mistakes, or required reading.
  failed;

  /// Human-readable Arabic label.
  String get label => switch (this) {
    ReviewOutcome.easy => 'سهل',
    ReviewOutcome.good => 'جيد',
    ReviewOutcome.difficult => 'صعب',
    ReviewOutcome.failed => 'لم أتذكر',
  };

  /// Alias for design terminology.
  String get arabicLabel => label;

  /// Maps outcome to corresponding [MemorizationStatus].
  MemorizationStatus get resultingStatus => switch (this) {
    ReviewOutcome.easy || ReviewOutcome.good => MemorizationStatus.memorized,
    ReviewOutcome.difficult ||
    ReviewOutcome.failed => MemorizationStatus.needsRevision,
  };

  /// Parses a serialized name safely.
  static ReviewOutcome fromString(String? value) {
    if (value == null) return ReviewOutcome.good;
    return ReviewOutcome.values.firstWhere(
      (o) => o.name == value,
      orElse: () => ReviewOutcome.good,
    );
  }
}

/// The computed adaptive scheduling state of an Ayah relative to the current time.
enum AdaptiveScheduleState {
  /// Not yet scheduled or not yet due for review.
  notDue,

  /// Scheduled for review today.
  due,

  /// Review date has passed and Ayah is overdue.
  overdue,

  /// Ayah has multiple mistakes or difficult outcomes and needs consolidation.
  weak,

  /// Ayah has consecutive failures or is critically overdue.
  urgent;

  /// Human-readable Arabic label.
  String get label => switch (this) {
    AdaptiveScheduleState.notDue => 'غير مستحقة',
    AdaptiveScheduleState.due => 'مستحقة اليوم',
    AdaptiveScheduleState.overdue => 'متأخرة',
    AdaptiveScheduleState.weak => 'تحتاج تثبيت',
    AdaptiveScheduleState.urgent => 'عاجلة',
  };

  String get arabicLabel => label;
}

/// User-selectable review category modes for targeted Muraja'ah.
enum AdaptiveMurajaahCategory {
  /// Ayahs due for spaced review today.
  dueToday,

  /// Ayahs whose scheduled review date has passed.
  overdue,

  /// Ayahs flagged with high mistake counts or needsRevision.
  weak,

  /// Ayahs whose most recent review was difficult or failed.
  recentlyDifficult,

  /// Ayahs ordered strictly by total mistake count descending.
  mistakeBased,

  /// Comprehensive blended adaptive queue.
  all;

  String get label => switch (this) {
    AdaptiveMurajaahCategory.dueToday => 'مستحقة اليوم',
    AdaptiveMurajaahCategory.overdue => 'متأخرة',
    AdaptiveMurajaahCategory.weak => 'تحتاج تثبيت',
    AdaptiveMurajaahCategory.recentlyDifficult => 'صعبة مؤخراً',
    AdaptiveMurajaahCategory.mistakeBased => 'حسب الأخطاء',
    AdaptiveMurajaahCategory.all => 'شاملة',
  };

  String get arabicLabel => label;
}

/// Immutable record of a single completed review or self-assessment event.
class MemorizationReviewRecord extends Equatable {
  const MemorizationReviewRecord({
    required this.id,
    required this.globalAyah,
    this.planId,
    this.sessionId,
    required this.outcome,
    required this.mistakeCount,
    required this.reviewedAt,
    this.intervalDays = 1,
    this.previousStatus,
    this.resultingStatus,
  }) : assert(
         globalAyah >= 1 && globalAyah <= 6236,
         'globalAyah must be between 1 and 6236, got $globalAyah',
       ),
       assert(mistakeCount >= 0, 'mistakeCount must not be negative'),
       assert(intervalDays >= 0, 'intervalDays must not be negative');

  /// Unique identifier (e.g. `rev_timestamp_globalAyah`).
  final String id;

  /// The canonical global Ayah index (1..6236).
  final int globalAyah;

  /// ID of the active plan during this review, if applicable.
  final String? planId;

  /// ID of the session during this review, if applicable.
  final String? sessionId;

  /// Assessment outcome chosen by the user.
  final ReviewOutcome outcome;

  /// Snapshot of the Ayah's mistake count at the time of review.
  final int mistakeCount;

  /// Timestamp when the review took place.
  final DateTime reviewedAt;

  /// Scheduled interval in days calculated for the subsequent review.
  final int intervalDays;

  /// The status before this review occurred.
  final MemorizationStatus? previousStatus;

  /// The status resulting from this review.
  final MemorizationStatus? resultingStatus;

  factory MemorizationReviewRecord.fromJson(Map<String, dynamic> json) {
    final rawGlobal = (json['g'] ?? json['globalAyah']) as num?;
    if (rawGlobal == null) {
      throw const FormatException('Missing globalAyah in review record');
    }
    final global = rawGlobal.toInt().clamp(1, 6236);

    final id =
        (json['id'] as String?) ??
        'rev_${DateTime.now().millisecondsSinceEpoch}_$global';

    final outcome = ReviewOutcome.fromString(
      (json['o'] ?? json['outcome']) as String?,
    );

    final rawMistakes = (json['m'] ?? json['mistakeCount']) as num?;
    final mistakeCount = (rawMistakes?.toInt() ?? 0).clamp(0, 999999);

    final rawReviewed = json['r'] ?? json['reviewedAt'];
    final reviewedAt =
        (rawReviewed is String ? DateTime.tryParse(rawReviewed) : null) ??
        DateTime.now();

    final rawInterval = (json['iv'] ?? json['intervalDays']) as num?;
    final intervalDays = (rawInterval?.toInt() ?? 1).clamp(0, 365);

    final planId = json['p'] as String? ?? json['planId'] as String?;
    final sessionId = json['s'] as String? ?? json['sessionId'] as String?;

    final prevStatusStr =
        json['ps'] as String? ?? json['previousStatus'] as String?;
    final previousStatus = prevStatusStr != null
        ? MemorizationStatus.fromString(prevStatusStr)
        : null;

    final resStatusStr =
        json['rs'] as String? ?? json['resultingStatus'] as String?;
    final resultingStatus = resStatusStr != null
        ? MemorizationStatus.fromString(resStatusStr)
        : null;

    return MemorizationReviewRecord(
      id: id,
      globalAyah: global,
      planId: planId,
      sessionId: sessionId,
      outcome: outcome,
      mistakeCount: mistakeCount,
      reviewedAt: reviewedAt,
      intervalDays: intervalDays,
      previousStatus: previousStatus,
      resultingStatus: resultingStatus,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'g': globalAyah,
    if (planId != null) 'p': planId,
    if (sessionId != null) 's': sessionId,
    'o': outcome.name,
    'm': mistakeCount,
    'r': reviewedAt.toIso8601String(),
    'iv': intervalDays,
    if (previousStatus != null) 'ps': previousStatus!.name,
    if (resultingStatus != null) 'rs': resultingStatus!.name,
  };

  @override
  List<Object?> get props => [
    id,
    globalAyah,
    planId,
    sessionId,
    outcome,
    mistakeCount,
    reviewedAt,
    intervalDays,
    previousStatus,
    resultingStatus,
  ];
}

/// Explainable priority score components for an individual Ayah.
class MurajaahPriorityScore extends Equatable {
  const MurajaahPriorityScore({
    required this.globalAyah,
    required this.totalScore,
    required this.overdueWeight,
    required this.weaknessWeight,
    required this.mistakeWeight,
    required this.recentFailureWeight,
    required this.reviewGapWeight,
    required this.scheduleState,
  });

  final int globalAyah;
  final double totalScore;
  final double overdueWeight;
  final double weaknessWeight;
  final double mistakeWeight;
  final double recentFailureWeight;
  final double reviewGapWeight;
  final AdaptiveScheduleState scheduleState;

  @override
  List<Object?> get props => [
    globalAyah,
    totalScore,
    overdueWeight,
    weaknessWeight,
    mistakeWeight,
    recentFailureWeight,
    reviewGapWeight,
    scheduleState,
  ];
}
