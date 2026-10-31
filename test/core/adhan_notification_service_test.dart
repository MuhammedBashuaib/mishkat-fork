import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/features/settings/data/models/adhan_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
  const native = MethodChannel('com.dakomn.mishkatapp/adhan');
  final calls = <MethodCall>[];
  final pluginCalls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    tz_data.initializeTimeZones();
    calls.clear();
    pluginCalls.clear();
    messenger.setMockMethodCallHandler(plugin, (call) async {
      pluginCalls.add(call);
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'canScheduleExactNotifications') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(native, null);
  });

  ScheduledAppNotification prayer({
    bool sound = true,
    String name = 'adhan2',
  }) => ScheduledAppNotification(
    id: 100001,
    title: 'الفجر',
    body: 'حي على الصلاة',
    at: DateTime.now().add(const Duration(hours: 1)),
    sound: sound,
    soundName: sound ? name : null,
    vibrate: false,
    payload: 'prayer:fajr',
    kind: AppNotificationKind.adhan,
  );

  test(
    'full and short adhan use persisted native playback, never duplicate sound',
    () async {
      final service = LocalNotificationService();
      for (final voice in AdhanVoice.voices) {
        for (final mode in AdhanPlaybackMode.values) {
          final name = voice.soundName(mode);
          await service.scheduleAll([prayer(name: name)]);
          final item = (calls.last.arguments as List).single as Map;
          expect(item['soundName'], name);
          expect(item['vibrate'], false);
          expect(item['payload'], 'prayer:fajr');
        }
      }
      expect(
        pluginCalls.where((call) => call.method == 'zonedSchedule'),
        isEmpty,
      );
    },
  );

  test(
    'muted prayers remove old native alarms and keep a silent notification',
    () async {
      await LocalNotificationService().scheduleAll([prayer(sound: false)]);
      expect(calls.single.method, 'replace');
      expect(calls.single.arguments, isEmpty);
      final schedule = pluginCalls.singleWhere(
        (call) => call.method == 'zonedSchedule',
      );
      expect(schedule.arguments['platformSpecifics']['playSound'], false);
    },
  );

  test('test playback and stop use the same native player', () async {
    final service = LocalNotificationService();
    await service.showTest(
      sound: true,
      vibrate: false,
      soundName: 'adhan4_short',
    );
    expect(calls.single.method, 'play');
    expect(calls.single.arguments['soundName'], 'adhan4_short');
    expect(pluginCalls.where((call) => call.method == 'show'), isEmpty);
    await service.stopTest();
    expect(calls.last.method, 'stop');
  });

  test(
    'turning notifications off waits for an in-flight calendar replacement',
    () async {
      final gate = Completer<void>();
      messenger.setMockMethodCallHandler(native, (call) async {
        calls.add(call);
        if (call.method == 'replace') await gate.future;
        return null;
      });
      final service = LocalNotificationService();
      final scheduling = service.scheduleAll([prayer()]);
      await Future<void>.delayed(Duration.zero);
      final cancelling = service.cancelAll();
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method), ['replace']);
      gate.complete();
      await Future.wait([scheduling, cancelling]);
      expect(calls.map((call) => call.method), ['replace', 'cancelAll']);
      expect(pluginCalls.last.method, 'cancelAll');
    },
  );

  test('failed replacement does not poison later calendar updates', () async {
    var fail = true;
    messenger.setMockMethodCallHandler(native, (call) async {
      if (fail) throw PlatformException(code: 'test');
      calls.add(call);
      return null;
    });
    final service = LocalNotificationService();
    await expectLater(
      service.scheduleAll([prayer()]),
      throwsA(isA<PlatformException>()),
    );
    fail = false;
    await service.scheduleAll([prayer(name: 'adhan1_short')]);
    expect(calls.single.arguments[0]['soundName'], 'adhan1_short');
  });

  test('iOS uses the bundled short CAF for either requested mode', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    final service = LocalNotificationService();
    for (final mode in AdhanPlaybackMode.values) {
      await service.showTest(
        sound: true,
        vibrate: true,
        soundName: AdhanVoice.voices.last.soundName(mode),
      );
      final details = pluginCalls.last.arguments['platformSpecifics'] as Map;
      expect(details['sound'], 'adhan4.caf');
      expect(details['presentSound'], true);
    }
    expect(calls, isEmpty);
  });

  test(
    'all selectable native sounds are packaged and preserved in release',
    () {
      final keep = File('android/app/src/main/res/raw/keep.xml')
          .readAsStringSync();
      final project = File('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      for (final voice in AdhanVoice.voices) {
        for (final mode in AdhanPlaybackMode.values) {
          final name = voice.soundName(mode);
          expect(
            File('android/app/src/main/res/raw/$name.mp3').lengthSync(),
            greaterThan(10000),
          );
          expect(keep, contains('@raw/$name'));
        }
        final file = File('ios/Runner/Sounds/${voice.id}.caf');
        expect(file.lengthSync(), greaterThan(10000));
        expect(project, contains('${voice.id}.caf in Resources'));
      }
    },
  );
}
