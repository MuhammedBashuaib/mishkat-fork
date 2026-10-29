import 'package:equatable/equatable.dart';

import '../../data/models/hifz_planning_models.dart';
import '../../data/models/memorization_analytics_models.dart';
import '../../data/models/memorization_item.dart';
import '../../data/models/memorization_plan.dart';
import '../../data/models/memorization_session.dart';
import '../../data/models/memorization_status.dart';
import '../../data/models/murajaah_models.dart';
import '../../data/models/quran_models.dart';
import '../services/adaptive_murajaah_engine.dart';
import '../services/hifz_planning_engine.dart';
import '../services/memorization_analytics_engine.dart';

enum QuranMemorizationStatus { initial, loading, ready, failure }

class QuranMemorizationState extends Equatable {
  const QuranMemorizationState({
    this.status = QuranMemorizationStatus.initial,
    this.plans = const [],
    this.items = const {},
    this.activeSession,
    this.error,
    this.history = const [],
  });

  final QuranMemorizationStatus status;
  final List<MemorizationPlan> plans;
  final Map<int, MemorizationItem> items;
  final MemorizationSession? activeSession;
  final String? error;
  final List<MemorizationReviewRecord> history;

  static const AdaptiveMurajaahEngine engine = AdaptiveMurajaahEngine();
  static const MemorizationAnalyticsEngine analyticsEngine =
      MemorizationAnalyticsEngine();
  static const HifzPlanningEngine planningEngine = HifzPlanningEngine();

  /// Computes a comprehensive analytics snapshot on demand from current authoritative state.
  ComprehensiveMemorizationAnalytics computeAnalytics(
    QuranData quranData, {
    DateTime? now,
  }) {
    return analyticsEngine.compute(
      items: items,
      history: history,
      plans: plans,
      quranData: quranData,
      now: now,
    );
  }

  /// Calculates a personalized, balanced daily journey ("وردك اليومي المقترح").
  DailyHifzJourney calculateDailyJourney({
    DateTime? now,
    int? manualTargetOverride,
  }) {
    return planningEngine.calculateDailyJourney(
      items: items.values,
      history: history,
      activePlan: activePlan,
      now: now,
      manualTargetOverride: manualTargetOverride,
    );
  }

  /// Calculates an adaptation suggestion for the active plan, if appropriate.
  PlanAdaptationSuggestion? calculatePlanAdaptationSuggestion({DateTime? now}) {
    final plan = activePlan;
    if (plan == null) return null;
    return planningEngine.calculatePlanAdaptationSuggestion(
      plan: plan,
      items: items.values,
      history: history,
      now: now,
    );
  }

  /// Calculates dual completion forecasts (target vs pace) for [plan].
  CompletionForecast calculateCompletionForecast(
    MemorizationPlan plan, {
    DateTime? now,
  }) {
    return planningEngine.estimateRealisticCompletion(
      plan: plan,
      items: items.values,
      history: history,
      now: now,
    );
  }

  /// Currently active and unfinished plan, if one exists.
  MemorizationPlan? get activePlan {
    for (final plan in plans) {
      if (plan.isActive && !plan.isCompleted) return plan;
    }
    return null;
  }

  /// All plans that are either inactive or completed.
  List<MemorizationPlan> get archivedPlans =>
      plans.where((p) => !p.isActive || p.isCompleted).toList();

