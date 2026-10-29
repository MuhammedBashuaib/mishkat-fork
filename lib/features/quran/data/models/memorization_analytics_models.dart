import 'package:equatable/equatable.dart';

import 'memorization_plan.dart';
import 'murajaah_models.dart';

/// Direction of review activity over time.
enum TrendDirection {
  increasing,
  stable,
  decreasing,
  insufficientData;

  String get label => switch (this) {
    TrendDirection.increasing => 'في ازدياد',
    TrendDirection.stable => 'مستقر',
    TrendDirection.decreasing => 'في تراجع',
    TrendDirection.insufficientData => 'بيانات غير كافية',
  };

  String get arabicLabel => label;
}

/// Pace health status of an active memorization plan.
enum PlanPaceStatus {
  onTrack,
  ahead,
  needsAttention,
  insufficientData;

  String get label => switch (this) {
    PlanPaceStatus.onTrack => 'على المسار',
    PlanPaceStatus.ahead => 'متقدم',
    PlanPaceStatus.needsAttention => 'يحتاج اهتماماً',
    PlanPaceStatus.insufficientData => 'بيانات غير كافية',
  };

  String get arabicLabel => label;
}

/// Workload level category for upcoming review commitments.
enum WorkloadLevel {
  light,
  moderate,
  heavy;

  String get label => switch (this) {
    WorkloadLevel.light => 'خفيف',
    WorkloadLevel.moderate => 'متوسط',
    WorkloadLevel.heavy => 'مرتفع',
  };

  String get arabicLabel => label;
}

/// Overall Quran memorization coverage metrics.
class OverallMemorizationAnalytics extends Equatable {
  const OverallMemorizationAnalytics({
    this.totalAyahs = 6236,
    required this.memorized,
    required this.learning,
    required this.needsRevision,
    required this.notStarted,
    required this.coveragePercentage,
    required this.dueToday,
    required this.overdue,
    required this.weak,
  });

  /// The canonical Quranic Ayah count (6,236).
  final int totalAyahs;

  /// Count of Ayahs marked as memorized.
  final int memorized;

  /// Count of Ayahs currently being learned.
  final int learning;

  /// Count of Ayahs flagged as needing revision.
  final int needsRevision;

  /// Count of Ayahs not yet initiated.
  final int notStarted;

  /// Fraction of total Ayahs confirmed memorized (0.0 .. 1.0).
  final double coveragePercentage;

  /// Count of Ayahs due for review today.
  final int dueToday;

  /// Count of Ayahs overdue for review.
  final int overdue;

  /// Count of Ayahs exhibiting retention weakness.
  final int weak;

  /// Human-readable percentage string (e.g. "19.5%").
  String get formattedPercentage =>
      '${(coveragePercentage * 100).toStringAsFixed(1)}%';

  @override
  List<Object?> get props => [
    totalAyahs,
    memorized,
    learning,
    needsRevision,
    notStarted,
    coveragePercentage,
    dueToday,
    overdue,
    weak,
  ];
}

/// Retention and performance analysis derived from retained review history.
class ReviewRetentionAnalytics extends Equatable {
  const ReviewRetentionAnalytics({
    required this.totalReviews,
    required this.easyCount,
    required this.goodCount,
    required this.difficultCount,
    required this.failedCount,
    required this.successRate,
    required this.difficultRate,
    required this.failureRate,
    required this.reviewsToday,
    required this.reviewsThisWeek,
    required this.reviewsThisMonth,
    required this.averageReviewsPerActiveDay,
    required this.hasSufficientData,
  });

  /// Total review records evaluated from the retained history (up to 2,000).
  final int totalReviews;

  /// Number of easy recalls.
  final int easyCount;

  /// Number of good recalls.
  final int goodCount;

  /// Number of difficult recall attempts.
  final int difficultCount;

  /// Number of failed recalls.
  final int failedCount;

