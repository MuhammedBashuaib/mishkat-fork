import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'khatma_schedule.dart';

enum KhatmaStatus { active, paused, completed }

enum KhatmaPlanningMode { duration, pages }

class KhatmaPlan extends Equatable {
  const KhatmaPlan({
    required this.id,
    required this.name,
    required this.durationDays,
    required this.dailyPages,
    required this.startDate,
    required this.startPage,
    required this.progressPage,
    required this.status,
    required this.createdAt,
    this.planningMode = KhatmaPlanningMode.duration,
    this.balancedSchedule = false,
    this.scheduleStartPage,
    this.scheduleStartDate,
    this.reminderTime,
    this.lastReadPage,
    this.currentWardEndPage,
    this.reminderPrayer,
    this.pausedAt,
    this.completedAt,
  });

  final String id;
  final String name;
  final int durationDays;
  final int dailyPages;
  final KhatmaPlanningMode planningMode;
  // Older plans keep their original fixed portions until explicitly rebalanced.
  final bool balancedSchedule;
  final int? scheduleStartPage;
  final DateTime? scheduleStartDate;
  final String? reminderTime;
  final DateTime startDate;
  final int startPage;
  final int progressPage;
  final int? lastReadPage;
  final int? currentWardEndPage;
  final KhatmaStatus status;
  final String? reminderPrayer;
  final DateTime createdAt;
  final DateTime? pausedAt;
  final DateTime? completedAt;

  KhatmaSchedule? get _balanced =>
      balancedSchedule && planningMode == KhatmaPlanningMode.duration
      ? KhatmaSchedule.fromDuration(
          startPage: scheduleStartPage ?? startPage,
          durationDays: durationDays,
        )
      : null;

  int get minDailyPages => _balanced?.minDailyPages ?? dailyPages;
  int get maxDailyPages => _balanced?.maxDailyPages ?? dailyPages;
  int get currentWardPages => remainingPages == 0 ? 0 : todayEnd - nextPage + 1;
  int nextWardEndAfter(int completedThrough) =>
      _balanced?.endPageAfter(completedThrough) ??
      math.min(604, completedThrough + dailyPages);

  int get totalPages => 604 - startPage + 1;
  int get completedPages => math.max(0, progressPage - startPage + 1);
  int get nextPage => math.min(604, math.max(startPage, progressPage + 1));
  int get resumePage =>
      math.min(604, math.max(nextPage, lastReadPage ?? nextPage));
  int get todayEnd {
    final savedTarget = currentWardEndPage;
    if (savedTarget != null && savedTarget >= nextPage) {
      return savedTarget.clamp(nextPage, 604).toInt();
    }
    return nextWardEndAfter(progressPage);
  }

  double get progress => (completedPages / totalPages).clamp(0, 1);
  int get remainingPages => math.max(0, 604 - progressPage);
  int get remainingDays {
    if (remainingPages == 0) return 0;
    final schedule = _balanced;
    return schedule == null
        ? (remainingPages / dailyPages).ceil()
        : durationDays - schedule.completedPortions(progressPage);
  }

