import '../../data/models/hifz_planning_models.dart';
import '../../data/models/memorization_analytics_models.dart';
import '../../data/models/memorization_item.dart';
import '../../data/models/memorization_plan.dart';
import '../../data/models/memorization_status.dart';
import '../../data/models/murajaah_models.dart';
import 'adaptive_murajaah_engine.dart';

/// Pure, deterministic domain service responsible for synthesizing Q8 (memorization plans),
/// Q9 (adaptive Muraja'ah), and Q10 (analytics and pacing) into a unified daily journey.
///
/// Strictly decoupled from Flutter widgets and BuildContext.
class HifzPlanningEngine {
  const HifzPlanningEngine({
    this.murajaahEngine = const AdaptiveMurajaahEngine(),
  });

  final AdaptiveMurajaahEngine murajaahEngine;

  /// Absolute maximum Ayahs recommended across all segments combined to prevent cognitive overload.
  static const int maxDailyJourneyAyahs = 30;

  /// Threshold of overdue Ayahs that triggers Gentle Recovery Mode.
  static const int recoveryOverdueThreshold = 15;

  /// Threshold of consecutive inactive days with pending reviews that triggers Gentle Recovery Mode.
  static const int recoveryInactivityDaysThreshold = 3;

  /// Minimum and maximum daily slice of overdue Ayahs during Recovery Mode.
  static const int recoveryDailySliceMax = 15;

  /// Maximum new Hifz allowed during Recovery Mode to protect retention while maintaining momentum.
  static const int recoveryMaxNewHifz = 2;