  /// Ratio of successful recalls (easy + good) to total reviews (0.0 .. 1.0), or null if insufficient.
  final double? successRate;

  /// Ratio of difficult recalls to total reviews (0.0 .. 1.0), or null if insufficient.
  final double? difficultRate;

  /// Ratio of failed recalls to total reviews (0.0 .. 1.0), or null if insufficient.
  final double? failureRate;

  /// Reviews conducted today.
  final int reviewsToday;

  /// Reviews conducted in the last 7 calendar days.
  final int reviewsThisWeek;

  /// Reviews conducted in the last 30 calendar days.
  final int reviewsThisMonth;

  /// Average reviews per day that had at least one review.
  final double averageReviewsPerActiveDay;

  /// Whether sample size is sufficient (>= 5 reviews) to present meaningful ratios.
  final bool hasSufficientData;

  /// Successful reviews total (easy + good).
  int get successfulCount => easyCount + goodCount;

  @override
  List<Object?> get props => [
    totalReviews,
    easyCount,
    goodCount,
    difficultCount,
    failedCount,
    successRate,
    difficultRate,
    failureRate,
    reviewsToday,
    reviewsThisWeek,
    reviewsThisMonth,
    averageReviewsPerActiveDay,
    hasSufficientData,
  ];
}

/// Activity trend over 7-day and 30-day evaluation windows.
class MurajaahTrendAnalytics extends Equatable {
  const MurajaahTrendAnalytics({
    required this.direction,
    required this.reviewsLast7Days,
    required this.reviewsPrevious7Days,
    required this.reviewsLast30Days,
    required this.reviewsPrevious30Days,
    required this.description,
  });

  final TrendDirection direction;
  final int reviewsLast7Days;
  final int reviewsPrevious7Days;
  final int reviewsLast30Days;
  final int reviewsPrevious30Days;
  final String description;

  @override
  List<Object?> get props => [
    direction,
    reviewsLast7Days,
    reviewsPrevious7Days,
    reviewsLast30Days,
    reviewsPrevious30Days,
    description,
  ];
}

/// Mastery breakdown for a specific Surah.
class SurahMemorizationAnalytics extends Equatable {
  const SurahMemorizationAnalytics({
    required this.surahNumber,
    required this.name,
    required this.totalAyahs,
    required this.memorizedCount,
    required this.learningCount,
    required this.needsRevisionCount,
    required this.weakCount,
    required this.completionPercentage,
  });

  final int surahNumber;
  final String name;
  final int totalAyahs;
  final int memorizedCount;
  final int learningCount;
  final int needsRevisionCount;
  final int weakCount;
  final double completionPercentage;

  bool get isCompleted => memorizedCount >= totalAyahs && totalAyahs > 0;

  @override
  List<Object?> get props => [
    surahNumber,
    name,
    totalAyahs,
    memorizedCount,
    learningCount,
    needsRevisionCount,
    weakCount,
    completionPercentage,
  ];
}

/// Mastery breakdown for a canonical Juz ($1 \dots 30$).
class JuzMemorizationAnalytics extends Equatable {
  const JuzMemorizationAnalytics({
    required this.juzNumber,
    required this.startGlobalAyah,
    required this.endGlobalAyah,
    required this.totalAyahs,
    required this.memorizedCount,
    required this.learningCount,
    required this.needsRevisionCount,
    required this.weakCount,
    required this.completionPercentage,
  });

  final int juzNumber;
  final int startGlobalAyah;
  final int endGlobalAyah;
  final int totalAyahs;
  final int memorizedCount;
  final int learningCount;
  final int needsRevisionCount;
  final int weakCount;
  final double completionPercentage;

  bool get isCompleted => memorizedCount >= totalAyahs && totalAyahs > 0;

  @override
  List<Object?> get props => [
    juzNumber,
    startGlobalAyah,
    endGlobalAyah,
    totalAyahs,
    memorizedCount,
    learningCount,
    needsRevisionCount,
    weakCount,
    completionPercentage,
  ];
}

