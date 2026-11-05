import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/khatma/data/models/khatma_plan.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_plan.dart';
import 'package:mishkat_app/features/prayer_times/data/services/prayer_calculator.dart';
import 'package:mishkat_app/features/settings/data/models/adhan_preferences.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/data/models/reminder_preferences.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_state.dart';
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
        result.any((item) => item.payload?.startsWith('tasbih:') == true),
        isTrue,
      );
      expect(
        result
            .where(
              (item) =>
                  item.kind == AppNotificationKind.adhkar && item.repeatsDaily,
            )
            .length,
        4,
      );
      final eveningReminders = result
          .where((item) => item.payload == 'adhkar:133')
          .toList();
      expect(eveningReminders, hasLength(1));
      expect(eveningReminders.single.repeatsDaily, isTrue);
      final tomorrow = NotificationSchedulePlanner.build(
        storage: storage,
        settings: settings,
        now: DateTime(2026, 10, 20, 12),
      ).singleWhere((item) => item.payload == 'adhkar:133');
      expect(eveningReminders.single.title, isNot(tomorrow.title));
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

    final markers = result.where(
      (item) => item.id == NotificationSchedulePlanner.memorizationReminderId,
    );
    expect(markers, hasLength(1));
    expect(
      markers.single.id,
      NotificationSchedulePlanner.memorizationReminderId,
    );
    expect(markers.single.at.isBefore(DateTime(2000)), isTrue);
  });

  test('applies the selected adhan length and per-prayer sound settings', () {
    final now = DateTime(2026, 10, 19);
    const settings = AppSettings(
      latitude: 34.0522,
      longitude: -118.2437,
      city: 'لوس أنجلوس',
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

  test('all prayers disabled clears old alarms without scheduling sunrise', () {
    final result = NotificationSchedulePlanner.build(
      storage: _MemoryStorage(const {}),
      settings: const AppSettings(
        latitude: 21.4225,
        longitude: 39.8262,
        notificationsEnabled: true,
        adhkarNotifications: false,
        reminders: ReminderPreferences(
          charityEnabled: false,
          dhikrEnabled: false,
          dailyWirdEnabled: false,
        ),
        prayerNotifications: {
          'fajr': false,
          'dhuhr': false,
          'asr': false,
          'maghrib': false,
          'isha': false,
        },
      ),
      now: DateTime(2026, 10, 19),
      days: 2,
    );
    expect(
      result.any((item) => item.id == 100000 && item.at.year == 1970),
      true,
    );
    expect(result.where((item) => item.at.year > 2000), isEmpty);
  });

  test(
    'global mute keeps prayer notifications but removes every adhan sound',
    () {
      final result = NotificationSchedulePlanner.build(
        storage: _MemoryStorage(const {}),
        settings: const AppSettings(
          latitude: 21.4225,
          longitude: 39.8262,
          notificationsEnabled: true,
          adhanSound: false,
        ),
        now: DateTime(2026, 10, 19),
        days: 2,
      );
      final prayers = result.where(
        (item) => item.kind == AppNotificationKind.adhan,
      );
      expect(prayers, isNotEmpty);
      expect(
        prayers.every((item) => !item.sound && item.soundName == null),
        true,
      );
      expect(result.any((item) => item.payload == 'prayer:sunrise'), false);
    },
  );

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

  test(
    'daily reminders work without location and continue with repeating alarms',
    () {
      final now = DateTime(2026, 10, 31);
      final result = NotificationSchedulePlanner.build(
        storage: _MemoryStorage({}),
        settings: const AppSettings(notificationsEnabled: true, vibrate: false),
        now: now,
      ).where((item) => item.at.isAfter(now)).toList();
      final charity = result
          .where((item) => item.kind == AppNotificationKind.charity)
          .toList();
      expect(charity, hasLength(2));
      expect(charity.map((item) => (item.at.hour, item.at.minute)), [
        (9, 0),
        (18, 30),
      ]);
      expect(charity.first.body, isNot(charity.last.body));
      expect(
        result.where((item) => item.kind == AppNotificationKind.dhikr),
        hasLength(3),
      );
      expect(result.singleWhere((item) => item.payload == 'wird').at.hour, 20);
      expect(
        result.singleWhere((item) => item.payload == 'adhkar:1').at.hour,
        7,
      );
      expect(
        result.singleWhere((item) => item.payload == 'adhkar:133').at.hour,
        18,
      );
      expect(
        result.singleWhere((item) => item.payload == 'adhkar:2').at.hour,
        22,
      );
      expect(
        result.every(
          (item) => item.repeatsDaily && !item.sound && !item.vibrate,
        ),
        true,
      );
      expect(result.map((item) => item.id).toSet(), hasLength(result.length));
    },
  );

  test('master switch and individual categories remove their reminders', () {
    final storage = _MemoryStorage({});
    final now = DateTime(2026, 10, 31);
    expect(
      NotificationSchedulePlanner.build(
        storage: storage,
        settings: const AppSettings(),
        now: now,
      ),
      isEmpty,
    );
    final result = NotificationSchedulePlanner.build(
      storage: storage,
      now: now,
      settings: const AppSettings(
        notificationsEnabled: true,
        adhkarNotifications: false,
        reminders: ReminderPreferences(
          charityEnabled: false,
          dhikrEnabled: false,
          dailyWirdEnabled: false,
        ),
      ),
    );
    expect(result.where((item) => item.at.isAfter(now)), isEmpty);
    expect(result.any((item) => item.id == 100000), true);
  });

  test('dhikr texts match the selected tasbih for every frequency and day', () {
    for (final frequency in [1, 3, 5]) {
      for (var day = 1; day <= 7; day++) {
        final now = DateTime(2026, 11, day);
        final result = NotificationSchedulePlanner.build(
          storage: _MemoryStorage({}),
          now: now,
          settings: AppSettings(
            notificationsEnabled: true,
            reminders: ReminderPreferences(dhikrPerDay: frequency),
          ),
        );
        final dhikrs = result
            .where((item) => item.kind == AppNotificationKind.dhikr)
            .toList();
        expect(dhikrs, hasLength(frequency));
        expect(
          dhikrs.map((item) => item.payload).toSet(),
          hasLength(frequency),
        );
        for (final item in dhikrs) {
          final id = item.payload!.split(':').last;
          final dhikr = tasbihDhikrOptions.singleWhere((item) => item.id == id);
          expect(item.body, startsWith(dhikr.text));
          expect(item.at.hour, inInclusiveRange(8, 21));
        }
      }
    }
  });

  test('crowded reminders are spaced and stay inside daytime hours', () {
    final now = DateTime(2026, 10, 31);
    final result = NotificationSchedulePlanner.build(
      storage: _MemoryStorage({}),
      now: now,
      settings: const AppSettings(
        notificationsEnabled: true,
        reminders: ReminderPreferences(
          charityMorningMinute: 21 * 60 + 55,
          charityEveningMinute: 21 * 60 + 55,
          dailyWirdMinute: 21 * 60 + 55,
          dhikrPerDay: 5,
        ),
      ),
    ).where((item) => item.id >= 400000 && item.id < 500000).toList();
    final minutes =
        result.map((item) => item.at.hour * 60 + item.at.minute).toList()
          ..sort();
    expect(minutes.first, greaterThanOrEqualTo(8 * 60));
    expect(minutes.last, lessThan(22 * 60));
    for (var i = 1; i < minutes.length; i++) {
      expect(minutes[i] - minutes[i - 1], greaterThanOrEqualTo(15));
    }
  });

  test('late-night refresh schedules the next local calendar day', () {
    final now = DateTime(2026, 10, 31, 23, 59);
    final result = NotificationSchedulePlanner.build(
      storage: _MemoryStorage({}),
      now: now,
      settings: const AppSettings(
        notificationsEnabled: true,
        reminders: ReminderPreferences(sleepMinute: 23 * 60),
      ),
    ).where((item) => item.at.isAfter(now));
    expect(result, isNotEmpty);
    expect(
      result.every(
        (item) =>
            item.at.year == 2026 && item.at.month == 11 && item.at.day == 1,
      ),
      true,
    );
    expect(
      result.singleWhere((item) => item.payload == 'adhkar:2').at.hour,
      23,
    );
  });

  test(
    'uses the explicit khatma reminder once, with a no-location fallback',
    () {
      final now = DateTime(2026, 10, 31, 23);
      final plan = KhatmaPlan(
        id: 'active',
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
      final storage = _MemoryStorage({
        'khatma': {
          'plans': [plan.toJson()],
        },
      });
      final settings = const AppSettings(
        notificationsEnabled: true,
        latitude: 34.0522,
        longitude: -118.2437,
      );
      final result = NotificationSchedulePlanner.build(
        storage: storage,
        settings: settings,
        now: now,
      );
      final wird = result
          .where((item) => item.kind == AppNotificationKind.khatma)
          .toList();
      expect(wird, hasLength(1));
      expect(wird.single.payload, 'khatma:active');
      expect(wird.single.repeatsDaily, true);
      final withoutLocation = NotificationSchedulePlanner.build(
        storage: storage,
        settings: settings.copyWith(latitude: null, longitude: null),
        now: now,
      );
      expect(
        withoutLocation.where((item) => item.payload == 'khatma:active'),
        hasLength(1),
      );
      final disabled = NotificationSchedulePlanner.build(
        storage: storage,
        settings: settings.copyWith(
          reminders: settings.reminders.copyWith(dailyWirdEnabled: false),
        ),
        now: now,
      );
      expect(
        disabled.where((item) => item.payload == 'khatma:active'),
        hasLength(1),
      );
    },
  );

  test(
    'custom khatma time repeats exactly without a location or generic wird',
    () {
      final now = DateTime(2026, 10, 31, 23, 50);
      final plan = _khatmaPlan(now, reminderTime: '05:07');
      final storage = _MemoryStorage({
        'khatma': {
          'plans': [plan.toJson()],
        },
      });
      final result = NotificationSchedulePlanner.build(
        storage: storage,
        now: now,
        settings: const AppSettings(
          notificationsEnabled: true,
          reminders: ReminderPreferences(dailyWirdEnabled: false),
        ),
      );
      final reminders = result.where(
        (item) => item.kind == AppNotificationKind.khatma,
      );
      expect(reminders, hasLength(1));
      final reminder = reminders.single;
      expect(reminder.at, DateTime(2026, 11, 1, 5, 7));
      expect(reminder.repeatsDaily, true);
      expect(reminder.payload, 'khatma:custom');
    },
  );

  test('explicit time wins conflicts and suppresses the generic wird', () {
    final now = DateTime(2026, 11, 5, 8);
    final plan = _khatmaPlan(now, reminderTime: '09:00');
    final result = NotificationSchedulePlanner.build(
      storage: _MemoryStorage({
        'khatma': {
          'plans': [plan.toJson()],
        },
      }),
      now: now,
      settings: const AppSettings(notificationsEnabled: true),
    );
    expect(
      result.singleWhere((item) => item.payload == 'khatma:custom').at,
      DateTime(2026, 11, 5, 9),
    );
    expect(result.where((item) => item.payload == 'wird'), isEmpty);
    expect(
      result
          .where((item) => item.payload == 'charity')
          .every(
            (item) => (item.at.hour * 60 + item.at.minute - 9 * 60).abs() >= 15,
          ),
      true,
    );
  });

  test('past or exact current custom time moves to tomorrow without drift', () {
    final now = DateTime(2026, 12, 31, 23, 59);
    final plan = _khatmaPlan(now, reminderTime: '23:59');
    final reminder = NotificationSchedulePlanner.build(
      storage: _MemoryStorage({
        'khatma': {
          'plans': [plan.toJson()],
        },
      }),
      now: now,
      settings: const AppSettings(notificationsEnabled: true),
    ).singleWhere((item) => item.payload == 'khatma:custom');
    expect(reminder.at, DateTime(2027, 1, 1, 23, 59));
  });

  test(
    'paused, completed, removed and malformed plans have no explicit alarm',
    () {
      final now = DateTime(2026, 11, 5, 8);
      final plan = _khatmaPlan(now, reminderTime: '19:00');
      for (final plans in [
        [plan.copyWith(status: KhatmaStatus.paused).toJson()],
        [plan.copyWith(status: KhatmaStatus.completed).toJson()],
        [
          {...plan.toJson(), 'reminderTime': '25:99'},
        ],
        <Map<String, dynamic>>[],
      ]) {
        final result = NotificationSchedulePlanner.build(
          storage: _MemoryStorage({
            'khatma': {'plans': plans},
          }),
          now: now,
          settings: const AppSettings(notificationsEnabled: true),
        );
        expect(
          result.where((item) => item.payload?.startsWith('khatma:') == true),
          isEmpty,
        );
        // The replacement marker makes the service clear previous plan alarms.
        expect(
          result.any((item) => item.id == 100000 && item.at.isBefore(now)),
          true,
        );
      }
    },
  );

  test(
    'after-prayer reminder uses the next actual prayer plus fifteen minutes',
    () {
      const settings = AppSettings(
        notificationsEnabled: true,
        latitude: 21.4225,
        longitude: 39.8262,
        reminders: ReminderPreferences(dailyWirdEnabled: false),
      );
      DateTime fajrOn(DateTime date) => const PrayerCalculator()
          .calculate(
            date: date,
            latitude: settings.latitude!,
            longitude: settings.longitude!,
            methodKey: settings.method,
            methodAuto: !settings.methodSet,
            asr: settings.asr,
            highLatitudes: settings.highLatitudes,
            tune: settings.tune,
          )['fajr']!
          .add(const Duration(minutes: 15));
      // Anchor to the calculated moment so this also covers a distant city
      // whose prayer lands on the preceding local calendar date.
      final now = fajrOn(DateTime(2026, 11, 5)).add(const Duration(minutes: 1));
      final plan = _khatmaPlan(now, reminderPrayer: 'fajr');
      final reminder = NotificationSchedulePlanner.build(
        storage: _MemoryStorage({
          'khatma': {
            'plans': [plan.toJson()],
          },
        }),
        now: now,
        settings: settings,
      ).singleWhere((item) => item.payload == 'khatma:custom');
      expect(reminder.at, fajrOn(DateTime(2026, 11, 6)));
      expect(reminder.repeatsDaily, true);
    },
  );

  test('prayer plans retain explicit fallback time without location or generic wird', () {
    final now = DateTime(2026, 11, 5, 12);
    final plan = _khatmaPlan(now, reminderPrayer: 'isha');
    final reminders = NotificationSchedulePlanner.build(
      storage: _MemoryStorage({
        'khatma': {
          'plans': [plan.toJson()],
        },
      }),
      now: now,
      settings: const AppSettings(
        notificationsEnabled: true,
        reminders: ReminderPreferences(
          dailyWirdEnabled: false,
          dailyWirdMinute: 21 * 60 + 17,
        ),
      ),
    ).where((item) => item.kind == AppNotificationKind.khatma);
    expect(reminders, hasLength(1));
    expect(reminders.single.payload, 'khatma:custom');
    expect(reminders.single.at, DateTime(2026, 11, 5, 21, 17));
  });

  test('migrates reminder choices and validates damaged saved values', () {
    final old = AppSettings.fromJson({
      'notificationsEnabled': true,
      'adhkarNotifications': false,
    });
    expect(old.adhkarNotifications, false);
    expect(old.reminders.charityEnabled, true);
    final preferences = ReminderPreferences.fromJson({
      'charityEnabled': false,
      'dhikrEnabled': false,
      'dailyWirdEnabled': false,
      'dhikrPerDay': 999,
      'dailyWirdMinute': -5,
      'sleepMinute': 9999,
      'charityMorningMinute': 3 * 60,
    });
    expect(preferences.dhikrPerDay, 3);
    expect(preferences.dailyWirdMinute, 20 * 60 + 30);
    expect(preferences.sleepMinute, 22 * 60);
    expect(preferences.charityMorningMinute, 9 * 60);
    final settings = old.copyWith(
      reminders: preferences.copyWith(sound: true, dhikrPerDay: 5),
    );
    expect(AppSettings.fromJson(settings.toJson()), settings);
  });
}

class _MemoryStorage extends LocalStorageService {
  _MemoryStorage(this.values);

  final Map<String, Map<String, dynamic>> values;

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from(values[key] ?? const <String, dynamic>{});
}

KhatmaPlan _khatmaPlan(
  DateTime now, {
  String? reminderTime,
  String? reminderPrayer,
}) => KhatmaPlan(
  id: 'custom',
  name: 'ختمتي',
  durationDays: 150,
  dailyPages: 5,
  startDate: now,
  startPage: 1,
  progressPage: 0,
  status: KhatmaStatus.active,
  createdAt: now,
  reminderTime: reminderTime,
  reminderPrayer: reminderPrayer,
);