  /// Calculates a personalized, balanced daily journey ("وردك اليومي المقترح").
  DailyHifzJourney calculateDailyJourney({
    required Iterable<MemorizationItem> items,
    required List<MemorizationReviewRecord> history,
    MemorizationPlan? activePlan,
    DateTime? now,
    int? manualTargetOverride,
  }) {
    final current = now ?? DateTime.now();

    // 1. Identify due, overdue, urgent, and weak items
    final itemMap = {for (final item in items) item.globalAyah: item};
    final dueTodayCandidates = murajaahEngine.generateQueue(
      items: items,
      category: AdaptiveMurajaahCategory.dueToday,
      limit: 50,
      now: current,
      planStart: activePlan?.startGlobalAyah,
      planEnd: activePlan?.endGlobalAyah,
    );

    final overdueList = <int>[];
    final urgentList = <int>[];
    for (final item in items) {
      final state = murajaahEngine.calculateScheduleState(item, now: current);
      if (state == AdaptiveScheduleState.overdue ||
          state == AdaptiveScheduleState.urgent) {
        overdueList.add(item.globalAyah);
      }
      if (state == AdaptiveScheduleState.urgent) {
        urgentList.add(item.globalAyah);
      }
    }

    // 2. Check for Recovery Mode trigger
    final daysSinceLastReview = _calculateDaysSinceLastReview(history, current);
    final isRecoveryMode =
        overdueList.length >= recoveryOverdueThreshold ||
        (daysSinceLastReview != null &&
            daysSinceLastReview >= recoveryInactivityDaysThreshold &&
            overdueList.isNotEmpty);

    // Step 1: Calculate C_total using the approved formula
    final planAgeDays = activePlan != null
        ? current.difference(activePlan.createdAt).inDays
        : 0;

    var memorizedInPlan = 0;
    if (activePlan != null) {
      for (
        var g = activePlan.startGlobalAyah;
        g <= activePlan.endGlobalAyah;
        g++
      ) {
        final it = itemMap[g];
        if (it != null && it.status == MemorizationStatus.memorized) {
          memorizedInPlan++;
        }
      }
    }
    final actualPace = (planAgeDays >= 2 && planAgeDays > 0)
        ? (memorizedInPlan / planAgeDays)
        : 0.0;
    final baseDailyTarget = activePlan?.dailyTarget ?? 5;
    final wBase = dueTodayCandidates.length;

    final cTotal = calculateDailyCapacity(
      actualPace: actualPace,
      target: baseDailyTarget,
      reviewWorkloadBase: wBase,
      historyCount: history.length,
      planAgeDays: planAgeDays,
      dueReviewsCount: dueTodayCandidates.length,
    );

    // Step 2: Determine Workload Level (D1: exact approved thresholds)
    final workloadLevel = _determineWorkloadLevel(
      dueCount: dueTodayCandidates.length,
      urgentCount: urgentList.length,
      isRecovery: isRecoveryMode,
    );

    // Step 3: Determine Recommended New Hifz Target
    final recommendedNewTarget = _calculateRecommendedNewTarget(
      baseDailyTarget: baseDailyTarget,
      workloadLevel: workloadLevel,
      dueCount: dueTodayCandidates.length,
      urgentCount: urgentList.length,
      isRecoveryMode: isRecoveryMode,
    );

    final effectiveNewTarget = manualTargetOverride ?? recommendedNewTarget;

    // Step 4: Build Segment Queues with Strict Deduplication
    final allocatedDueQueue = <int>[];
    final allocatedWeakQueue = <int>[];
    final allocatedNewQueue = <int>[];
    final seenGlobalAyahs = <int>{};

    // Segment A: Due Muraja'ah
    final maxDueSlice = isRecoveryMode ? recoveryDailySliceMax : 20;
    for (final g in dueTodayCandidates) {
      if (allocatedDueQueue.length >= maxDueSlice) break;
      if (seenGlobalAyahs.add(g)) {
        allocatedDueQueue.add(g);
      }
    }

    // Segment B: Weak Consolidation (sourced from weak category, excluding already due)
    final weakCandidates = murajaahEngine.generateQueue(
      items: items,
      category: AdaptiveMurajaahCategory.weak,
      limit: 30,
      now: current,
    );
    final maxWeakSlice = isRecoveryMode ? 5 : 8;
    for (final g in weakCandidates) {
      if (allocatedWeakQueue.length >= maxWeakSlice) break;
      if (seenGlobalAyahs.add(g)) {
        allocatedWeakQueue.add(g);
      }
    }

    // Segment C: New Hifz (sourced from active plan un-memorized sequence)
    final hasUnmemorizedInPlan =
        activePlan != null && activePlan.isActive && !activePlan.isCompleted;
    if (hasUnmemorizedInPlan) {
      final unmemorizedPlanAyahs = <int>[];
      for (
        var g = activePlan.startGlobalAyah;
        g <= activePlan.endGlobalAyah;
        g++
      ) {
        final it = itemMap[g];
        if (it == null || it.status != MemorizationStatus.memorized) {
          unmemorizedPlanAyahs.add(g);
        }
      }

      for (final g in unmemorizedPlanAyahs) {
        if (allocatedNewQueue.length >= effectiveNewTarget) break;
        // Strict deduplication: genuine new Hifz cannot be currently in due or weak queue
        if (seenGlobalAyahs.add(g)) {
          allocatedNewQueue.add(g);
        }
      }
    }

    // Step 5: Apply C_total capacity constraint
    _boundTotalCapacity(
      allocatedDueQueue: allocatedDueQueue,
      allocatedWeakQueue: allocatedWeakQueue,
      allocatedNewQueue: allocatedNewQueue,
      maxLimit: cTotal,
      preserveNewHifz: hasUnmemorizedInPlan && !isRecoveryMode,
    );

    // Step 6: Apply final global humane safety cap (Total <= 30)
    _boundTotalCapacity(
      allocatedDueQueue: allocatedDueQueue,
      allocatedWeakQueue: allocatedWeakQueue,
      allocatedNewQueue: allocatedNewQueue,
      maxLimit: maxDailyJourneyAyahs,
      preserveNewHifz: hasUnmemorizedInPlan && !isRecoveryMode,
    );

    // Step 7: Re-check final total and deduplication
    final finalTotal =
        allocatedDueQueue.length +
        allocatedWeakQueue.length +
        allocatedNewQueue.length;
    assert(finalTotal <= maxDailyJourneyAyahs);

    // Step 8: Formulate Segments
    final segments = <HifzJourneySegment>[
      HifzJourneySegment(
        type: HifzJourneySegmentType.dueMurajaah,
        queue: allocatedDueQueue,
      ),
      HifzJourneySegment(
        type: HifzJourneySegmentType.weakConsolidation,
        queue: allocatedWeakQueue,
      ),
      HifzJourneySegment(
        type: HifzJourneySegmentType.newHifz,
        queue: allocatedNewQueue,
      ),
    ];

    // 8. Generate Dignified Rationale Message
    final rationaleMessage = _generateRationaleMessage(
      isRecoveryMode: isRecoveryMode,
      workloadLevel: workloadLevel,
      overdueCount: overdueList.length,
      dueCount: allocatedDueQueue.length,
      weakCount: allocatedWeakQueue.length,
      newCount: allocatedNewQueue.length,
      activePlan: activePlan,
    );

    return DailyHifzJourney(
      segments: segments,
      dueMurajaahQueue: allocatedDueQueue,
      weakAyahsQueue: allocatedWeakQueue,
      newHifzQueue: allocatedNewQueue,
      recommendedNewHifzTarget: recommendedNewTarget,
      effectiveNewHifzTarget: manualTargetOverride,
      workloadLevel: workloadLevel,
      isRecoveryMode: isRecoveryMode,
      recoveryBacklogCount: overdueList.length,
      rationaleMessage: rationaleMessage,
      evaluatedAt: current,
      plan: activePlan,
    );
  }