/// Progress and pacing intelligence for an active memorization plan.
class PlanProgressAnalytics extends Equatable {
  const PlanProgressAnalytics({
    required this.plan,
    required this.totalAyahs,
    required this.memorizedCount,
    required this.learningCount,
    required this.needsRevisionCount,
    required this.remainingCount,
    required this.completionPercentage,
    required this.dailyTarget,
    required this.estimatedDaysRemaining,
    required this.currentPace,
    required this.paceStatus,
    required this.paceMessage,
  });

  final MemorizationPlan plan;
  final int totalAyahs;
  final int memorizedCount;
  final int learningCount;
  final int needsRevisionCount;
  final int remainingCount;
  final double completionPercentage;
  final int dailyTarget;
  final int estimatedDaysRemaining;
  final double currentPace;
  final PlanPaceStatus paceStatus;
  final String paceMessage;

  @override
  List<Object?> get props => [
    plan,
    totalAyahs,
    memorizedCount,
    learningCount,
    needsRevisionCount,
    remainingCount,
    completionPercentage,
    dailyTarget,
    estimatedDaysRemaining,
    currentPace,
    paceStatus,
    paceMessage,
  ];
}

/// Workload forecast for upcoming Muraja'ah.
class ReviewWorkloadForecast extends Equatable {
  const ReviewWorkloadForecast({
    required this.dueTodayCount,
    required this.dueTomorrowCount,
    required this.dueNext7DaysCount,
    required this.workloadLevel,
  });

  final int dueTodayCount;
  final int dueTomorrowCount;
  final int dueNext7DaysCount;
  final WorkloadLevel workloadLevel;

  @override
  List<Object?> get props => [
    dueTodayCount,
    dueTomorrowCount,
    dueNext7DaysCount,
    workloadLevel,
  ];
}

/// Focused insight on an individual Ayah requiring attention or consolidation.
class WeakAyahInsight extends Equatable {
  const WeakAyahInsight({
    required this.globalAyah,
    required this.surahNumber,
    required this.surahName,
    required this.ayahNumber,
    required this.mistakeCount,
    required this.scheduleState,
    this.lastOutcome,
    this.nextReviewAt,
    required this.priorityScore,
  });

  final int globalAyah;
  final int surahNumber;
  final String surahName;
  final int ayahNumber;
  final int mistakeCount;
  final AdaptiveScheduleState scheduleState;
  final ReviewOutcome? lastOutcome;
  final DateTime? nextReviewAt;
  final double priorityScore;

  @override
  List<Object?> get props => [
    globalAyah,
    surahNumber,
    surahName,
    ayahNumber,
    mistakeCount,
    scheduleState,
    lastOutcome,
    nextReviewAt,
    priorityScore,
  ];
}

/// Comprehensive container uniting all memorization and Muraja'ah analytics.
class ComprehensiveMemorizationAnalytics extends Equatable {
  const ComprehensiveMemorizationAnalytics({
    required this.overall,
    required this.retention,
    required this.trend,
    required this.forecast,
    this.plan,
    required this.weakAyahs,
    required this.surahs,
    required this.juzs,
    required this.generatedAt,
  });

  final OverallMemorizationAnalytics overall;
  final ReviewRetentionAnalytics retention;
  final MurajaahTrendAnalytics trend;
  final ReviewWorkloadForecast forecast;
  final PlanProgressAnalytics? plan;
  final List<WeakAyahInsight> weakAyahs;
  final List<SurahMemorizationAnalytics> surahs;
  final List<JuzMemorizationAnalytics> juzs;
  final DateTime generatedAt;

  @override
  List<Object?> get props => [
    overall,
    retention,
    trend,
    forecast,
    plan,
    weakAyahs,
    surahs,
    juzs,
    generatedAt,
  ];
}
