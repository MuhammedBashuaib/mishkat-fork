import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/khatma/data/models/khatma_plan.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_plan.dart';
import 'package:mishkat_app/features/settings/data/models/adhan_preferences.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/data/services/notification_schedule_planner.dart';

void main() {
  test(
    'builds prayer, adhkar, khatma and recurring memorization reminders',
    () {
      final now = DateTime(2026, 10, 19, 12);
      final khatma = KhatmaPlan(
        id: 'khatma-1',
        name: 'ختمتي',
        durationDays: 30,
        dailyPages: 20,
        startDate: now,
        startPage: 1,
        progressPage: 40,
        status: KhatmaStatus.active,
        reminderPrayer: 'isha',
        createdAt: now,
      );
      final memorization = MemorizationPlan(
        id: 'hifz-1',
        title: 'حفظ سورة البقرة',
        startGlobalAyah: 1,
        endGlobalAyah: 100,
        dailyTarget: 5,
        createdAt: now,
        reminderHour: 19,
        reminderMinute: 30,
      );
      final storage = _MemoryStorage({
        'khatma': {
          'plans': [khatma.toJson()],
        },
        'quran_memorization': {
          'plans': [memorization.toJson()],
        },
      });
      const settings = AppSettings(
        latitude: 21.4225,
        longitude: 39.8262,
        city: 'مكة المكرمة',
        notificationsEnabled: true,
        adhkarNotifications: true,
        preMinutes: 10,
      );

      final result = NotificationSchedulePlanner.build(
        storage: storage,
        settings: settings,
        now: now,
        days: 3,
      );

      expect(
        result.any((item) => item.kind == AppNotificationKind.adhan),
        isTrue,
      );
      expect(
        result.any((item) => item.kind == AppNotificationKind.prayerReminder),
        isTrue,
      );
      expect(result.any((item) => item.payload == 'adhkar:1'), isTrue);
      expect(result.any((item) => item.payload == 'adhkar:133'), isTrue);
      expect(result.any((item) => item.payload == 'adhkar:3'), isTrue);
      expect(result.any((item) => item.payload == 'adhkar:2'), isTrue);
      expect(
        result.any(
          (item) =>
              item.payload == 'adhkar:129' || item.payload == 'adhkar:130',
        ),
        isTrue,
      );
      expect(
        result
            .where(
              (item) =>
                  item.kind == AppNotificationKind.adhkar && item.repeatsDaily,
            )
            .length,
        3,
      );
      final eveningReminders = result
          .where((item) => item.payload == 'adhkar:133')
          .toList();
      expect(eveningReminders.length, greaterThanOrEqualTo(2));
      expect(eveningReminders.first.title, isNot(eveningReminders[1].title));
      expect(result.any((item) => item.payload == 'khatma:khatma-1'), isTrue);
      final hifz = result.singleWhere(
        (item) => item.id == NotificationSchedulePlanner.memorizationReminderId,
      );
      expect(hifz.payload, 'memorization:hifz-1');
      expect(hifz.repeatsDaily, isTrue);
      expect(hifz.at.hour, 19);
      expect(hifz.at.minute, 30);
    },
  );

  test('emits a cancellation marker when no Hifz reminder is active', () {
    final result = NotificationSchedulePlanner.build(
      storage: _MemoryStorage(const {}),
      settings: const AppSettings(notificationsEnabled: true),
      now: DateTime(2026, 10, 19),
    );

    expect(result, hasLength(1));
    expect(
      result.single.id,
      NotificationSchedulePlanner.memorizationReminderId,
    );
    expect(result.single.at.isBefore(DateTime(2000)), isTrue);
  });

  test('applies the selected adhan length and per-prayer sound settings', () {
    final now = DateTime(2026, 10, 19);
    const settings = AppSettings(
      latitude: 21.4225,
      longitude: 39.8262,
      city: 'مكة المكرمة',
      notificationsEnabled: true,
      adhanFile: 'adhan4',
      adhanPlaybackMode: AdhanPlaybackMode.short,
      preMinutes: 10,
      prayerAdhanEnabled: {
        'fajr': false,
        'dhuhr': true,
        'asr': true,
        'maghrib': true,
        'isha': true,
      },
    );

    final result = NotificationSchedulePlanner.build(
      storage: _MemoryStorage(const {}),
      settings: settings,
      now: now,
      days: 1,
    );

    final fajr = result.singleWhere((item) => item.payload == 'prayer:fajr');
    expect(fajr.sound, isFalse);
    expect(fajr.soundName, isNull);

    final dhuhr = result.singleWhere((item) => item.payload == 'prayer:dhuhr');
    expect(dhuhr.sound, isTrue);
    expect(dhuhr.soundName, 'adhan4_short');

    final earlyReminder = result.singleWhere(
      (item) => item.payload == 'prayer:dhuhr:pre',
    );
    expect(earlyReminder.sound, isTrue);
    expect(earlyReminder.soundName, isNull);
  });

  test('migrates legacy prayer choices into per-prayer adhan settings', () {
    final settings = AppSettings.fromJson({
      'adhanFile': 'a2',
      'prayerNotifications': {'fajr': false, 'dhuhr': true},
    });

    expect(settings.adhanFile, 'adhan2');
    expect(settings.adhanPlaybackMode, AdhanPlaybackMode.full);
    expect(settings.prayerAdhanEnabled['fajr'], isFalse);
    expect(settings.prayerAdhanEnabled['dhuhr'], isTrue);
    expect(settings.prayerAdhanEnabled['asr'], isTrue);

    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored, settings);
  });
}

class _MemoryStorage extends LocalStorageService {
  _MemoryStorage(this.values);

  final Map<String, Map<String, dynamic>> values;

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from(values[key] ?? const <String, dynamic>{});
}