  /// Calculates the approved daily capacity model:
  /// C_total = clamp(round(0.7 * P_actual + 0.3 * T_target) + W_base, 5, 50)
  ///
  /// Fallback when data is insufficient (fewer than 5 review records OR fewer than 2 plan days):
  /// C_total = dailyTarget + dueReviewsCount
  int calculateDailyCapacity({
    required double actualPace,
    required int target,
    required int reviewWorkloadBase,
    required int historyCount,
    required int planAgeDays,
    required int dueReviewsCount,
  }) {
    if (historyCount < 5 || planAgeDays < 2) {
      return target + dueReviewsCount;
    }
    final weighted = 0.7 * actualPace + 0.3 * target;
    return (weighted.round() + reviewWorkloadBase).clamp(5, 50);
  }

  /// Calculates the recommended new Hifz target based on workload and recovery state.
  int _calculateRecommendedNewTarget({
    required int baseDailyTarget,
    required WorkloadLevel workloadLevel,
    required int dueCount,
    required int urgentCount,
    required bool isRecoveryMode,
  }) {
    if (isRecoveryMode) {
      return (baseDailyTarget >= 2) ? 2 : 1;
    }

    if (workloadLevel == WorkloadLevel.heavy ||
        dueCount > 30 ||
        urgentCount > 3) {
      return (baseDailyTarget * 0.4).floor().clamp(1, baseDailyTarget);
    }

    if (workloadLevel == WorkloadLevel.moderate || dueCount > 10) {
      return (baseDailyTarget * 0.7).floor().clamp(1, baseDailyTarget);
    }

    return baseDailyTarget.clamp(1, 100);
  }

  /// Determines workload level strictly according to approved thresholds (D1):
  /// - Light: <= 10 due reviews (urgentCount <= 3)
  /// - Moderate: 11..30 due reviews (urgentCount <= 3)
  /// - Heavy: > 30 due reviews OR urgentCount > 3
  WorkloadLevel _determineWorkloadLevel({
    required int dueCount,
    required int urgentCount,
    bool isRecovery = false,
  }) {
    if (isRecovery || dueCount > 30 || urgentCount > 3) {
      return WorkloadLevel.heavy;
    }
    if (dueCount > 10) {
      return WorkloadLevel.moderate;
    }
    return WorkloadLevel.light;
  }

  int? _calculateDaysSinceLastReview(
    List<MemorizationReviewRecord> history,
    DateTime now,
  ) {
    if (history.isEmpty) return null;
    DateTime? latest;
    for (final record in history) {
      if (latest == null || record.reviewedAt.isAfter(latest)) {
        latest = record.reviewedAt;
      }
    }
    if (latest == null) return null;
    final diff = now.difference(latest).inDays;
    return diff < 0 ? 0 : diff;
  }

  void _boundTotalCapacity({
    required List<int> allocatedDueQueue,
    required List<int> allocatedWeakQueue,
    required List<int> allocatedNewQueue,
    required int maxLimit,
    bool preserveNewHifz = false,
  }) {
    var total =
        allocatedDueQueue.length +
        allocatedWeakQueue.length +
        allocatedNewQueue.length;
    if (total <= maxLimit) return;

    // Pruning strategy:
    // 1. Trim due queue down to at most 18
    while (total > maxLimit && allocatedDueQueue.length > 18) {
      allocatedDueQueue.removeLast();
      total--;
    }

    // 2. Trim weak queue down to at most 4
    while (total > maxLimit && allocatedWeakQueue.length > 4) {
      allocatedWeakQueue.removeLast();
      total--;
    }

    // 3. Trim due queue further down to at most 12
    while (total > maxLimit && allocatedDueQueue.length > 12) {
      allocatedDueQueue.removeLast();
      total--;
    }

    // 4. Finally trim new queue to at least 1 (if preserveNewHifz is true)
    final minNew = preserveNewHifz ? 1 : 0;
    while (total > maxLimit && allocatedNewQueue.length > minNew) {
      allocatedNewQueue.removeLast();
      total--;
    }

    // 5. If still exceeding limit, trim due queue further down to 1
    while (total > maxLimit && allocatedDueQueue.length > 1) {
      allocatedDueQueue.removeLast();
      total--;
    }

    // 6. If still exceeding limit, trim weak queue down to 0
    while (total > maxLimit && allocatedWeakQueue.isNotEmpty) {
      allocatedWeakQueue.removeLast();
      total--;
    }

    // 7. If still exceeding limit, trim due queue to 0
    while (total > maxLimit && allocatedDueQueue.isNotEmpty) {
      allocatedDueQueue.removeLast();
      total--;
    }
  }

