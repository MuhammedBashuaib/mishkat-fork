import '../../data/models/memorization_item.dart';
import '../../data/models/memorization_status.dart';
import '../../data/models/murajaah_models.dart';

/// Pure, deterministic domain service responsible for adaptive Muraja'ah scheduling,
/// spaced repetition interval computation, priority scoring, and queue generation.
///
/// Completely decoupled from Flutter UI and BuildContext.
class AdaptiveMurajaahEngine {
  const AdaptiveMurajaahEngine();

  /// Configurable Spaced Interval Progression Ladder (in days) indexed by consecutive successes.
  static const List<int> goodIntervalLadder = [3, 7, 14, 30, 60];
  static const List<int> easyIntervalLadder = [7, 14, 30, 60, 90];

  /// Computes the subsequent review interval and target due date for an Ayah based on the given outcome.
  ({int intervalDays, DateTime nextReviewAt, int consecutiveSuccesses})
  calculateNextInterval({
    required MemorizationItem item,
    required ReviewOutcome outcome,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();

    switch (outcome) {
      case ReviewOutcome.failed:
        // Immediate / same-day review required
        return (
          intervalDays: 0,
          nextReviewAt: current,
          consecutiveSuccesses: 0,
        );

      case ReviewOutcome.difficult:
        // Review next day
        return (
          intervalDays: 1,
          nextReviewAt: current.add(const Duration(days: 1)),
          consecutiveSuccesses: 0,
        );

      case ReviewOutcome.good:
        final ladderIndex = item.consecutiveSuccesses.clamp(
          0,
          goodIntervalLadder.length - 1,
        );
        final interval = goodIntervalLadder[ladderIndex];
        return (
          intervalDays: interval,
          nextReviewAt: current.add(Duration(days: interval)),
          consecutiveSuccesses: item.consecutiveSuccesses + 1,
        );

      case ReviewOutcome.easy:
        final ladderIndex = item.consecutiveSuccesses.clamp(
          0,
          easyIntervalLadder.length - 1,
        );
        final interval = easyIntervalLadder[ladderIndex];
        return (
          intervalDays: interval,
          nextReviewAt: current.add(Duration(days: interval)),
          consecutiveSuccesses: item.consecutiveSuccesses + 1,
        );
    }
  }

  /// Calculates the current [AdaptiveScheduleState] of an Ayah.
  AdaptiveScheduleState calculateScheduleState(
    MemorizationItem item, {
    DateTime? now,
  }) {
    if (item.status == MemorizationStatus.notStarted) {
      return AdaptiveScheduleState.notDue;
    }

    final current = now ?? DateTime.now();

    // Critical weakness / urgency
    if (item.status == MemorizationStatus.needsRevision) {
      if (item.mistakeCount >= 3 || item.lastOutcome == ReviewOutcome.failed) {
        return AdaptiveScheduleState.urgent;
      }
      return AdaptiveScheduleState.weak;
    }

    // Explicit nextReviewAt takes precedence
    if (item.nextReviewAt != null) {
      final dueDate = item.nextReviewAt!;
      final diff = current.difference(dueDate);

      // Overdue if due date was yesterday or earlier (>= 24 hours past dueDate)
      if (diff.inHours >= 24) {
        if (diff.inDays >= 7 || item.mistakeCount >= 2) {
          return AdaptiveScheduleState.urgent;
        }
        return AdaptiveScheduleState.overdue;
      }

      // Due today
      if (_isSameDayOrBefore(dueDate, current)) {
        return AdaptiveScheduleState.due;
      }

      return AdaptiveScheduleState.notDue;
    }

    // Fallback if nextReviewAt not yet populated (e.g. legacy Q8 items)
    if (item.lastReviewedAt == null) {
      return AdaptiveScheduleState.due;
    }

    final daysSinceReview = current.difference(item.lastReviewedAt!).inDays;
    if (daysSinceReview >= 7) {
      return AdaptiveScheduleState.overdue;
    } else if (daysSinceReview >= 3) {
      return AdaptiveScheduleState.due;
    }

    return AdaptiveScheduleState.notDue;
  }

  /// Calculates an explainable, deterministic priority score for an Ayah.
  /// Higher totalScore indicates greater urgency for review.
  MurajaahPriorityScore calculatePriority(
    MemorizationItem item, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final schedule = calculateScheduleState(item, now: current);

    var overdueWeight = 0.0;
    if (item.nextReviewAt != null && current.isAfter(item.nextReviewAt!)) {
      final days = current.difference(item.nextReviewAt!).inDays.clamp(0, 20);
      overdueWeight = days * 10.0;
    } else if (item.lastReviewedAt != null) {
      final days = current.difference(item.lastReviewedAt!).inDays.clamp(0, 20);
      if (days > 3) overdueWeight = (days - 3) * 5.0;
    }

    var weaknessWeight = 0.0;
    if (item.status == MemorizationStatus.needsRevision) {
      weaknessWeight = 35.0;
    } else if (schedule == AdaptiveScheduleState.weak) {
      weaknessWeight = 25.0;
    }

    final mistakeWeight = (item.mistakeCount.clamp(0, 10)) * 5.0;

    var recentFailureWeight = 0.0;
    if (item.lastOutcome == ReviewOutcome.failed) {
      recentFailureWeight = 30.0;
    } else if (item.lastOutcome == ReviewOutcome.difficult) {
      recentFailureWeight = 15.0;
    }

    var reviewGapWeight = 0.0;
    if (item.lastReviewedAt != null) {
      final gapDays = current
          .difference(item.lastReviewedAt!)
          .inDays
          .clamp(0, 30);
      reviewGapWeight = gapDays * 1.5;
    } else {
      reviewGapWeight = 20.0; // Never reviewed
    }

    // Damping factor for solid retention
    final damping = (item.consecutiveSuccesses.clamp(0, 5)) * 4.0;

    var total =
        overdueWeight +
        weaknessWeight +
        mistakeWeight +
        recentFailureWeight +
        reviewGapWeight -
        damping;

    if (schedule == AdaptiveScheduleState.urgent) {
      total += 50.0;
    }

    return MurajaahPriorityScore(
      globalAyah: item.globalAyah,
      totalScore: total.clamp(0.0, 9999.0),
      overdueWeight: overdueWeight,
      weaknessWeight: weaknessWeight,
      mistakeWeight: mistakeWeight,
      recentFailureWeight: recentFailureWeight,
      reviewGapWeight: reviewGapWeight,
      scheduleState: schedule,
    );
  }

  /// Generates a deterministic queue of canonical globalAyah indices according to category and priority.
  List<int> generateQueue({
    required Iterable<MemorizationItem> items,
    AdaptiveMurajaahCategory category = AdaptiveMurajaahCategory.all,
    int limit = 20,
    DateTime? now,
    int? planStart,
    int? planEnd,
  }) {
    final current = now ?? DateTime.now();

    // 1. Filter candidates
    final candidates = <MemorizationItem>[];
    for (final item in items) {
      if (item.status == MemorizationStatus.notStarted) continue;

      final state = calculateScheduleState(item, now: current);

      final matchesCategory = switch (category) {
        AdaptiveMurajaahCategory.dueToday =>
          state == AdaptiveScheduleState.due ||
              state == AdaptiveScheduleState.overdue ||
              state == AdaptiveScheduleState.urgent ||
              state == AdaptiveScheduleState.weak,
        AdaptiveMurajaahCategory.overdue =>
          state == AdaptiveScheduleState.overdue ||
              state == AdaptiveScheduleState.urgent,
        AdaptiveMurajaahCategory.weak =>
          item.status == MemorizationStatus.needsRevision ||
              item.mistakeCount > 0 ||
              state == AdaptiveScheduleState.weak ||
              state == AdaptiveScheduleState.urgent,
        AdaptiveMurajaahCategory.recentlyDifficult =>
          item.lastOutcome == ReviewOutcome.difficult ||
              item.lastOutcome == ReviewOutcome.failed,
        AdaptiveMurajaahCategory.mistakeBased => item.mistakeCount > 0,
        AdaptiveMurajaahCategory.all => true,
      };

      if (matchesCategory) {
        candidates.add(item);
      }
    }

    // 2. Score candidates
    final scored = candidates.map((item) {
      final score = calculatePriority(item, now: current);
      var bonus = 0.0;
      // Plan awareness boost: if Ayah is inside the active plan range, boost slightly
      if (planStart != null &&
          planEnd != null &&
          item.globalAyah >= planStart &&
          item.globalAyah <= planEnd) {
        bonus = 15.0;
      }
      return (item: item, totalScore: score.totalScore + bonus);
    }).toList();

    // 3. Sort deterministically: highest score first, stable tie-breaker: globalAyah asc
    scored.sort((a, b) {
      final scoreComp = b.totalScore.compareTo(a.totalScore);
      if (scoreComp != 0) return scoreComp;
      return a.item.globalAyah.compareTo(b.item.globalAyah);
    });

    // 4. Return top slice
    return scored.take(limit).map((s) => s.item.globalAyah).toList();
  }

  bool _isSameDayOrBefore(DateTime date, DateTime now) {
    if (date.year < now.year) return true;
    if (date.year > now.year) return false;
    if (date.month < now.month) return true;
    if (date.month > now.month) return false;
    return date.day <= now.day;
  }
}
