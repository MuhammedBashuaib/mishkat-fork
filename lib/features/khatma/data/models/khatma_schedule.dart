import 'dart:math' as math;

/// Whole-page portions shared by the plan builder and saved reading plans.
/// Duration plans put the extra pages in the first few portions, so every day
/// has at least one page and the last portion ends on the chosen day.
class KhatmaSchedule {
  const KhatmaSchedule._({
    required this.startPage,
    required this.durationDays,
    required this.minDailyPages,
    required this.maxDailyPages,
    required this.isBalanced,
  });

  factory KhatmaSchedule.fromDuration({
    required int startPage,
    required int durationDays,
  }) {
    RangeError.checkValueInInterval(startPage, 1, 604, 'startPage');
    final pages = 605 - startPage;
    RangeError.checkValueInInterval(durationDays, 1, pages, 'durationDays');
    return KhatmaSchedule._(
      startPage: startPage,
      durationDays: durationDays,
      minDailyPages: pages ~/ durationDays,
      maxDailyPages: (pages / durationDays).ceil(),
      isBalanced: true,
    );
  }

  factory KhatmaSchedule.fromDailyPages({
    required int startPage,
    required int dailyPages,
  }) {
    RangeError.checkValueInInterval(startPage, 1, 604, 'startPage');
    RangeError.checkValueInInterval(dailyPages, 1, 604, 'dailyPages');
    return KhatmaSchedule._(
      startPage: startPage,
      durationDays: ((605 - startPage) / dailyPages).ceil(),
      minDailyPages: dailyPages,
      maxDailyPages: dailyPages,
      isBalanced: false,
    );
  }

  final int startPage;
  final int durationDays;
  final int minDailyPages;
  final int maxDailyPages;
  final bool isBalanced;

  int get totalPages => 605 - startPage;

  DateTime targetDate(DateTime start) => DateTime(
    start.year,
    start.month,
    start.day + durationDays - 1,
    start.hour,
    start.minute,
    start.second,
    start.millisecond,
    start.microsecond,
  );

  int completedPortions(int progressPage) {
    final completed = (progressPage - startPage + 1).clamp(0, totalPages);
    if (!isBalanced) return completed ~/ maxDailyPages;
    final largerPortions = totalPages % durationDays;
    final largerPages = largerPortions * (minDailyPages + 1);
    if (completed < largerPages) return completed ~/ (minDailyPages + 1);
    return largerPortions + (completed - largerPages) ~/ minDailyPages;
  }

  int endPageAfter(int progressPage) {
    if (!isBalanced) return math.min(604, progressPage + maxDailyPages);
    final portion = (completedPortions(progressPage) + 1)
        .clamp(1, durationDays)
        .toInt();
    final completed =
        portion * minDailyPages + math.min(portion, totalPages % durationDays);
    return (startPage + completed - 1).toInt();
  }
}