  String _generateRationaleMessage({
    required bool isRecoveryMode,
    required WorkloadLevel workloadLevel,
    required int overdueCount,
    required int dueCount,
    required int weakCount,
    required int newCount,
    required MemorizationPlan? activePlan,
  }) {
    if (isRecoveryMode) {
      return 'وضع التعويض الهادئ: قسّمنا المراجعات المتأخرة ($overdueCount آية) إلى دفعات يسيرة، مع حفظ $newCount ${newCount == 1 ? 'آية' : 'آيتين'} فقط للحفاظ على استمرارية الورد دون إرهاق.';
    }

    switch (workloadLevel) {
      case WorkloadLevel.heavy:
        return 'أولوية التثبيت: جدول اليوم يركّز على المراجعة المستحقة لضمان ثبات المحفوظ، مع تخفيف الحفظ الجديد إلى $newCount آيات.';
      case WorkloadLevel.moderate:
        return 'ورد متوازن: موازنة معتدلة بين مراجعة $dueCount آية وتثبيت المواضع الصعبة، مع إنجاز $newCount آيات من حفظك الجديد.';
      case WorkloadLevel.light:
        if (activePlan != null) {
          return 'محفوظك في أمان ومثبّت: يمكنك اليوم إنجاز ورد حفظك الجديد كاملاً ($newCount آيات) بكل طمأنينة.';
        }
        return 'ورد هادئ: لا توجد مراجعات عاجلة اليوم، يمكنك المراجعة الحرة أو إعداد خطة حفظ جديدة.';
    }
  }

