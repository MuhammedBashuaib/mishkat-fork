import '../../data/models/memorization_analytics_models.dart';
import '../../data/models/memorization_item.dart';
import '../../data/models/memorization_plan.dart';
import '../../data/models/memorization_status.dart';
import '../../data/models/murajaah_models.dart';
import '../../data/models/quran_models.dart';
import 'adaptive_murajaah_engine.dart';

/// Pure, deterministic domain service responsible for computing all Quran
/// memorization and Muraja'ah retention analytics.
///
/// Completely decoupled from Flutter UI, BuildContext, and persistence.
class MemorizationAnalyticsEngine {
  const MemorizationAnalyticsEngine({
    this.adaptiveEngine = const AdaptiveMurajaahEngine(),
  });

  final AdaptiveMurajaahEngine adaptiveEngine;

  /// Total canonical Ayahs in the Holy Quran.
  static const int canonicalTotalAyahs = 6236;

  /// Minimum historical reviews needed before presenting statistical ratios.
  static const int minReviewsForRatios = 5;

  /// Computes overall Quran memorization mastery totals and coverage.
  OverallMemorizationAnalytics calculateOverall(
    Map<int, MemorizationItem> items, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    var memorized = 0;
    var learning = 0;
    var needsRevision = 0;
    var dueToday = 0;
    var overdue = 0;
    var weak = 0;

    for (final item in items.values) {
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

      if (item.status != MemorizationStatus.notStarted) {
        final state = adaptiveEngine.calculateScheduleState(item, now: current);
        if (state == AdaptiveScheduleState.due ||
            state == AdaptiveScheduleState.overdue ||
            state == AdaptiveScheduleState.urgent) {
          dueToday++;
        }
        if (state == AdaptiveScheduleState.overdue ||
            state == AdaptiveScheduleState.urgent) {
          overdue++;
        }
        if (item.status == MemorizationStatus.needsRevision ||
            item.mistakeCount >= 2 ||
            state == AdaptiveScheduleState.weak ||
            state == AdaptiveScheduleState.urgent) {
          weak++;
        }
      }
    }

    final notStarted =
        (canonicalTotalAyahs - (memorized + learning + needsRevision)).clamp(
          0,
          canonicalTotalAyahs,
        );
    final coveragePercentage = (memorized / canonicalTotalAyahs).clamp(
      0.0,
      1.0,
    );

    return OverallMemorizationAnalytics(
      totalAyahs: canonicalTotalAyahs,
      memorized: memorized,
      learning: learning,
      needsRevision: needsRevision,
      notStarted: notStarted,
      coveragePercentage: coveragePercentage,
      dueToday: dueToday,
      overdue: overdue,
      weak: weak,
    );
  }

  /// Evaluates review retention and performance from historical logs.
  ReviewRetentionAnalytics calculateRetention(
    List<MemorizationReviewRecord> history, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final totalReviews = history.length;
    final hasSufficientData = totalReviews >= minReviewsForRatios;

    var easyCount = 0;
    var goodCount = 0;
    var difficultCount = 0;
    var failedCount = 0;
    var reviewsToday = 0;
    var reviewsThisWeek = 0;
    var reviewsThisMonth = 0;

    final weekCutoff = current.subtract(const Duration(days: 7));
    final monthCutoff = current.subtract(const Duration(days: 30));
    final activeDays = <String>{};

    for (final record in history) {
      switch (record.outcome) {
        case ReviewOutcome.easy:
          easyCount++;
        case ReviewOutcome.good:
          goodCount++;
        case ReviewOutcome.difficult:
          difficultCount++;
        case ReviewOutcome.failed:
          failedCount++;
      }

      final rDate = record.reviewedAt;
      if (rDate.year == current.year &&
          rDate.month == current.month &&
          rDate.day == current.day) {
        reviewsToday++;
      }
      if (rDate.isAfter(weekCutoff)) {
        reviewsThisWeek++;
      }
      if (rDate.isAfter(monthCutoff)) {
        reviewsThisMonth++;
      }

      final dayKey =
          '${rDate.year}-${rDate.month.toString().padLeft(2, '0')}-${rDate.day.toString().padLeft(2, '0')}';
      activeDays.add(dayKey);
    }

    final successRate = hasSufficientData
        ? ((easyCount + goodCount) / totalReviews).clamp(0.0, 1.0)
        : null;
    final difficultRate = hasSufficientData
        ? (difficultCount / totalReviews).clamp(0.0, 1.0)
        : null;
    final failureRate = hasSufficientData
        ? (failedCount / totalReviews).clamp(0.0, 1.0)
        : null;
    final averageReviewsPerActiveDay = activeDays.isEmpty
        ? 0.0
        : (totalReviews / activeDays.length);

    return ReviewRetentionAnalytics(
      totalReviews: totalReviews,
      easyCount: easyCount,
      goodCount: goodCount,
      difficultCount: difficultCount,
      failedCount: failedCount,
      successRate: successRate,
      difficultRate: difficultRate,
      failureRate: failureRate,
      reviewsToday: reviewsToday,
      reviewsThisWeek: reviewsThisWeek,
      reviewsThisMonth: reviewsThisMonth,
      averageReviewsPerActiveDay: averageReviewsPerActiveDay,
      hasSufficientData: hasSufficientData,
    );
  }

