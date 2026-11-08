import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/prayer_times/data/services/prayer_calculator.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/data/models/reminder_preferences.dart';
import 'package:mishkat_app/features/settings/data/services/notification_schedule_planner.dart';

class _Storage extends LocalStorageService {
  @override
  Map<String, dynamic> readMap(String key) => {};
}

const _quietReminders = ReminderPreferences(
  charityEnabled: false,
  dhikrEnabled: false,
  dailyWirdEnabled: false,
);

AppSettings _settings({bool location = false}) => AppSettings(
  notificationsEnabled: true,
  adhkarNotifications: false,
  latitude: location ? 24.7 : null,
  // Match the test host's local solar zone, including DST transitions.
  longitude: location
      ? DateTime(2026, 11, 6).timeZoneOffset.inMinutes / 4
      : null,
  method: 'MWL',
  methodSet: true,
  reminders: _quietReminders,
);

List<ScheduledAppNotification> _friday(DateTime now, AppSettings settings) =>
    NotificationSchedulePlanner.build(
      storage: _Storage(),
      settings: settings,
      now: now,
    ).where((item) => item.kind == AppNotificationKind.friday).toList();

void main() {
  test(
    'Friday preferences default on and persist independently of daily dhikr',
    () {
      expect(const ReminderPreferences().fridayEnabled, true);
      final old = AppSettings.fromJson({
        'reminders': {'dhikrEnabled': false},
      });
      expect(old.reminders.fridayEnabled, true);
      expect(old.reminders.dhikrEnabled, false);
      final updated = old.copyWith(
        reminders: old.reminders.copyWith(fridayEnabled: false),
      );
      expect(updated, isNot(old));
      expect(AppSettings.fromJson(updated.toJson()), updated);
      expect(updated.reminders.dhikrEnabled, false);
    },
  );

  test('every weekday schedules nine future weekly Friday reminders', () {
    for (var day = 2; day <= 8; day++) {
      final now = DateTime(2026, 11, day);
      final items = _friday(now, _settings());
      expect(items, hasLength(9));
      expect(items.map((item) => item.id).toSet(), hasLength(9));
      expect(items.where((item) => item.payload == 'quran:kahf'), hasLength(3));
      expect(
        items.where((item) => item.payload == 'tasbih:salawat'),
        hasLength(3),
      );
      expect(items.where((item) => item.payload == 'friday:dua'), hasLength(3));
      for (final item in items) {
        expect(item.at.weekday, DateTime.friday);
        expect(item.at.isAfter(now), true);
        expect(item.repeatsWeekly, true);
        expect(item.repeatsDaily, false);
        expect(item.sound, false);
      }
      for (var index = 1; index < items.length; index++) {
        expect(
          items[index].at.difference(items[index - 1].at).inMinutes,
          greaterThanOrEqualTo(15),
        );
      }
    }
  });

  test('Friday midnight and Saturday rollover keep stable IDs without catch-up bursts', () {
    final friday = _friday(DateTime(2026, 11, 6), _settings());
    final saturday = _friday(DateTime(2026, 11, 7), _settings());
    final lateFriday = _friday(DateTime(2026, 11, 6, 23, 59), _settings());
    expect(friday.every((item) => item.at.day == 6), true);
    expect(saturday.every((item) => item.at.day == 13), true);
    expect(lateFriday.map((item) => item.at), saturday.map((item) => item.at));
    expect(
      friday.map((item) => item.id).toSet(),
      saturday.map((item) => item.id).toSet(),
    );
  });

  test('prayer-based slots honor Friday calculation, madhhab and tuning', () {
    final settings = _settings(location: true)
        .copyWith(asr: 'Hanafi', tune: const {'asr': 7, 'maghrib': 4});
    final friday = DateTime(2026, 11, 6);
    final times = const PrayerCalculator().calculate(
      date: friday,
      latitude: settings.latitude!,
      longitude: settings.longitude!,
      methodKey: settings.method,
      methodAuto: !settings.methodSet,
      asr: settings.asr,
      tune: settings.tune,
    );
    final items = _friday(friday, settings);
    expect(items, hasLength(9));
    expect(
      items.singleWhere((item) => item.id == 500007).at,
      times['asr']!.add(const Duration(minutes: 15)),
    );
    final beforeMaghrib = items.singleWhere((item) => item.id == 500008);
    expect(
      beforeMaghrib.at,
      times['maghrib']!.subtract(const Duration(minutes: 30)),
    );
    expect(beforeMaghrib.body, contains('قبل غروب الجمعة'));
    final lastKahf = items.singleWhere((item) => item.id == 500002);
    expect(lastKahf.at, times['maghrib']!.add(const Duration(minutes: 20)));
    expect(lastKahf.body, contains('بعد صلاة المغرب'));
    expect(
      items
          .where((item) => item.id != 500002)
          .every((item) => item.at.isBefore(times['maghrib']!)),
      true,
    );
  });

  test(
    'slots already reached recalculate next Friday instead of replaying today',
    () {
      final settings = _settings(location: true);
      final initial = _friday(DateTime(2026, 11, 6), settings);
      final nextWeek = _friday(DateTime(2026, 11, 13), settings);
      for (final slot in initial) {
        final before = _friday(
          slot.at.subtract(const Duration(seconds: 1)),
          settings,
        );
        expect(before.singleWhere((item) => item.id == slot.id).at, slot.at);
        final reached = _friday(slot.at, settings);
        final next = reached.singleWhere((item) => item.id == slot.id);
        expect(next.at, nextWeek.singleWhere((item) => item.id == slot.id).at);
        expect(next.at.day, 13);
      }
      final currentDua = initial.singleWhere((item) => item.id == 500008);
      final nextDua = nextWeek.singleWhere((item) => item.id == 500008);
      expect(
        nextDua.at.hour * 60 + nextDua.at.minute,
        isNot(currentDua.at.hour * 60 + currentDua.at.minute),
        reason: 'Next week must use its new astronomical/DST time.',
      );
    },
  );

  test(
    'without location the copy never claims a computed sunset countdown',
    () {
      final items = _friday(DateTime(2026, 11, 6), _settings());
      expect(items, hasLength(9));
      expect(items.any((item) => item.body.contains('نصف ساعة')), false);
      expect(items.any((item) => item.title == 'آخر ساعة من الجمعة'), false);
      expect(items.singleWhere((item) => item.id == 500007).at.hour, 15);
      expect(items.singleWhere((item) => item.id == 500008).at.hour, 17);
      expect(
        items.singleWhere((item) => item.id == 500002).at,
        DateTime(2026, 11, 6, 18, 20),
      );
    },
  );

  test('Friday reminders respect their own switch, the master switch, sound and vibration', () {
    final now = DateTime(2026, 11, 6);
    final settings = _settings();
    expect(
      _friday(now, settings.copyWith(notificationsEnabled: false)),
      isEmpty,
    );
    expect(
      _friday(
        now,
        settings.copyWith(
          reminders: _quietReminders.copyWith(fridayEnabled: false),
        ),
      ),
      isEmpty,
    );
    final audible = _friday(
      now,
      settings.copyWith(
        vibrate: false,
        reminders: _quietReminders.copyWith(sound: true),
      ),
    );
    expect(
      audible.every(
        (item) => item.sound && !item.vibrate && item.soundName == null,
      ),
      true,
    );
  });

  test(
    'daily good-deed reminders stay separated from the reserved Friday slots',
    () {
      final now = DateTime(2026, 11, 6);
      final items = NotificationSchedulePlanner.build(
        storage: _Storage(),
        settings: _settings().copyWith(
          reminders: const ReminderPreferences(dhikrPerDay: 5),
        ),
        now: now,
      );
      final friday = items.where(
        (item) => item.kind == AppNotificationKind.friday,
      );
      final daily = items.where(
        (item) => item.id >= 400000 && item.id < 500000,
      );
      for (final special in friday) {
        for (final regular in daily) {
          final difference =
              ((special.at.hour * 60 + special.at.minute) -
                      (regular.at.hour * 60 + regular.at.minute))
                  .abs();
          expect(difference, greaterThanOrEqualTo(15));
        }
      }
    },
  );
}
