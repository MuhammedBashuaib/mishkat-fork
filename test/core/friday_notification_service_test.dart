import 'dart:async';

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
  final pluginCalls = <MethodCall>[];
  final nativeCalls = <MethodCall>[];
  var exactAllowed = true;
  var deviceZone = 'Asia/Aden';

  setUp(() {
    tz_data.initializeTimeZones();
    exactAllowed = true;
    deviceZone = 'Asia/Aden';
    pluginCalls.clear();
    nativeCalls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(plugin, (call) async {
      pluginCalls.add(call);
      if (call.method == 'canScheduleExactNotifications') return exactAllowed;
      if (call.method == 'pendingNotificationRequests') return [];
      return null;
    });
    messenger.setMockMethodCallHandler(timezone, (_) async => deviceZone);
    messenger.setMockMethodCallHandler(native, (call) async {
      nativeCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(timezone, null);
    messenger.setMockMethodCallHandler(native, null);
  });

  ScheduledAppNotification friday({int id = 500000, String body = ''}) {
    final zone = tz.getLocation(deviceZone);
    final now = tz.TZDateTime.now(zone);
    var date = tz.TZDateTime(
      zone,
      now.year,
      now.month,
      now.day + (DateTime.friday - now.weekday + 7) % 7,
      9,
    );
    if (!date.isAfter(now)) {
      date = tz.TZDateTime(zone, date.year, date.month, date.day + 7, 9);
    }
    return ScheduledAppNotification(
      id: id,
      title: 'سورة الكهف',
      body: body,
      at: date,
      payload: 'quran:kahf',
      sound: false,
      vibrate: false,
      repeatsWeekly: true,
      kind: AppNotificationKind.friday,
    );
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform repeats Friday reminders by weekday and local time',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        if (platform == TargetPlatform.iOS) {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        }
        final reminder = friday();
        await LocalNotificationService().scheduleAll([reminder]);
        final scheduled = pluginCalls.singleWhere(
          (call) => call.method == 'zonedSchedule',
        );
        expect(reminder.at.weekday, DateTime.friday);
        expect(scheduled.arguments['timeZoneName'], 'Asia/Aden');
        expect(scheduled.arguments['scheduledDateTime'], contains('T09:00:00'));
        expect(
          scheduled.arguments['matchDateTimeComponents'],
          DateTimeComponents.dayOfWeekAndTime.index,
        );
        expect(scheduled.arguments['payload'], 'quran:kahf');
        final specifics = scheduled.arguments['platformSpecifics'] as Map;
        if (platform == TargetPlatform.android) {
          expect(specifics['playSound'], isFalse);
          expect(specifics['enableVibration'], isFalse);
          expect(specifics['channelId'], contains('friday_silent'));
        } else {
          expect(specifics['presentSound'], isFalse);
        }
      },
    );
  }

  test(
    'weekly requests use the latest device timezone after returning',
    () async {
      final service = LocalNotificationService();
      await service.scheduleAll([friday()]);
      deviceZone = 'America/New_York';
      await service.scheduleAll([friday()]);
      final scheduled = pluginCalls
          .where((call) => call.method == 'zonedSchedule')
          .toList();
      expect(scheduled.first.arguments['timeZoneName'], 'Asia/Aden');
      expect(scheduled.last.arguments['timeZoneName'], 'America/New_York');
      expect(
        scheduled.last.arguments['scheduledDateTime'],
        contains('T09:00:00'),
      );
    },
  );

  test(
    'weekly reminders still schedule without exact alarm permission',
    () async {
      exactAllowed = false;
      await LocalNotificationService().scheduleAll([friday()]);
      final scheduled = pluginCalls.singleWhere(
        (call) => call.method == 'zonedSchedule',
      );
      expect(
        scheduled.arguments['platformSpecifics']['scheduleMode'],
        'inexactAllowWhileIdle',
      );
      expect(
        scheduled.arguments['matchDateTimeComponents'],
        DateTimeComponents.dayOfWeekAndTime.index,
      );
    },
  );

  test(
    'revoking exact permission during a calendar update keeps reminders',
    () async {
      messenger.setMockMethodCallHandler(plugin, (call) async {
        pluginCalls.add(call);
        if (call.method == 'canScheduleExactNotifications') return true;
        if (call.method == 'pendingNotificationRequests') return [];
        if (call.method == 'zonedSchedule' &&
            call.arguments['platformSpecifics']['scheduleMode'] ==
                'exactAllowWhileIdle') {
          throw PlatformException(code: 'exact_alarms_not_permitted');
        }
        return null;
      });
      await LocalNotificationService().scheduleAll([
        friday(),
        friday(id: 500001),
      ]);
      final scheduled = pluginCalls
          .where((call) => call.method == 'zonedSchedule')
          .toList();
      expect(scheduled, hasLength(3));
      expect(
        scheduled.map(
          (call) => call.arguments['platformSpecifics']['scheduleMode'],
        ),
        [
          'exactAllowWhileIdle',
          'inexactAllowWhileIdle',
          'inexactAllowWhileIdle',
        ],
      );
      expect(scheduled.last.arguments['id'], 500001);
    },
  );

  test(
    'native adhan shares the total alarm budget and preserves Friday reminders',
    () async {
      messenger.setMockMethodCallHandler(plugin, (call) async {
        pluginCalls.add(call);
        if (call.method == 'canScheduleExactNotifications') return true;
        if (call.method == 'pendingNotificationRequests') {
          return [
            for (var index = 0; index < 12; index++)
              {'id': 900000 + index, 'title': '', 'body': '', 'payload': ''},
          ];
        }
        return null;
      });
      final now = DateTime.now();
      await LocalNotificationService().scheduleAll([
        for (var index = 0; index < 450; index++)
          ScheduledAppNotification(
            id: 100001 + index,
            title: 'الأذان',
            body: '',
            at: now.add(Duration(minutes: index + 1)),
            soundName: 'adhan1',
            kind: AppNotificationKind.adhan,
          ),
        for (var index = 0; index < 20; index++)
          ScheduledAppNotification(
            id: 200001 + index,
            title: 'تذكير',
            body: '',
            at: now.add(Duration(hours: index + 24)),
          ),
        for (var index = 0; index < 9; index++) friday(id: 500000 + index),
      ]);
      expect(nativeCalls.single.arguments, hasLength(429));
      final scheduled = pluginCalls
          .where((call) => call.method == 'zonedSchedule')
          .toList();
      expect(scheduled, hasLength(9));
      expect(
        scheduled.map((call) => call.arguments['id']),
        everyElement(inInclusiveRange(500000, 500008)),
      );
      expect(
        (nativeCalls.single.arguments as List).length + scheduled.length + 12,
        450,
      );
    },
  );

  for (final weekly in [false, true]) {
    test(
      'elapsed ${weekly ? 'weekly' : 'daily'} reminders retain their next occurrence',
      () async {
        final zone = tz.getLocation(deviceZone);
        final now = tz.TZDateTime.now(zone);
        final elapsed = tz.TZDateTime.from(
          now.subtract(const Duration(minutes: 1)),
          zone,
        );
        final reminder = ScheduledAppNotification(
          id: 500000,
          title: 'تذكير',
          body: '',
          at: elapsed,
          repeatsDaily: !weekly,
          repeatsWeekly: weekly,
        );
        await LocalNotificationService().scheduleAll([
          reminder,
          ScheduledAppNotification(
            id: 100000,
            title: '',
            body: '',
            at: DateTime(1970),
          ),
          ScheduledAppNotification(
            id: 100001,
            title: 'تذكير منتهٍ',
            body: '',
            at: elapsed,
          ),
        ]);
        final call = pluginCalls.singleWhere(
          (call) => call.method == 'zonedSchedule',
        );
        final actual = DateTime.parse(
          call.arguments['scheduledDateTime'] as String,
        );
        final expected = tz.TZDateTime(
          zone,
          elapsed.year,
          elapsed.month,
          elapsed.day + (weekly ? 7 : 1),
          elapsed.hour,
          elapsed.minute,
          elapsed.second,
        );
        expect(
          [
            actual.year,
            actual.month,
            actual.day,
            actual.hour,
            actual.minute,
            actual.second,
          ],
          [
            expected.year,
            expected.month,
            expected.day,
            expected.hour,
            expected.minute,
            expected.second,
          ],
        );
        expect(expected.isAfter(now), isTrue);
        expect(reminder.at, same(elapsed));
        expect(reminder.at.isBefore(now), isTrue);
        expect(call.arguments['id'], 500000);
        expect(
          call.arguments['matchDateTimeComponents'],
          (weekly
                  ? DateTimeComponents.dayOfWeekAndTime
                  : DateTimeComponents.time)
              .index,
        );
      },
    );
  }

  test(
    'elapsed recurrence preserves wall clock across a DST offset change',
    () async {
      deviceZone = 'America/New_York';
      final zone = tz.getLocation(deviceZone);
      final now = tz.TZDateTime.now(zone);
      final winter = tz.TZDateTime(zone, now.year - 1, 1, 3, 9, 7);
      final summer = tz.TZDateTime(zone, now.year - 1, 7, 3, 9, 7);
      final source = winter.timeZoneOffset != now.timeZoneOffset
          ? winter
          : summer;
      expect(source.timeZoneOffset, isNot(now.timeZoneOffset));
      for (final weekly in [false, true]) {
        await LocalNotificationService().scheduleAll([
          ScheduledAppNotification(
            id: 500000,
            title: 'تذكير',
            body: '',
            at: source,
            repeatsWeekly: weekly,
            repeatsDaily: !weekly,
          ),
        ]);
        final call = pluginCalls.lastWhere(
          (call) => call.method == 'zonedSchedule',
        );
        final actual = DateTime.parse(
          call.arguments['scheduledDateTime'] as String,
        );
        expect(actual.hour, 9);
        expect(actual.minute, 7);
        expect(call.arguments['timeZoneName'], deviceZone);
        if (weekly) expect(actual.weekday, source.weekday);
        final next = tz.TZDateTime(
          zone,
          actual.year,
          actual.month,
          actual.day,
          actual.hour,
          actual.minute,
        );
        expect(next.isAfter(now), isTrue);
        expect(next.difference(now), lessThan(const Duration(days: 8)));
      }
    },
  );

  test('updated requests with the same ID are scheduled once', () async {
    await LocalNotificationService().scheduleAll([
      friday(body: 'old'),
      friday(body: 'new'),
    ]);
    final scheduled = pluginCalls.singleWhere(
      (call) => call.method == 'zonedSchedule',
    );
    expect(scheduled.arguments['body'], 'new');
  });

  test(
    'queued calendar captures its request list before a caller changes it',
    () async {
      final entered = Completer<void>();
      final gate = Completer<void>();
      var pendingReads = 0;
      messenger.setMockMethodCallHandler(plugin, (call) async {
        pluginCalls.add(call);
        if (call.method == 'canScheduleExactNotifications') return true;
        if (call.method == 'pendingNotificationRequests') {
          if (pendingReads++ == 0) {
            entered.complete();
            await gate.future;
          }
          return [];
        }
        return null;
      });
      final service = LocalNotificationService();
      final first = service.scheduleAll([friday()]);
      await entered.future;
      final next = [friday(id: 500001)];
      final queued = service.scheduleAll(next);
      next.clear();
      gate.complete();
      await Future.wait([first, queued]);
      expect(
        pluginCalls
            .where((call) => call.method == 'zonedSchedule')
            .map((call) => call.arguments['id']),
        [500000, 500001],
      );
    },
  );

  test('switching alerts off cancels plugin reminders if native cancellation fails', () async {
    messenger.setMockMethodCallHandler(native, (_) async {
      throw PlatformException(code: 'native_cancel_failed');
    });
    await expectLater(
      LocalNotificationService().cancelAll(),
      throwsA(isA<PlatformException>()),
    );
    expect(pluginCalls.single.method, 'cancelAll');
  });
}
