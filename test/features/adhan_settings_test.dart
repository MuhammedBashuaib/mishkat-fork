import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/features/settings/data/models/reminder_preferences.dart';
import 'package:mishkat_app/features/settings/data/models/adhan_preferences.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

class _Storage extends LocalStorageService {
  Map<String, dynamic> settings = const AppSettings(
    latitude: 21.4225,
    longitude: 39.8262,
    notificationsEnabled: true,
  ).toJson();
  Completer<void>? gate;
  @override
  Map<String, dynamic> readMap(String key) => key == 'settings' ? settings : {};
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    settings = value;
    await gate?.future;
  }
}

class _Notifications extends LocalNotificationService {
  List<ScheduledAppNotification> latest = [];
  bool cancelled = false;
  @override
  Future<bool> canSchedulePrecisely() async => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleAll(List<ScheduledAppNotification> notifications) async {
    latest = notifications;
    cancelled = false;
  }

  @override
  Future<void> cancelAll() async => cancelled = true;
}

void main() {
  late _Storage storage;
  late _Notifications notifications;
  late SettingsCubit cubit;
  setUp(() async {
    storage = _Storage();
    notifications = _Notifications();
    cubit = SettingsCubit(
      storage: storage,
      locationService: LocationService(),
      notifications: notifications,
    );
    await cubit.load();
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() => cubit.close());

  test('choosing a prayer enables its notification and disabling it clears its sound choice', () async {
    await cubit.setPrayerNotification('fajr', false);
    expect(cubit.state.settings.prayerAdhanEnabled['fajr'], false);
    await cubit.setPrayerAdhan('fajr', true);
    expect(cubit.state.settings.prayerNotifications['fajr'], true);
    expect(cubit.state.settings.prayerAdhanEnabled['fajr'], true);
    await cubit.setPrayerAdhan('fajr', false);
    expect(cubit.state.settings.prayerNotifications['fajr'], true);
    expect(
      notifications.latest
          .where((item) => item.payload == 'prayer:fajr')
          .every((item) => !item.sound),
      true,
    );
  });

  test(
    'rapid voice and duration changes keep the latest state and calendar',
    () async {
      storage.gate = Completer<void>();
      final first = cubit.setAdhanFile('adhan4');
      final second = cubit.setAdhanPlaybackMode(AdhanPlaybackMode.short);
      storage.gate!.complete();
      await Future.wait([first, second]);
      expect(cubit.state.settings.adhanFile, 'adhan4');
      expect(cubit.state.settings.adhanPlaybackMode, AdhanPlaybackMode.short);
      expect(
        notifications.latest
            .where((item) => item.kind == AppNotificationKind.adhan)
            .every((item) => item.soundName == 'adhan4_short'),
        true,
      );
      expect(AppSettings.fromJson(storage.settings), cubit.state.settings);
    },
  );

  test(
    'rapid disable then enable does not cancel the newer enabled calendar',
    () async {
      storage.gate = Completer<void>();
      final disable = cubit.setNotificationsEnabled(false);
      final enable = cubit.setNotificationsEnabled(true);
      await Future<void>.delayed(Duration.zero);
      storage.gate!.complete();
      await Future.wait([disable, enable]);
      expect(cubit.state.settings.notificationsEnabled, true);
      expect(notifications.cancelled, false);
    },
  );

  test('reminder choices persist and immediately replace the notification calendar', () async {
    await cubit.setReminders(
      const ReminderPreferences(
        charityEnabled: false,
        dhikrPerDay: 5,
        sound: true,
        dailyWirdMinute: 19 * 60,
        sleepMinute: 23 * 60,
      ),
    );
    expect(
      notifications.latest.where((item) => item.payload == 'charity'),
      isEmpty,
    );
    expect(
      notifications.latest.where(
        (item) => item.payload?.startsWith('tasbih:') == true,
      ),
      hasLength(5),
    );
    expect(
      notifications.latest
          .singleWhere((item) => item.payload == 'adhkar:2')
          .at
          .hour,
      23,
    );
    expect(AppSettings.fromJson(storage.settings), cubit.state.settings);
  });
}
