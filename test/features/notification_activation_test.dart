import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_state.dart';

class _Storage extends LocalStorageService {
  Map<String, dynamic> settings = {};
  @override
  Map<String, dynamic> readMap(String key) => key == 'settings' ? settings : {};
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    settings = value;
  }
}

class _Notifications extends LocalNotificationService {
  bool failPermission = false, failSchedule = false, failCancel = false;
  Completer<void>? scheduleGate;
  @override
  Future<bool> requestPermission() async {
    if (failPermission) throw PlatformException(code: 'permission_failed');
    return true;
  }

  @override
  Future<bool> canSchedulePrecisely() async => true;
  @override
  Future<void> scheduleAll(List<ScheduledAppNotification> notifications) async {
    final failure = failSchedule;
    await scheduleGate?.future;
    if (failure) throw PlatformException(code: 'schedule_failed');
  }

  @override
  Future<void> cancelAll() async {
    if (failCancel) throw PlatformException(code: 'cancel_failed');
  }
}

void main() {
  late SettingsCubit cubit;
  late _Notifications notifications;
  setUp(() async {
    notifications = _Notifications();
    cubit = SettingsCubit(
      storage: _Storage(),
      locationService: LocationService(),
      notifications: notifications,
    );
    await cubit.load();
  });
  tearDown(() => cubit.close());

  test(
    'failed activation reports failure and resume retry clears it',
    () async {
      notifications.failSchedule = true;
      expect(await cubit.setNotificationsEnabled(true), isFalse);
      expect(cubit.state.status, SettingsStatus.failure);
      expect(cubit.state.settings.notificationsEnabled, isTrue);
      notifications.failSchedule = false;
      await cubit.refreshNotificationSchedule();
      expect(cubit.state.status, SettingsStatus.ready);
      expect(cubit.state.message, isNull);
    },
  );

  test(
    'permission and cancellation exceptions return failure without escaping',
    () async {
      notifications.failPermission = true;
      expect(await cubit.setNotificationsEnabled(true), isFalse);
      expect(cubit.state.settings.notificationsEnabled, isFalse);
      expect(cubit.state.status, SettingsStatus.failure);
      notifications.failPermission = false;
      expect(await cubit.setNotificationsEnabled(true), isTrue);
      notifications.failCancel = true;
      expect(await cubit.setNotificationsEnabled(false), isFalse);
      expect(cubit.state.message, contains('تعذّر إيقاف'));
    },
  );

  test('late scheduling error cannot overwrite a successful disable', () async {
    notifications.failSchedule = true;
    final gate = notifications.scheduleGate = Completer<void>();
    final enabling = cubit.setNotificationsEnabled(true);
    await Future<void>.delayed(Duration.zero);
    expect(await cubit.setNotificationsEnabled(false), isTrue);
    final disabled = cubit.state;
    gate.complete();
    expect(await enabling, isFalse);
    expect(cubit.state, disabled);
    expect(cubit.state.message, isNull);
  });

  test(
    'older failure cannot overwrite a newer retry with identical settings',
    () async {
      notifications.failSchedule = true;
      final gate = notifications.scheduleGate = Completer<void>();
      final older = cubit.setNotificationsEnabled(true);
      await Future<void>.delayed(Duration.zero);
      notifications.scheduleGate = null;
      notifications.failSchedule = false;
      expect(await cubit.setNotificationsEnabled(true), isTrue);
      final recovered = cubit.state;
      gate.complete();
      expect(await older, isFalse);
      expect(cubit.state, recovered);
    },
  );
}
