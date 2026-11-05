import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/khatma/data/models/khatma_plan.dart';
import 'package:mishkat_app/features/khatma/data/models/khatma_schedule.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('five months produces exactly 150 complete portions, not 121', () async {
    final cubit = KhatmaCubit(_MemoryStorage());
    addTearDown(cubit.close);
    await cubit.create(name: 'خمسة أشهر', durationDays: 150, startPage: 1);
    expect(cubit.state.active!.minDailyPages, 4);
    expect(cubit.state.active!.maxDailyPages, 5);
    for (var day = 0; day < 150; day++) {
      final plan = cubit.state.active!;
      expect(plan.status, KhatmaStatus.active);
      expect(plan.remainingDays, 150 - day);
      expect(plan.currentWardPages, day < 4 ? 5 : 4);
      await cubit.completeToday();
    }
    expect(cubit.state.active!.progressPage, 604);
    expect(cubit.state.active!.remainingDays, 0);
    expect(cubit.state.active!.currentWardPages, 0);
    expect(cubit.state.active!.status, KhatmaStatus.completed);
  });

  test('three-day duration balances 202, 201, 201 pages', () async {
    final cubit = KhatmaCubit(_MemoryStorage());
    addTearDown(cubit.close);
    await cubit.create(name: 'ثلاثة أيام', durationDays: 3, startPage: 1);
    expect(cubit.state.active!.todayEnd, 202);
    await cubit.completeToday();
    expect(cubit.state.active!.todayEnd, 403);
    expect(cubit.state.active!.currentWardPages, 201);
    await cubit.completeToday();
    expect(cubit.state.active!.todayEnd, 604);
    await cubit.completeToday();
    expect(cubit.state.active!.status, KhatmaStatus.completed);
  });

  test(
    'fixed five pages stay fixed after saving and finish in 121 days',
    () async {
      final storage = _MemoryStorage();
      final first = KhatmaCubit(storage);
      await first.create(
        name: 'خمس صفحات',
        durationDays: 30,
        startPage: 1,
        planningMode: KhatmaPlanningMode.pages,
        dailyPages: 5,
        reminderPrayer: 'fajr',
        reminderTime: '7:05',
      );
      expect(first.state.active!.durationDays, 121);
      expect(first.state.active!.dailyPages, 5);
      expect(first.state.active!.reminderTime, '07:05');
      expect(first.state.active!.reminderPrayer, isNull);
      await first.completeToday();
      await first.close();

      final restored = KhatmaCubit(storage);
      addTearDown(restored.close);
      expect(restored.state.active!.planningMode, KhatmaPlanningMode.pages);
      expect(restored.state.active!.todayEnd, 10);
      expect(restored.state.active!.remainingDays, 120);
      expect(restored.state.active!.reminderTime, '07:05');
      await restored.recordProgress(600);
      expect(restored.state.active!.currentWardPages, 4);
      expect(restored.state.active!.remainingDays, 1);
      await restored.completeToday();
      expect(restored.state.active!.status, KhatmaStatus.completed);
    },
  );

  test(
    'duration progress resumes inside the original balanced portion',
    () async {
      final storage = _MemoryStorage();
      final first = KhatmaCubit(storage);
      await first.create(
        name: 'من منتصف المصحف',
        durationDays: 3,
        startPage: 600,
      );
      final id = first.state.active!.id;
      expect(first.state.active!.todayEnd, 601);
      await first.recordReadingPosition(
        planId: id,
        currentPage: 601,
        completedThrough: 600,
      );
      await first.close();
      final restored = KhatmaCubit(storage);
      addTearDown(restored.close);
      expect(restored.state.active!.currentWardPages, 1);
      expect(restored.state.active!.remainingDays, 3);
      await restored.completeToday();
      expect(restored.state.active!.todayEnd, 603);
      expect(restored.state.active!.remainingDays, 2);
      await restored.completeToday();
      expect(restored.state.active!.todayEnd, 604);
      expect(restored.state.active!.currentWardPages, 1);
    },
  );

  test('legacy plans preserve their saved ward and fixed daily pace', () {
    final legacy = KhatmaPlan.fromJson({
      'id': 'old',
      'startDate': '2026-01-01T10:30:00',
      'createdAt': '2026-01-01T10:30:00',
      'durationDays': 150,
      'dailyPages': 5,
      'startPage': 1,
      'progressPage': 24,
      'currentWardEndPage': 25,
    });
    expect(legacy.balancedSchedule, false);
    expect(legacy.todayEnd, 25);
    expect(legacy.nextWardEndAfter(25), 30);
    expect(legacy.reminderTime, isNull);
    expect(KhatmaPlan.fromJson(legacy.toJson()), legacy);
  });

  test('rebalance distributes the remaining pages from the new date', () async {
    final cubit = KhatmaCubit(_MemoryStorage());
    addTearDown(cubit.close);
    await cubit.create(
      name: 'ختمتي',
      durationDays: 30,
      startPage: 1,
      planningMode: KhatmaPlanningMode.pages,
      dailyPages: 5,
    );
    await cubit.recordProgress(599);
    await cubit.rebalance(3);
    final plan = cubit.state.active!;
    expect(plan.startPage, 1);
    expect(plan.completedPages, 599);
    expect(plan.scheduleStartPage, 600);
    expect(plan.planningMode, KhatmaPlanningMode.duration);
    expect(plan.remainingDays, 3);
    expect(plan.todayEnd, 601);
    expect(
      plan.targetDate.day,
      DateTime(
        plan.scheduleStartDate!.year,
        plan.scheduleStartDate!.month,
        plan.scheduleStartDate!.day + 2,
      ).day,
    );
    expect(KhatmaPlan.fromJson(plan.toJson()), plan);
  });

  test(
    'schedule validates empty, negative and impossible whole-page durations',
    () {
      for (final days in [0, -1, 605]) {
        expect(
          () => KhatmaSchedule.fromDuration(startPage: 1, durationDays: days),
          throwsRangeError,
        );
      }
      expect(
        () => KhatmaSchedule.fromDuration(startPage: 600, durationDays: 6),
        throwsRangeError,
      );
      for (final pages in [0, -1, 605]) {
        expect(
          () => KhatmaSchedule.fromDailyPages(startPage: 1, dailyPages: pages),
          throwsRangeError,
        );
      }
      expect(
        KhatmaSchedule.fromDuration(
          startPage: 1,
          durationDays: 604,
        ).maxDailyPages,
        1,
      );
      final lastPage = KhatmaSchedule.fromDailyPages(
        startPage: 604,
        dailyPages: 5,
      );
      expect(lastPage.durationDays, 1);
      expect(lastPage.endPageAfter(603), 604);
    },
  );

  test('target date uses calendar days across month and year boundaries', () {
    final schedule = KhatmaSchedule.fromDuration(startPage: 1, durationDays: 3);
    expect(
      schedule.targetDate(DateTime(2026, 12, 31, 8)),
      DateTime(2027, 1, 2, 8),
    );
    expect(
      schedule.targetDate(DateTime(2028, 2, 28, 8)),
      DateTime(2028, 3, 1, 8),
    );
  });

  test('custom reminder normalization rejects invalid clock times', () {
    expect(KhatmaPlan.normalizeReminderTime('0:00'), '00:00');
    expect(KhatmaPlan.normalizeReminderTime('23:59'), '23:59');
    for (final value in [null, '', '24:00', '12:60', '-1:05', '12:5', 'noon']) {
      expect(KhatmaPlan.normalizeReminderTime(value), isNull);
    }
  });

  test(
    'failed persistence leaves no phantom plan or scheduled reminder',
    () async {
      final storage = _FailingStorage()
        ..values['settings'] = {'notificationsEnabled': true};
      final notifications = _RecordingNotifications();
      final cubit = KhatmaCubit(storage, notifications: notifications);
      addTearDown(cubit.close);

      await expectLater(
        cubit.create(
          name: 'ختمتي',
          durationDays: 30,
          startPage: 1,
          reminderTime: '18:45',
        ),
        throwsStateError,
      );
      expect(cubit.state.plans, isEmpty);
      expect(cubit.state.activeId, isNull);
      expect(storage.readMap('khatma'), isEmpty);
      expect(notifications.refreshes, 0);
    },
  );

  test(
    'failed scheduling preserves the durable plan and its reminder',
    () async {
      final storage = _MemoryStorage()
        ..values['settings'] = {'notificationsEnabled': true};
      final notifications = _FailingNotifications();
      final cubit = KhatmaCubit(storage, notifications: notifications);
      addTearDown(cubit.close);

      await expectLater(
        cubit.create(
          name: 'ختمتي',
          durationDays: 30,
          startPage: 1,
          reminderTime: '18:45',
        ),
        throwsStateError,
      );
      expect(cubit.state.plans, hasLength(1));
      final restored = KhatmaCubit(storage);
      addTearDown(restored.close);
      expect(restored.state.active, cubit.state.active);
      expect(restored.state.active!.reminderTime, '18:45');
    },
  );

  test('plan lifecycle refreshes the shared notification calendar', () async {
    final storage = _MemoryStorage()
      ..values['settings'] = {'notificationsEnabled': true};
    final notifications = _RecordingNotifications();
    final cubit = KhatmaCubit(storage, notifications: notifications);
    addTearDown(cubit.close);
    await cubit.create(
      name: 'ختمتي',
      durationDays: 1,
      startPage: 604,
      reminderTime: '18:45',
    );
    final id = cubit.state.active!.id;
    expect(notifications.refreshes, 1);
    await cubit.setActive(id);
    await cubit.togglePause();
    await cubit.togglePause();
    await cubit.completeToday();
    await cubit.delete(id);
    expect(notifications.refreshes, 6);
  });
}

class _MemoryStorage extends LocalStorageService {
  final values = <String, Map<String, dynamic>>{};
  @override
  Map<String, dynamic> readMap(String key) => values[key] ?? {};
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    values[key] = value;
  }
}

class _RecordingNotifications extends LocalNotificationService {
  int refreshes = 0;
  @override
  Future<void> scheduleAll(List<ScheduledAppNotification> notifications) async {
    refreshes++;
  }
}

class _FailingStorage extends _MemoryStorage {
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    throw StateError('storage is full');
  }
}

class _FailingNotifications extends LocalNotificationService {
  @override
  Future<void> scheduleAll(List<ScheduledAppNotification> notifications) async {
    throw StateError('notification scheduling unavailable');
  }
}
