import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
  const native = MethodChannel('com.dakomn.mishkatapp/adhan');
  const timezone = MethodChannel('flutter_timezone');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var exactAllowed = true;

  setUp(() {
    tz_data.initializeTimeZones();
    calls.clear();
    exactAllowed = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call);
      if (call.method == 'canScheduleExactNotifications') return exactAllowed;
      if (call.method == 'pendingNotificationRequests') {
        return [
          {'id': 300009, 'title': '', 'body': '', 'payload': 'khatma:old'},
          {'id': 800002, 'title': '', 'body': '', 'payload': 'unrelated'},
        ];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(timezone, (_) async => 'Asia/Aden');
    messenger.setMockMethodCallHandler(native, (_) async => null);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(timezone, null);
    messenger.setMockMethodCallHandler(native, null);
  });

  ScheduledAppNotification reminder() {
    final zone = tz.getLocation('Asia/Aden');
    final now = tz.TZDateTime.now(zone);
    return ScheduledAppNotification(
      id: 300000,
      title: 'ورد ختمتي',
      body: 'حان وقت وردك',
      at: tz.TZDateTime(zone, now.year, now.month, now.day + 1, 23, 7),
      payload: 'khatma:custom',
      repeatsDaily: true,
      kind: AppNotificationKind.khatma,
    );
  }

  test(
    'Android schedules the selected local time as an exact daily alarm',
    () async {
      await LocalNotificationService().scheduleAll([reminder()]);
      final call = calls.singleWhere((item) => item.method == 'zonedSchedule');
      expect(call.arguments['timeZoneName'], 'Asia/Aden');
      expect(call.arguments['scheduledDateTime'], contains('T23:07:00'));
      expect(
        call.arguments['matchDateTimeComponents'],
        DateTimeComponents.time.index,
      );
      expect(
        call.arguments['platformSpecifics']['scheduleMode'],
        'exactAllowWhileIdle',
      );
      expect(call.arguments['payload'], 'khatma:custom');
      expect(
        calls
            .where((item) => item.method == 'cancel')
            .map((item) => item.arguments['id']),
        [300009],
      );
    },
  );

  test(
    'Android keeps a daily reminder when exact alarms are unavailable',
    () async {
      exactAllowed = false;
      await LocalNotificationService().scheduleAll([reminder()]);
      final call = calls.singleWhere((item) => item.method == 'zonedSchedule');
      expect(
        call.arguments['platformSpecifics']['scheduleMode'],
        'inexactAllowWhileIdle',
      );
      expect(
        call.arguments['matchDateTimeComponents'],
        DateTimeComponents.time.index,
      );
    },
  );

  test(
    'iOS schedules a daily wall-clock notification with the plan payload',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      await LocalNotificationService().scheduleAll([reminder()]);
      final call = calls.singleWhere((item) => item.method == 'zonedSchedule');
      expect(call.arguments['timeZoneName'], 'Asia/Aden');
      expect(call.arguments['scheduledDateTime'], contains('T23:07:00'));
      expect(
        call.arguments['matchDateTimeComponents'],
        DateTimeComponents.time.index,
      );
      expect(call.arguments['payload'], 'khatma:custom');
    },
  );
}