  /// Calculates review velocity and trend direction over 7-day and 30-day windows.
  MurajaahTrendAnalytics calculateTrend(
    List<MemorizationReviewRecord> history, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final w1Cutoff = current.subtract(const Duration(days: 7));
    final w2Cutoff = current.subtract(const Duration(days: 14));
    final m1Cutoff = current.subtract(const Duration(days: 30));
    final m2Cutoff = current.subtract(const Duration(days: 60));

    var reviewsLast7Days = 0;
    var reviewsPrevious7Days = 0;
    var reviewsLast30Days = 0;
    var reviewsPrevious30Days = 0;

    for (final record in history) {
      final rDate = record.reviewedAt;
      if (rDate.isAfter(w1Cutoff) && !rDate.isAfter(current)) {
        reviewsLast7Days++;
      } else if (rDate.isAfter(w2Cutoff) && !rDate.isAfter(w1Cutoff)) {
        reviewsPrevious7Days++;
      }

      if (rDate.isAfter(m1Cutoff) && !rDate.isAfter(current)) {
        reviewsLast30Days++;
      } else if (rDate.isAfter(m2Cutoff) && !rDate.isAfter(m1Cutoff)) {
        reviewsPrevious30Days++;
      }
    }

    final total7DayPeriod = reviewsLast7Days + reviewsPrevious7Days;
    if (total7DayPeriod < minReviewsForRatios) {
      return MurajaahTrendAnalytics(
        direction: TrendDirection.insufficientData,
        reviewsLast7Days: reviewsLast7Days,
        reviewsPrevious7Days: reviewsPrevious7Days,
        reviewsLast30Days: reviewsLast30Days,
        reviewsPrevious30Days: reviewsPrevious30Days,
        description: 'لا توجد بيانات مراجعة كافية لعرض الاتجاه بعد',
      );
    }

    final diff = reviewsLast7Days - reviewsPrevious7Days;
    final TrendDirection direction;
    final String description;

    if (diff >= 3 ||
        (reviewsPrevious7Days > 0 &&
            diff / reviewsPrevious7Days >= 0.25 &&
            diff >= 2)) {
      direction = TrendDirection.increasing;
      description = 'نشاط المراجعة في ازدياد مبارك مقارنة بالأسبوع الماضي';
    } else if (diff <= -3 ||
        (reviewsPrevious7Days > 0 &&
            diff / reviewsPrevious7Days <= -0.25 &&
            diff <= -2)) {
      direction = TrendDirection.decreasing;
      description = 'نشاط المراجعة أقل من الأسبوع الماضي';
    } else {
      direction = TrendDirection.stable;
      description = 'نشاط المراجعة مستقر ومتوازن';
    }

    return MurajaahTrendAnalytics(
      direction: direction,
      reviewsLast7Days: reviewsLast7Days,
      reviewsPrevious7Days: reviewsPrevious7Days,
      reviewsLast30Days: reviewsLast30Days,
      reviewsPrevious30Days: reviewsPrevious30Days,
      description: description,
    );
  }

  /// Calculates upcoming review commitments based on items' [nextReviewAt] scheduling.
  ReviewWorkloadForecast calculateWorkloadForecast(
    Map<int, MemorizationItem> items, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final endOfToday = DateTime(
      current.year,
      current.month,
      current.day,
      23,
      59,
      59,
    );
    final startOfTomorrow = DateTime(
      current.year,
      current.month,
      current.day + 1,
    );
    final endOfTomorrow = DateTime(
      current.year,
      current.month,
      current.day + 1,
      23,
      59,
      59,
    );
    final endOf7Days = DateTime(
      current.year,
      current.month,
      current.day + 7,
      23,
      59,
      59,
    );

    var dueTodayCount = 0;
    var dueTomorrowCount = 0;
    var dueNext7DaysCount = 0;

    for (final item in items.values) {
      if (item.status == MemorizationStatus.notStarted) continue;

      if (item.nextReviewAt != null) {
        final nr = item.nextReviewAt!;
        if (!nr.isAfter(endOfToday)) {
          dueTodayCount++;
        } else if (!nr.isBefore(startOfTomorrow) &&
            !nr.isAfter(endOfTomorrow)) {
          dueTomorrowCount++;
        }

        if (nr.isAfter(endOfToday) && !nr.isAfter(endOf7Days)) {
          dueNext7DaysCount++;
        }
      } else {
        // Fallback for items without explicit nextReviewAt
        final state = adaptiveEngine.calculateScheduleState(item, now: current);
        if (state == AdaptiveScheduleState.due ||
            state == AdaptiveScheduleState.overdue ||
            state == AdaptiveScheduleState.urgent) {
          dueTodayCount++;
        }
      }
    }

    final totalNear = dueTodayCount + dueTomorrowCount;
    final WorkloadLevel level;
    if (totalNear <= 10) {
      level = WorkloadLevel.light;
    } else if (totalNear <= 30) {
      level = WorkloadLevel.moderate;
    } else {
      level = WorkloadLevel.heavy;
    }

    return ReviewWorkloadForecast(
      dueTodayCount: dueTodayCount,
      dueTomorrowCount: dueTomorrowCount,
      dueNext7DaysCount: dueNext7DaysCount,
      workloadLevel: level,
    );
  }

