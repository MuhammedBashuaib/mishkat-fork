import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/settings/presentation/widgets/notification_permission_flow.dart';

import 'quran_bookmarks_test.dart' show InMemoryLocalStorageService;

class _Notifications extends LocalNotificationService {
  bool granted = true;
  bool failSchedule = false;
  bool settingsOpened = true;
  int requests = 0;
  int settingsOpens = 0;
  int permissionChecks = 0;
  int testNotifications = 0;
  List<ScheduledAppNotification> scheduled = [];
  Completer<bool>? permissionGate;

  @override
  Future<bool> requestPermission() async {
    requests++;
    return permissionGate?.future ?? granted;
  }

  @override
  Future<bool> isPermissionGranted() async {
    permissionChecks++;
    return granted;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpens++;
    return settingsOpened;
  }

  @override
  Future<bool> canSchedulePrecisely() async => true;
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> showTest({
    required bool sound,
    required bool vibrate,
    String? soundName,
  }) async {
    testNotifications++;
  }

  @override
  Future<void> scheduleAll(List<ScheduledAppNotification> items) async {
    if (failSchedule) throw StateError('calendar failed');
    scheduled = items;
  }
}

class _Host extends StatefulWidget {
  const _Host(this.storage, {this.firstLaunch = true});
  final LocalStorageService storage;
  final bool firstLaunch;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    if (widget.firstLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationPermissionFlow.showOnFirstLaunch(context, widget.storage);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () => NotificationPermissionFlow.ensureEnabled(context),
          child: const Text('ensure'),
        ),
        TextButton(
          onPressed: () => NotificationPermissionFlow.testNotification(context),
          child: const Text('test'),
        ),
        TextButton(
          onPressed: () => NotificationPermissionFlow.enable(context),
          child: const Text('feature'),
        ),
        TextButton(
          onPressed: () => NotificationPermissionFlow.showOnFirstLaunch(
            context,
            widget.storage,
          ),
          child: const Text('reopen'),
        ),
        TextButton(
          onPressed: () {
            NotificationPermissionFlow.enable(context);
            NotificationPermissionFlow.enable(context);
          },
          child: const Text('double'),
        ),
      ],
    ),
  );
}