  /// Retrieves the personal mastery record for a specific [globalAyah].
  MemorizationItem getItem(int globalAyah) {
    final existing = items[globalAyah];
    if (existing != null) return existing;
    return MemorizationItem(
      globalAyah: globalAyah,
      status: MemorizationStatus.notStarted,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool isAyahMemorized(int globalAyah) =>
      items[globalAyah]?.status == MemorizationStatus.memorized;

  bool isAyahNeedsRevision(int globalAyah) =>
      items[globalAyah]?.status == MemorizationStatus.needsRevision;

  /// Total count of all Ayahs in the entire Quran confirmed memorized.
  int get totalMemorizedCount => items.values
      .where((i) => i.status == MemorizationStatus.memorized)
      .length;

  /// Total count of all Ayahs flagged as needing revision.
  int get totalNeedsRevisionCount => items.values
      .where((i) => i.status == MemorizationStatus.needsRevision)
      .length;

  /// Total count of all Ayahs currently in progress (learning).
  int get totalLearningCount =>
      items.values.where((i) => i.status == MemorizationStatus.learning).length;

  // ==========================================
  // ADAPTIVE MURAJA'AH GETTERS
  // ==========================================

  /// Returns list of canonical globalAyahs due for review today.
  List<int> dueTodayAyahs({DateTime? now}) {
    final current = now ?? DateTime.now();
    return items.values
        .where((i) {
          final s = engine.calculateScheduleState(i, now: current);
          return s == AdaptiveScheduleState.due ||
              s == AdaptiveScheduleState.overdue ||
              s == AdaptiveScheduleState.urgent;
        })
        .map((i) => i.globalAyah)
        .toList();
  }

  /// Returns list of canonical globalAyahs overdue for review.
  List<int> overdueAyahs({DateTime? now}) {
    final current = now ?? DateTime.now();
    return items.values
        .where((i) {
          final s = engine.calculateScheduleState(i, now: current);
          return s == AdaptiveScheduleState.overdue ||
              s == AdaptiveScheduleState.urgent;
        })
        .map((i) => i.globalAyah)
        .toList();
  }

  /// Returns list of canonical globalAyahs with significant mistakes or weak retention.
  List<int> weakAyahs({DateTime? now}) {
    final current = now ?? DateTime.now();
    return items.values
        .where((i) {
          final s = engine.calculateScheduleState(i, now: current);
          return i.status == MemorizationStatus.needsRevision ||
              i.mistakeCount >= 2 ||
              s == AdaptiveScheduleState.weak ||
              s == AdaptiveScheduleState.urgent;
        })
        .map((i) => i.globalAyah)
        .toList();
  }

  /// Returns list of canonical globalAyahs whose most recent review was difficult or failed.
  List<int> recentlyDifficultAyahs() {
    return items.values
        .where(
          (i) =>
              i.lastOutcome == ReviewOutcome.difficult ||
              i.lastOutcome == ReviewOutcome.failed,
        )
        .map((i) => i.globalAyah)
        .toList();
  }

  /// Calculates the [AdaptiveScheduleState] for a specific [globalAyah].
  AdaptiveScheduleState scheduleState(int globalAyah, {DateTime? now}) {
    final item = getItem(globalAyah);
    return engine.calculateScheduleState(item, now: now);
  }

  /// Calculates the [MurajaahPriorityScore] for a specific [globalAyah].
  MurajaahPriorityScore priorityScore(int globalAyah, {DateTime? now}) {
    final item = getItem(globalAyah);
    return engine.calculatePriority(item, now: now);
  }

  /// Total count of reviews performed today.
  int reviewsCountToday({DateTime? now}) {
    final current = now ?? DateTime.now();
    return history.where((r) {
      return r.reviewedAt.year == current.year &&
          r.reviewedAt.month == current.month &&
          r.reviewedAt.day == current.day;
    }).length;
  }

  /// Total count of reviews performed in the last 7 days.
  int reviewsCountThisWeek({DateTime? now}) {
    final current = now ?? DateTime.now();
    final cutoff = current.subtract(const Duration(days: 7));
    return history.where((r) => r.reviewedAt.isAfter(cutoff)).length;
  }

  /// Total count of reviews performed in the last 30 days.
  int reviewsCountThisMonth({DateTime? now}) {
    final current = now ?? DateTime.now();
    final cutoff = current.subtract(const Duration(days: 30));
    return history.where((r) => r.reviewedAt.isAfter(cutoff)).length;
  }

  /// Generates a queue using the [AdaptiveMurajaahEngine].
  List<int> generateAdaptiveQueue({
    AdaptiveMurajaahCategory category = AdaptiveMurajaahCategory.all,
    int limit = 20,
    DateTime? now,
  }) {
    return engine.generateQueue(
      items: items.values,
      category: category,
      limit: limit,
      now: now,
      planStart: activePlan?.startGlobalAyah,
      planEnd: activePlan?.endGlobalAyah,
    );
  }

  /// Calculates deterministic progress breakdown for [plan].
  ({
    int total,
    int memorized,
    int learning,
    int needsRevision,
    int remaining,
    double percentage,
  })
  planProgress(MemorizationPlan plan) {
    final total = plan.totalAyahs;
    var memorized = 0;
    var learning = 0;
    var needsRevision = 0;

    for (var g = plan.startGlobalAyah; g <= plan.endGlobalAyah; g++) {
      final item = items[g];
      if (item != null) {
        switch (item.status) {
          case MemorizationStatus.memorized:
            memorized++;
          case MemorizationStatus.learning:
            learning++;
          case MemorizationStatus.needsRevision:
            needsRevision++;
          case MemorizationStatus.notStarted:
            break;
        }
      }
    }

    final remaining = (total - memorized).clamp(0, total);
    final percentage = total == 0 ? 1.0 : (memorized / total).clamp(0.0, 1.0);

    return (
      total: total,
      memorized: memorized,
      learning: learning,
      needsRevision: needsRevision,
      remaining: remaining,
      percentage: percentage,
    );
  }

  /// Computes today's batch of target Ayahs for [plan].
  /// Finds the first non-memorized Ayah and selects up to [plan.dailyTarget] consecutive Ayahs.
  List<int> todayTargetAyahs(MemorizationPlan plan) {
    if (plan.totalAyahs == 0) return const [];

    // Find the first Ayah within the plan that is not yet fully memorized
    var firstUnfinished = plan.startGlobalAyah;
    while (firstUnfinished <= plan.endGlobalAyah) {
      final item = items[firstUnfinished];
      if (item == null || item.status != MemorizationStatus.memorized) {
        break;
      }
      firstUnfinished++;
    }

    // If all are memorized, return the final dailyTarget slice for reinforcement
    if (firstUnfinished > plan.endGlobalAyah) {
      final start = (plan.endGlobalAyah - plan.dailyTarget + 1).clamp(
        plan.startGlobalAyah,
        plan.endGlobalAyah,
      );
      return [for (var g = start; g <= plan.endGlobalAyah; g++) g];
    }

    final targetEnd = (firstUnfinished + plan.dailyTarget - 1).clamp(
      plan.startGlobalAyah,
      plan.endGlobalAyah,
    );

    return [for (var g = firstUnfinished; g <= targetEnd; g++) g];
  }

  /// Generates a deterministic revision queue.
  /// If [category] is provided, uses [AdaptiveMurajaahEngine].
  /// Otherwise, falls back to the Q8 4-tier algorithm for strict backward compatibility:
  /// 1. Needs revision (sorted by highest mistakeCount descending).
  /// 2. mistakeCount > 0 and not reviewed in the last 48 hours.
  /// 3. Learning (oldest practiced first).
  /// 4. Memorized (oldest lastReviewedAt first).
  /// Stable tie-breaker: globalAyah ascending.
  List<int> generateRevisionQueue({
    int limit = 20,
    DateTime? now,
    AdaptiveMurajaahCategory? category,
  }) {
    if (category != null) {
      return generateAdaptiveQueue(category: category, limit: limit, now: now);
    }

    final current = now ?? DateTime.now();
    final cutoff48h = current.subtract(const Duration(hours: 48));

    final tier1 = <MemorizationItem>[];
    final tier2 = <MemorizationItem>[];
    final tier3 = <MemorizationItem>[];
    final tier4 = <MemorizationItem>[];

    for (final item in items.values) {
      if (item.status == MemorizationStatus.needsRevision) {
        tier1.add(item);
      } else if (item.mistakeCount > 0 &&
          (item.lastReviewedAt == null ||
              item.lastReviewedAt!.isBefore(cutoff48h))) {
        tier2.add(item);
      } else if (item.status == MemorizationStatus.learning) {
        tier3.add(item);
      } else if (item.status == MemorizationStatus.memorized) {
        tier4.add(item);
      }
    }

    // Tier 1: Highest mistakeCount first, then globalAyah ascending
    tier1.sort((a, b) {
      final mistakeComp = b.mistakeCount.compareTo(a.mistakeCount);
      if (mistakeComp != 0) return mistakeComp;
      return a.globalAyah.compareTo(b.globalAyah);
    });

    // Tier 2: Oldest reviewed first, then mistakeCount desc, then globalAyah asc
    tier2.sort((a, b) {
      final aDate = a.lastReviewedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.lastReviewedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateComp = aDate.compareTo(bDate);
      if (dateComp != 0) return dateComp;
      final mistakeComp = b.mistakeCount.compareTo(a.mistakeCount);
      if (mistakeComp != 0) return mistakeComp;
      return a.globalAyah.compareTo(b.globalAyah);
    });

    // Tier 3: Oldest practiced first, then globalAyah asc
    tier3.sort((a, b) {
      final aDate = a.lastReviewedAt ?? a.updatedAt;
      final bDate = b.lastReviewedAt ?? b.updatedAt;
      final dateComp = aDate.compareTo(bDate);
      if (dateComp != 0) return dateComp;
      return a.globalAyah.compareTo(b.globalAyah);
    });

    // Tier 4: Oldest reviewed first, then globalAyah asc
    tier4.sort((a, b) {
      final aDate = a.lastReviewedAt ?? a.updatedAt;
      final bDate = b.lastReviewedAt ?? b.updatedAt;
      final dateComp = aDate.compareTo(bDate);
      if (dateComp != 0) return dateComp;
      return a.globalAyah.compareTo(b.globalAyah);
    });

    final result = <int>[];
    final seen = <int>{};

    void addTier(List<MemorizationItem> tier) {
      for (final item in tier) {
        if (result.length >= limit) return;
        if (seen.add(item.globalAyah)) {
          result.add(item.globalAyah);
        }
      }
    }

    addTier(tier1);
    addTier(tier2);
    addTier(tier3);
    addTier(tier4);

    return result;
  }

  QuranMemorizationState copyWith({
    QuranMemorizationStatus? status,
    List<MemorizationPlan>? plans,
    Map<int, MemorizationItem>? items,
    MemorizationSession? activeSession,
    bool clearActiveSession = false,
    String? error,
    bool clearError = false,
    List<MemorizationReviewRecord>? history,
  }) => QuranMemorizationState(
    status: status ?? this.status,
    plans: plans ?? this.plans,
    items: items ?? this.items,
    activeSession: clearActiveSession
        ? null
        : (activeSession ?? this.activeSession),
    error: clearError ? null : (error ?? this.error),
    history: history ?? this.history,
  );

  @override
  List<Object?> get props => [
    status,
    plans,
    items,
    activeSession,
    error,
    history,
  ];
}