  /// Computes progress and pacing intelligence for an active plan.
  PlanProgressAnalytics calculatePlanAnalytics(
    MemorizationPlan plan,
    Map<int, MemorizationItem> items, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
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
    final estimatedDays = (remaining / plan.dailyTarget).ceil();

    final daysElapsed = (current.difference(plan.createdAt).inHours / 24.0)
        .clamp(0.0, 3650.0);

    final PlanPaceStatus paceStatus;
    final String paceMessage;
    final double currentPace;

    if (daysElapsed < 2.0 || memorized == 0) {
      currentPace = daysElapsed > 0.1 ? (memorized / daysElapsed) : 0.0;
      paceStatus = PlanPaceStatus.insufficientData;
      paceMessage = 'الخطة في بدايتها، سيظهر تقييم المعدل قريباً إن شاء الله';
    } else {
      currentPace = memorized / daysElapsed;
      if (currentPace >= plan.dailyTarget * 1.1) {
        paceStatus = PlanPaceStatus.ahead;
        paceMessage = 'أنت متقدم على المعدل المخطط له بفضل الله';
      } else if (currentPace >= plan.dailyTarget * 0.8) {
        paceStatus = PlanPaceStatus.onTrack;
        paceMessage = 'أنت تسير وفق المعدل المحدد بنجاح';
      } else {
        paceStatus = PlanPaceStatus.needsAttention;
        paceMessage = 'تحتاج إلى زيادة بسيطة في وتيرة الحفظ للوصول للهدف';
      }
    }

    return PlanProgressAnalytics(
      plan: plan,
      totalAyahs: total,
      memorizedCount: memorized,
      learningCount: learning,
      needsRevisionCount: needsRevision,
      remainingCount: remaining,
      completionPercentage: percentage,
      dailyTarget: plan.dailyTarget,
      estimatedDaysRemaining: estimatedDays,
      currentPace: currentPace,
      paceStatus: paceStatus,
      paceMessage: paceMessage,
    );
  }

  /// Identifies and ranks weak Ayahs requiring attention or consolidation.
  List<WeakAyahInsight> findWeakAyahs(
    Map<int, MemorizationItem> items,
    QuranData quranData, {
    DateTime? now,
    int limit = 10,
  }) {
    final current = now ?? DateTime.now();
    final candidates =
        <({MemorizationItem item, MurajaahPriorityScore score})>[];

    for (final item in items.values) {
      if (item.status == MemorizationStatus.notStarted) continue;

      final schedule = adaptiveEngine.calculateScheduleState(
        item,
        now: current,
      );
      final isWeakCandidate =
          item.status == MemorizationStatus.needsRevision ||
          item.mistakeCount >= 2 ||
          schedule == AdaptiveScheduleState.weak ||
          schedule == AdaptiveScheduleState.urgent ||
          item.lastOutcome == ReviewOutcome.difficult ||
          item.lastOutcome == ReviewOutcome.failed;

      if (isWeakCandidate) {
        final score = adaptiveEngine.calculatePriority(item, now: current);
        candidates.add((item: item, score: score));
      }
    }

    // Sort by priority totalScore descending; tie-break by globalAyah ascending
    candidates.sort((a, b) {
      final cmp = b.score.totalScore.compareTo(a.score.totalScore);
      if (cmp != 0) return cmp;
      return a.item.globalAyah.compareTo(b.item.globalAyah);
    });

    final selected = candidates.take(limit);
    final insights = <WeakAyahInsight>[];

    for (final entry in selected) {
      final global = entry.item.globalAyah;
      final point = quranData.pointForGlobal(global);
      final chapter = quranData.chapter(point.surah);

      insights.add(
        WeakAyahInsight(
          globalAyah: global,
          surahNumber: point.surah,
          surahName: chapter.name,
          ayahNumber: point.ayah,
          mistakeCount: entry.item.mistakeCount,
          scheduleState: entry.score.scheduleState,
          lastOutcome: entry.item.lastOutcome,
          nextReviewAt: entry.item.nextReviewAt,
          priorityScore: entry.score.totalScore,
        ),
      );
    }

    return insights;
  }

