import 'package:equatable/equatable.dart';

import 'memorization_analytics_models.dart';
import 'memorization_plan.dart';

/// The distinct category of an individual segment within the daily journey.
enum HifzJourneySegmentType {
  /// Spaced repetition review of due and overdue Ayahs.
  dueMurajaah,

  /// Targeted consolidation of weak Ayahs, recurring mistakes, or difficult recalls.
  weakConsolidation,

  /// Forward memorization of new Ayahs from the active plan.
  newHifz;

  /// Arabic label for display in UI chips and headers.
  String get label => switch (this) {
    HifzJourneySegmentType.dueMurajaah => 'المراجعة المستحقة',
    HifzJourneySegmentType.weakConsolidation => 'تثبيت المواضع الضعيفة',
    HifzJourneySegmentType.newHifz => 'الحفظ الجديد',
  };

  String get arabicLabel => label;

  /// Default subtitle explaining the segment purpose calmly.
  String get description => switch (this) {
    HifzJourneySegmentType.dueMurajaah =>
      'آيات حان موعد مراجعتها اليوم للحفاظ على رسوخها',
    HifzJourneySegmentType.weakConsolidation =>
      'آيات تحتاج تثبيتاً وعناية إضافية لضبط الإتقان',
    HifzJourneySegmentType.newHifz =>
      'آيات جديدة لم تدرسها بعد وفق خطتك المعتمدة',
  };
}

/// An individual segment of the recommended daily Quran journey.
class HifzJourneySegment extends Equatable {
  const HifzJourneySegment({
    required this.type,
    required this.queue,
    this.customTitle,
    this.customDescription,
  });

  /// The segment category.
  final HifzJourneySegmentType type;

  /// Ordered list of canonical global Ayah indices (1..6236).
  final List<int> queue;

  final String? customTitle;
  final String? customDescription;

  /// Localized title.
  String get title => customTitle ?? type.label;

  /// Localized description.
  String get description => customDescription ?? type.description;

  /// Number of Ayahs in this segment.
  int get count => queue.length;

  /// Whether this segment has no Ayahs scheduled.
  bool get isEmpty => queue.isEmpty;

  /// Whether this segment contains scheduled Ayahs.
  bool get isNotEmpty => queue.isNotEmpty;

  @override
  List<Object?> get props => [type, queue, customTitle, customDescription];
}

/// The synthesized, balanced daily Quran memorization journey ("وردك اليومي المقترح").
class DailyHifzJourney extends Equatable {
  const DailyHifzJourney({
    required this.segments,
    required this.dueMurajaahQueue,
    required this.weakAyahsQueue,
    required this.newHifzQueue,
    required this.recommendedNewHifzTarget,
    this.effectiveNewHifzTarget,
    required this.workloadLevel,
    required this.isRecoveryMode,
    this.recoveryBacklogCount = 0,
    required this.rationaleMessage,
    required this.evaluatedAt,
    this.plan,
  });

  /// All individual journey segments in presentation order.
  final List<HifzJourneySegment> segments;

  /// Canonical global Ayah queue for Due Muraja'ah.
  final List<int> dueMurajaahQueue;

  /// Canonical global Ayah queue for Weak Ayah consolidation.
  final List<int> weakAyahsQueue;

  /// Canonical global Ayah queue for New Hifz.
  final List<int> newHifzQueue;

  /// System-recommended new Hifz target (balanced against review workload).
  final int recommendedNewHifzTarget;

  /// User-overridden target, or defaults to [recommendedNewHifzTarget].
  final int? effectiveNewHifzTarget;

  /// Current cognitive workload level (light, moderate, heavy).
  final WorkloadLevel workloadLevel;

  /// Whether Gentle Recovery Mode ("وضع التعويض الهادئ") is active.
  final bool isRecoveryMode;

  /// Total count of overdue reviews remaining in backlog (if in recovery mode).
  final int recoveryBacklogCount;

  /// Dignified Arabic explanation of today's recommendation and pacing rationale.
  final String rationaleMessage;

  /// Timestamp when this daily journey was evaluated.
  final DateTime evaluatedAt;

  /// Associated active plan, if any.
  final MemorizationPlan? plan;

  /// The active new Hifz target for today (effective override or recommended).
  int get targetToday => effectiveNewHifzTarget ?? recommendedNewHifzTarget;

  /// Total number of Ayahs scheduled across all 3 segments today.
  int get totalAyahs =>
      dueMurajaahQueue.length + weakAyahsQueue.length + newHifzQueue.length;

  /// Whether the journey has no Ayahs scheduled.
  bool get isEmpty => totalAyahs == 0;

  /// Whether the journey has any Ayahs scheduled.
  bool get isNotEmpty => totalAyahs > 0;