  DateTime get targetDate {
    final start = scheduleStartDate ?? startDate;
    return DateTime(
      start.year,
      start.month,
      start.day + durationDays - 1,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
  }

  int get elapsedDays => math.max(
    1,
    DateTime.now()
            .difference(
              DateTime(startDate.year, startDate.month, startDate.day),
            )
            .inDays +
        1,
  );

  factory KhatmaPlan.fromJson(Map<String, dynamic> json) => KhatmaPlan(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'ختمتي',
    durationDays: (json['durationDays'] as num?)?.toInt() ?? 30,
    dailyPages: ((json['dailyPages'] as num?)?.toInt() ?? 21).clamp(1, 604),
    planningMode: KhatmaPlanningMode.values.firstWhere(
      (mode) => mode.name == json['planningMode'],
      orElse: () => KhatmaPlanningMode.duration,
    ),
    balancedSchedule: json['balancedSchedule'] == true,
    scheduleStartPage: (json['scheduleStartPage'] as num?)?.toInt(),
    scheduleStartDate: DateTime.tryParse(
      json['scheduleStartDate'] as String? ?? '',
    ),
    reminderTime: normalizeReminderTime(json['reminderTime'] as String?),
    startDate:
        DateTime.tryParse(json['startDate'] as String? ?? '') ?? DateTime.now(),
    startPage: (json['startPage'] as num?)?.toInt() ?? 1,
    progressPage: (json['progressPage'] as num?)?.toInt() ?? 0,
    lastReadPage: (json['lastReadPage'] as num?)?.toInt(),
    currentWardEndPage: (json['currentWardEndPage'] as num?)?.toInt(),
    status: KhatmaStatus.values.firstWhere(
      (item) => item.name == json['status'],
      orElse: () => KhatmaStatus.active,
    ),
    reminderPrayer: json['reminderPrayer'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    pausedAt: DateTime.tryParse(json['pausedAt'] as String? ?? ''),
    completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'durationDays': durationDays,
    'dailyPages': dailyPages,
    'planningMode': planningMode.name,
    'balancedSchedule': balancedSchedule,
    'scheduleStartPage': scheduleStartPage,
    'scheduleStartDate': scheduleStartDate?.toIso8601String(),
    'reminderTime': reminderTime,
    'startDate': startDate.toIso8601String(),
    'startPage': startPage,
    'progressPage': progressPage,
    'lastReadPage': lastReadPage,
    'currentWardEndPage': currentWardEndPage,
    'status': status.name,
    'reminderPrayer': reminderPrayer,
    'createdAt': createdAt.toIso8601String(),
    'pausedAt': pausedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  KhatmaPlan copyWith({
    String? name,
    int? durationDays,
    int? dailyPages,
    KhatmaPlanningMode? planningMode,
    bool? balancedSchedule,
    int? scheduleStartPage,
    DateTime? scheduleStartDate,
    Object? reminderTime = _unset,
    int? progressPage,
    Object? lastReadPage = _unset,
    Object? currentWardEndPage = _unset,
    KhatmaStatus? status,
    Object? reminderPrayer = _unset,
    Object? pausedAt = _unset,
    Object? completedAt = _unset,
  }) => KhatmaPlan(
    id: id,
    name: name ?? this.name,
    durationDays: durationDays ?? this.durationDays,
    dailyPages: dailyPages ?? this.dailyPages,
    planningMode: planningMode ?? this.planningMode,
    balancedSchedule: balancedSchedule ?? this.balancedSchedule,
    scheduleStartPage: scheduleStartPage ?? this.scheduleStartPage,
    scheduleStartDate: scheduleStartDate ?? this.scheduleStartDate,
    reminderTime: identical(reminderTime, _unset)
        ? this.reminderTime
        : normalizeReminderTime(reminderTime as String?),
    startDate: startDate,
    startPage: startPage,
    progressPage: progressPage ?? this.progressPage,
    lastReadPage: identical(lastReadPage, _unset)
        ? this.lastReadPage
        : lastReadPage as int?,
    currentWardEndPage: identical(currentWardEndPage, _unset)
        ? this.currentWardEndPage
        : currentWardEndPage as int?,
    status: status ?? this.status,
    reminderPrayer: identical(reminderPrayer, _unset)
        ? this.reminderPrayer
        : reminderPrayer as String?,
    createdAt: createdAt,
    pausedAt: identical(pausedAt, _unset)
        ? this.pausedAt
        : pausedAt as DateTime?,
    completedAt: identical(completedAt, _unset)
        ? this.completedAt
        : completedAt as DateTime?,
  );

  static String? normalizeReminderTime(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [
    id,
    name,
    durationDays,
    dailyPages,
    planningMode,
    balancedSchedule,
    scheduleStartPage,
    scheduleStartDate,
    reminderTime,
    startDate,
    startPage,
    progressPage,
    lastReadPage,
    currentWardEndPage,
    status,
    reminderPrayer,
    createdAt,
    pausedAt,
    completedAt,
  ];
}

const _unset = Object();