  /// Computes mastery coverage per Surah ($1 \dots 114$).
  List<SurahMemorizationAnalytics> calculateSurahAnalytics(
    Map<int, MemorizationItem> items,
    QuranData quranData, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final result = <SurahMemorizationAnalytics>[];

    for (final chapter in quranData.chapters) {
      final total = chapter.ayahs.length;
      final start = chapter.globalStart;
      final end = start + total - 1;

      var memorized = 0;
      var learning = 0;
      var needsRevision = 0;
      var weak = 0;

      for (var g = start; g <= end; g++) {
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

          if (item.status != MemorizationStatus.notStarted) {
            final s = adaptiveEngine.calculateScheduleState(item, now: current);
            if (item.status == MemorizationStatus.needsRevision ||
                item.mistakeCount >= 2 ||
                s == AdaptiveScheduleState.weak ||
                s == AdaptiveScheduleState.urgent) {
              weak++;
            }
          }
        }
      }

      final percentage = total == 0 ? 0.0 : (memorized / total).clamp(0.0, 1.0);

      result.add(
        SurahMemorizationAnalytics(
          surahNumber: chapter.number,
          name: chapter.name,
          totalAyahs: total,
          memorizedCount: memorized,
          learningCount: learning,
          needsRevisionCount: needsRevision,
          weakCount: weak,
          completionPercentage: percentage,
        ),
      );
    }

    return result;
  }

  /// Computes mastery coverage per canonical Juz ($1 \dots 30$).
  List<JuzMemorizationAnalytics> calculateJuzAnalytics(
    Map<int, MemorizationItem> items,
    QuranData quranData, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final result = <JuzMemorizationAnalytics>[];
    final juzList = quranData.juz;

    for (var i = 0; i < juzList.length; i++) {
      final juz = juzList[i];
      final start = quranData.globalFor(juz.surah, juz.ayah);
      final end = (i + 1 < juzList.length)
          ? quranData.globalFor(juzList[i + 1].surah, juzList[i + 1].ayah) - 1
          : canonicalTotalAyahs;
      final total = end - start + 1;

      var memorized = 0;
      var learning = 0;
      var needsRevision = 0;
      var weak = 0;

      for (var g = start; g <= end; g++) {
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

          if (item.status != MemorizationStatus.notStarted) {
            final s = adaptiveEngine.calculateScheduleState(item, now: current);
            if (item.status == MemorizationStatus.needsRevision ||
                item.mistakeCount >= 2 ||
                s == AdaptiveScheduleState.weak ||
                s == AdaptiveScheduleState.urgent) {
              weak++;
            }
          }
        }
      }

      final percentage = total == 0 ? 0.0 : (memorized / total).clamp(0.0, 1.0);

      result.add(
        JuzMemorizationAnalytics(
          juzNumber: juz.number,
          startGlobalAyah: start,
          endGlobalAyah: end,
          totalAyahs: total,
          memorizedCount: memorized,
          learningCount: learning,
          needsRevisionCount: needsRevision,
          weakCount: weak,
          completionPercentage: percentage,
        ),
      );
    }

    return result;
  }

  /// Computes comprehensive aggregated analytics snapshot on demand.
  ComprehensiveMemorizationAnalytics compute({
    required Map<int, MemorizationItem> items,
    required List<MemorizationReviewRecord> history,
    required List<MemorizationPlan> plans,
    required QuranData quranData,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();

    final overall = calculateOverall(items, now: current);
    final retention = calculateRetention(history, now: current);
    final trend = calculateTrend(history, now: current);
    final forecast = calculateWorkloadForecast(items, now: current);

    MemorizationPlan? activePlan;
    for (final p in plans) {
      if (p.isActive && !p.isCompleted) {
        activePlan = p;
        break;
      }
    }

    final planAnalytics = activePlan != null
        ? calculatePlanAnalytics(activePlan, items, now: current)
        : null;

    final weakAyahs = findWeakAyahs(items, quranData, now: current, limit: 8);
    final surahs = calculateSurahAnalytics(items, quranData, now: current);
    final juzs = calculateJuzAnalytics(items, quranData, now: current);

    return ComprehensiveMemorizationAnalytics(
      overall: overall,
      retention: retention,
      trend: trend,
      forecast: forecast,
      plan: planAnalytics,
      weakAyahs: weakAyahs,
      surahs: surahs,
      juzs: juzs,
      generatedAt: current,
    );
  }
}