  /// Evaluates whether the user's active plan would benefit from a recommended target adaptation.
  ///
  /// Requires at least 7 calendar days of history or activity to prevent hasty suggestions.
  PlanAdaptationSuggestion? calculatePlanAdaptationSuggestion({
    required MemorizationPlan plan,
    required Iterable<MemorizationItem> items,
    required List<MemorizationReviewRecord> history,
    DateTime? now,
  }) {
    if (!plan.isActive || plan.isCompleted) return null;

    final current = now ?? DateTime.now();
    final planAgeDays = current.difference(plan.createdAt).inDays;
    if (planAgeDays < 7) return null;

    // Filter reviews within the plan's scope
    final planReviews = history.where((r) {
      return r.globalAyah >= plan.startGlobalAyah &&
          r.globalAyah <= plan.endGlobalAyah;
    }).toList();

    if (planReviews.length < 5) return null;

    // Calculate unique active days in the last 14 days
    final activeDaysSet = <String>{};
    final recentWindowCutoff = current.subtract(const Duration(days: 14));
    final recentPlanReviews = planReviews
        .where((r) => r.reviewedAt.isAfter(recentWindowCutoff))
        .toList();

    for (final r in recentPlanReviews) {
      final dateKey =
          '${r.reviewedAt.year}-${r.reviewedAt.month}-${r.reviewedAt.day}';
      activeDaysSet.add(dateKey);
    }

    if (activeDaysSet.length < 5) return null;

    // Count genuinely memorized Ayahs in the plan
    var memorizedInPlan = 0;
    for (var g = plan.startGlobalAyah; g <= plan.endGlobalAyah; g++) {
      final it = items.firstWhere(
        (item) => item.globalAyah == g,
        orElse: () => MemorizationItem(
          globalAyah: g,
          status: MemorizationStatus.notStarted,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      if (it.status == MemorizationStatus.memorized) {
        memorizedInPlan++;
      }
    }

    // Effective pace calculation: memorized over active days
    final sustainedPace = memorizedInPlan / planAgeDays.clamp(1, 365);
    final roundedPace = sustainedPace.round().clamp(1, 50);

    // Only suggest adaptation if pace diverges significantly from dailyTarget
    // Case 1: Target is too ambitious (sustained pace <= 55% of target and pace differs by >= 2)
    if (sustainedPace <= (plan.dailyTarget * 0.55) &&
        (plan.dailyTarget - roundedPace) >= 2) {
      return PlanAdaptationSuggestion(
        planId: plan.id,
        planTitle: plan.title,
        currentTarget: plan.dailyTarget,
        recommendedTarget: roundedPace,
        sustainedPace: sustainedPace,
        reason:
            'لوحظ أن وتيرة إنجازك الفعلية هي حوالي $roundedPace آيات يومياً. تخفيف الورد يضمن المداومة دون انقطاع، وأحب الأعمال إلى الله أدومها وإن قل.',
        actionText: 'تعديل الورد إلى $roundedPace آيات يومياً',
      );
    }

    // Case 2: User is consistently moving much faster (sustained pace >= 1.6x target and diff >= 2)
    if (sustainedPace >= (plan.dailyTarget * 1.6) &&
        (roundedPace - plan.dailyTarget) >= 2) {
      return PlanAdaptationSuggestion(
        planId: plan.id,
        planTitle: plan.title,
        currentTarget: plan.dailyTarget,
        recommendedTarget: roundedPace,
        sustainedPace: sustainedPace,
        reason:
            'ما شاء الله، وتيرة حفظك الفعلية أعلى من الورد المحدد وتصل إلى $roundedPace آيات يومياً. يمكنك رفع الورد لاختصار مدة الختم.',
        actionText: 'زيادة الورد إلى $roundedPace آيات يومياً',
      );
    }

    return null;
  }

  /// Calculates dual completion forecasts (target-based and realistic pace-based).
  CompletionForecast estimateRealisticCompletion({
    required MemorizationPlan plan,
    required Iterable<MemorizationItem> items,
    required List<MemorizationReviewRecord> history,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();

    // Count remaining non-memorized Ayahs
    var remaining = 0;
    for (var g = plan.startGlobalAyah; g <= plan.endGlobalAyah; g++) {
      final it = items.firstWhere(
        (item) => item.globalAyah == g,
        orElse: () => MemorizationItem(
          globalAyah: g,
          status: MemorizationStatus.notStarted,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      if (it.status != MemorizationStatus.memorized) {
        remaining++;
      }
    }

    if (remaining == 0) {
      return const CompletionForecast(
        targetBasedDays: 0,
        targetBasedDescription: 'تم إنجاز الخطة بالكامل بحمد الله',
        paceBasedDays: 0,
        paceBasedDescription: 'مكتملة',
        hasSufficientData: true,
      );
    }

    // Target-based estimation
    final targetDays = (remaining / plan.dailyTarget).ceil();
    final targetDescription = _formatDurationToCalmArabic(targetDays);

    // Pace-based estimation
    final planAgeDays = current.difference(plan.createdAt).inDays.clamp(1, 365);
    final memorizedInPlan = plan.totalAyahs - remaining;

    final hasSufficientData = planAgeDays >= 7 && memorizedInPlan > 0;
    int? paceDays;
    String? paceDescription;
    String? paceComparison;

    if (hasSufficientData) {
      final pace = memorizedInPlan / planAgeDays;
      if (pace > 0) {
        paceDays = (remaining / pace).ceil();
        paceDescription = _formatDurationToCalmArabic(paceDays);

        if ((paceDays - targetDays).abs() <= 5) {
          paceComparison = 'وتيرتك متطابقة مع الخطة الزمنية';
        } else if (paceDays < targetDays) {
          paceComparison = 'أنت تتقدم أسرع من الجدول الزمني المستهدف';
        } else {
          paceComparison =
              'الوتيرة الواقعية تتطلب وقتاً أطول قليلاً لضمان التثبيت';
        }
      }
    }

    return CompletionForecast(
      targetBasedDays: targetDays,
      targetBasedDescription: targetDescription,
      paceBasedDays: paceDays,
      paceBasedDescription: paceDescription,
      hasSufficientData: hasSufficientData,
      paceComparisonMessage: paceComparison,
    );
  }

  /// Converts a day count into human-friendly, dignified Arabic approximation.
  String _formatDurationToCalmArabic(int days) {
    if (days <= 0) return 'اليوم بإذن الله';
    if (days == 1) return 'يوم واحد تقريباً';
    if (days == 2) return 'يومان تقريباً';
    if (days <= 10) return 'حوالي $days أيام';
    if (days <= 14) return 'حوالي أسبوعين';
    if (days <= 21) return 'حوالي 3 أسابيع';
    if (days <= 35) return 'حوالي شهر';
    if (days <= 50) return 'حوالي شهر ونصف';
    if (days <= 70) return 'حوالي شهرين';
    if (days <= 100) return 'حوالي 3 أشهر';
    if (days <= 130) return 'حوالي 4 أشهر';
    if (days <= 160) return 'حوالي 5 أشهر';
    if (days <= 200) return 'حوالي نصف عام';
    if (days <= 290) return 'حوالي 8 إلى 9 أشهر';
    if (days <= 365) return 'حوالي عام';
    final years = (days / 365).toStringAsFixed(1);
    return 'حوالي $years سنة';
  }
}