  /// Whether there are due reviews scheduled.
  bool get hasDueMurajaah => dueMurajaahQueue.isNotEmpty;

  /// Whether there are weak Ayahs scheduled for consolidation.
  bool get hasWeakAyahs => weakAyahsQueue.isNotEmpty;

  /// Whether there are new Ayahs scheduled for memorization.
  bool get hasNewHifz => newHifzQueue.isNotEmpty;

  /// Unified, deduplicated linear queue containing all scheduled Ayahs in standard progression order:
  /// 1. Due Muraja'ah
  /// 2. Weak consolidation
  /// 3. New Hifz
  List<int> get allAyahs {
    final list = <int>[];
    final seen = <int>{};
    for (final g in dueMurajaahQueue) {
      if (seen.add(g)) list.add(g);
    }
    for (final g in weakAyahsQueue) {
      if (seen.add(g)) list.add(g);
    }
    for (final g in newHifzQueue) {
      if (seen.add(g)) list.add(g);
    }
    return list;
  }

  /// Creates a copy with optional user override for today's new Hifz target.
  DailyHifzJourney copyWithTargetOverride(
    int newTarget,
    List<int> updatedNewQueue,
  ) {
    final updatedSegments = segments.map((seg) {
      if (seg.type == HifzJourneySegmentType.newHifz) {
        return HifzJourneySegment(
          type: HifzJourneySegmentType.newHifz,
          queue: updatedNewQueue,
          customTitle: seg.customTitle,
          customDescription: seg.customDescription,
        );
      }
      return seg;
    }).toList();

    return DailyHifzJourney(
      segments: updatedSegments,
      dueMurajaahQueue: dueMurajaahQueue,
      weakAyahsQueue: weakAyahsQueue,
      newHifzQueue: updatedNewQueue,
      recommendedNewHifzTarget: recommendedNewHifzTarget,
      effectiveNewHifzTarget: newTarget,
      workloadLevel: workloadLevel,
      isRecoveryMode: isRecoveryMode,
      recoveryBacklogCount: recoveryBacklogCount,
      rationaleMessage: rationaleMessage,
      evaluatedAt: evaluatedAt,
      plan: plan,
    );
  }

  @override
  List<Object?> get props => [
    segments,
    dueMurajaahQueue,
    weakAyahsQueue,
    newHifzQueue,
    recommendedNewHifzTarget,
    effectiveNewHifzTarget,
    workloadLevel,
    isRecoveryMode,
    recoveryBacklogCount,
    rationaleMessage,
    evaluatedAt,
    plan,
  ];
}

/// Non-intrusive plan adaptation suggestion based on sustained pace over time.
class PlanAdaptationSuggestion extends Equatable {
  const PlanAdaptationSuggestion({
    required this.planId,
    required this.planTitle,
    required this.currentTarget,
    required this.recommendedTarget,
    required this.sustainedPace,
    required this.reason,
    required this.actionText,
  });

  /// ID of the plan.
  final String planId;

  /// Title of the plan.
  final String planTitle;

  /// Current configured daily target.
  final int currentTarget;

  /// Recommended adjusted daily target.
  final int recommendedTarget;

  /// Sustained average daily pace observed over recent history.
  final double sustainedPace;

  /// Dignified Arabic explanation for the suggested adjustment.
  final String reason;

  /// Action button label (e.g. "تعديل الورد إلى 3 آيات").
  final String actionText;

  @override
  List<Object?> get props => [
    planId,
    planTitle,
    currentTarget,
    recommendedTarget,
    sustainedPace,
    reason,
    actionText,
  ];
}

/// Dual completion forecast comparing commitment-based and realistic pace-based timelines.
class CompletionForecast extends Equatable {
  const CompletionForecast({
    required this.targetBasedDays,
    required this.targetBasedDescription,
    this.paceBasedDays,
    this.paceBasedDescription,
    required this.hasSufficientData,
    this.paceComparisonMessage,
  });

  /// Days remaining assuming exact fulfillment of plan's daily target.
  final int? targetBasedDays;

  /// Human-friendly Arabic approximation of target-based completion.
  final String targetBasedDescription;

  /// Days remaining based on actual sustained pace.
  final int? paceBasedDays;

  /// Human-friendly Arabic approximation of realistic pace-based completion.
  final String? paceBasedDescription;

  /// Whether sufficient historical activity exists (>= 5 active review days).
  final bool hasSufficientData;

  /// Optional comparison message between the two forecasts.
  final String? paceComparisonMessage;

  @override
  List<Object?> get props => [
    targetBasedDays,
    targetBasedDescription,
    paceBasedDays,
    paceBasedDescription,
    hasSufficientData,
    paceComparisonMessage,
  ];
}