void main() {
  late InMemoryLocalStorageService storage;
  late SettingsCubit cubit;
  late _Notifications notifications;
  final dialog = find.byKey(const ValueKey('notification-permission-dialog'));
  final enable = find.byKey(const ValueKey('notification-permission-enable'));
  final later = find.byKey(const ValueKey('notification-permission-later'));
  final settings = find.byKey(
    const ValueKey('notification-permission-settings'),
  );

  setUp(() {
    storage = InMemoryLocalStorageService();
    notifications = _Notifications();
    cubit = SettingsCubit(
      storage: storage,
      locationService: LocationService(),
      notifications: notifications,
    );
  });
  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester, {bool firstLaunch = true}) async {
    await cubit.load();
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: _Host(storage, firstLaunch: firstLaunch),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'fresh launch asks once, consent activates every default category',
    (tester) async {
      await pump(tester);
      expect(dialog, findsOneWidget);
      expect(notifications.requests, 0);
      expect(cubit.state.settings.notificationsEnabled, false);
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(notifications.requests, 1);
      final value = cubit.state.settings;
      expect(value.notificationsEnabled, true);
      expect(value.prayerNotifications.values, everyElement(isTrue));
      expect(value.prayerAdhanEnabled.values, everyElement(isTrue));
      expect(value.adhanSound, true);
      expect(value.adhkarNotifications, true);
      expect(value.reminders.charityEnabled, true);
      expect(value.reminders.dhikrEnabled, true);
      expect(value.reminders.dailyWirdEnabled, true);
      expect(value.reminders.fridayEnabled, true);
      expect(notifications.scheduled, isNotEmpty);
      await tester.tap(find.text('reopen'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(notifications.requests, 1);
    },
  );

  testWidgets('declining introduction persists without enabling or nagging', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(later);
    await tester.pumpAndSettle();
    expect(storage.readInt(NotificationPermissionFlow.firstLaunchKey), 1);
    expect(cubit.state.settings.notificationsEnabled, false);
    expect(notifications.requests, 0);
    await tester.tap(find.text('reopen'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets('upgrade preserves disabled master and custom reminder choices', (
    tester,
  ) async {
    final saved = const AppSettings().copyWith(
      adhkarNotifications: false,
      prayerNotifications: {
        ...const AppSettings().prayerNotifications,
        'fajr': false,
      },
      reminders: const AppSettings().reminders.copyWith(charityEnabled: false),
    );
    await storage.writeMap('settings', saved.toJson());
    await pump(tester);
    expect(dialog, findsNothing);
    expect(notifications.requests, 0);
    expect(cubit.state.settings, saved);
    await tester.tap(find.text('feature'));
    await tester.pumpAndSettle();
    expect(cubit.state.settings.notificationsEnabled, true);
    expect(cubit.state.settings.adhkarNotifications, false);
    expect(cubit.state.settings.prayerNotifications['fajr'], false);
    expect(cubit.state.settings.reminders.charityEnabled, false);
  });

  testWidgets(
    'completed old onboarding never receives the first launch prompt',
    (tester) async {
      await storage.writeInt('onboarding_version', 1);
      await pump(tester);
      expect(dialog, findsNothing);
      expect(notifications.requests, 0);
    },
  );

  testWidgets('OS denial offers local retry and does not enable master', (
    tester,
  ) async {
    notifications.granted = false;
    await pump(tester);
    await tester.tap(enable);
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
    expect(settings, findsOneWidget);
    expect(cubit.state.settings.notificationsEnabled, false);
    expect(notifications.scheduled, isEmpty);
    notifications.granted = true;
    await tester.tap(enable);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(cubit.state.settings.notificationsEnabled, true);
    expect(notifications.requests, 2);
  });

  testWidgets('feature use detects revoked permission despite enabled master', (
    tester,
  ) async {
    await storage.writeMap(
      'settings',
      const AppSettings(notificationsEnabled: true).toJson(),
    );
    notifications.granted = false;
    await pump(tester, firstLaunch: false);
    await tester.tap(find.text('ensure'));
    await tester.pumpAndSettle();
    expect(notifications.permissionChecks, 1);
    expect(notifications.requests, 1);
    expect(dialog, findsOneWidget);
    expect(settings, findsOneWidget);
  });

  testWidgets(
    'authorized feature and test alert do not repeat permission requests',
    (tester) async {
      await storage.writeMap(
        'settings',
        const AppSettings(notificationsEnabled: true).toJson(),
      );
      await pump(tester, firstLaunch: false);
      await tester.tap(find.text('ensure'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(notifications.requests, 0);
      await tester.tap(find.text('test'));
      await tester.pumpAndSettle();
      expect(notifications.testNotifications, 1);
      expect(notifications.requests, 0);
    },
  );

  testWidgets(
    'resume only rechecks after settings handoff and never nags denial',
    (tester) async {
      notifications.granted = false;
      await pump(tester, firstLaunch: false);
      await tester.tap(find.text('feature'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(notifications.permissionChecks, 0);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(notifications.permissionChecks, 1);
      expect(notifications.requests, 1);
      expect(dialog, findsOneWidget);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      notifications.granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(cubit.state.settings.notificationsEnabled, true);
    },
  );

  testWidgets(
    'schedule failure stays retryable without misleading activation',
    (tester) async {
      notifications.failSchedule = true;
      await pump(tester);
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(settings, findsNothing);
      expect(find.textContaining('تعذّر تحديث التذكيرات'), findsOneWidget);
      notifications.failSchedule = false;
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(notifications.scheduled, isNotEmpty);
    },
  );

  testWidgets('concurrent activation shares one dialog and one OS request', (
    tester,
  ) async {
    final gate = notifications.permissionGate = Completer<bool>();
    await pump(tester, firstLaunch: false);
    await tester.tap(find.text('double'));
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
    expect(notifications.requests, 1);
    expect(tester.widget<TextButton>(later).onPressed, isNull);
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets('permission introduction fits narrow screens with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    await tester.ensureVisible(later);
    await tester.tap(later);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
