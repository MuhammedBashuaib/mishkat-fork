import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
  const native = MethodChannel('com.dakomn.mishkatapp/adhan');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var failInitialize = false;
  var failExact = false;
  var failSchedule = false;
  Completer<void>? initializeGate;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    failInitialize = failExact = failSchedule = false;
    initializeGate = null;
    messenger.setMockMethodCallHandler(native, (_) async => null);
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          await initializeGate?.future;
          if (failInitialize) {
            throw PlatformException(code: 'initialization_failed');
          }
          return defaultTargetPlatform != TargetPlatform.iOS;
        case 'requestNotificationsPermission':
        case 'requestPermissions':
          return true;
        case 'canScheduleExactNotifications':
        case 'requestExactAlarmsPermission':
          if (failExact) throw PlatformException(code: 'unavailable');
          return true;
        case 'pendingNotificationRequests':
          return [
            {'id': 400001, 'title': 'existing'},
            {'id': 400002, 'title': 'disabled'},
            {'id': 800002, 'title': 'unrelated'},
          ];
        case 'zonedSchedule':
          if (failSchedule) throw PlatformException(code: 'schedule_failed');
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(native, null);
  });

  ScheduledAppNotification reminder() => ScheduledAppNotification(
    id: 400001,
    title: 'تذكير',
    body: 'ذكر الله',
    at: DateTime.now().add(const Duration(hours: 1)),
    repeatsDaily: true,
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform retries failed startup initialization before enabling',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        if (platform == TargetPlatform.iOS) {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        }
        final service = LocalNotificationService();
        failInitialize = true;
        await expectLater(
          service.initialize(),
          throwsA(isA<PlatformException>()),
        );
        failInitialize = false;
        expect(await service.requestPermission(), isTrue);
        await service.scheduleAll([reminder()]);
        expect(calls.where((c) => c.method == 'initialize'), hasLength(2));
        expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(1));
      },
    );

    test(
      '$platform failed upsert preserves matching and unrelated pending reminders',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        if (platform == TargetPlatform.iOS) {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        }
        failSchedule = true;
        final service = LocalNotificationService();
        await expectLater(
          service.scheduleAll([reminder()]),
          throwsA(isA<PlatformException>()),
        );
        expect(
          calls
              .where((c) => c.method == 'cancel')
              .map((c) => c.arguments is int ? c.arguments : c.arguments['id']),
          [400002],
        );
        failSchedule = false;
        await service.scheduleAll([reminder()]);
        expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(2));
      },
    );
  }

  test('concurrent initialization shares one native request', () async {
    initializeGate = Completer<void>();
    final service = LocalNotificationService();
    final first = service.initialize();
    final second = service.initialize();
    await Future<void>.delayed(Duration.zero);
    initializeGate!.complete();
    await Future.wait([first, second]);
    await service.initialize();
    expect(calls.where((c) => c.method == 'initialize'), hasLength(1));
  });

  test('optional exact alarm failure still allows inexact reminders', () async {
    failExact = true;
    final service = LocalNotificationService();
    expect(await service.requestPermission(), isTrue);
    await service.scheduleAll([reminder()]);
    final scheduled = calls.singleWhere((c) => c.method == 'zonedSchedule');
    expect(
      scheduled.arguments['platformSpecifics']['scheduleMode'],
      'inexactAllowWhileIdle',
    );
  });

  test(
    'native adhan failure preserves active and unrelated plugin reminders',
    () async {
      messenger.setMockMethodCallHandler(native, (_) async {
        throw PlatformException(code: 'native_replace_failed');
      });
      await expectLater(
        LocalNotificationService().scheduleAll([reminder()]),
        throwsA(isA<PlatformException>()),
      );
      expect(
        calls.where((c) => c.method == 'cancel').map((c) => c.arguments['id']),
        [400002],
      );
    },
  );
}
