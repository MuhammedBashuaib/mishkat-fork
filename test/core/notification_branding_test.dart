import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const adhan = MethodChannel('com.dakomn.mishkatapp/adhan');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    messenger.setMockMethodCallHandler(adhan, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'canScheduleExactNotifications':
          return true;
        case 'pendingNotificationRequests':
          return [];
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(adhan, null);
  });

  test(
    'immediate and scheduled reminders carry both Mishkat notification icons',
    () async {
      final service = LocalNotificationService();
      await service.showTest(sound: false, vibrate: false);
      await service.scheduleAll([
        ScheduledAppNotification(
          id: 400001,
          title: 'تذكير',
          body: 'مشكاة',
          at: DateTime.now().add(const Duration(hours: 1)),
          sound: false,
        ),
      ]);
      for (final method in ['show', 'zonedSchedule']) {
        final details =
            calls
                    .singleWhere((c) => c.method == method)
                    .arguments['platformSpecifics']
                as Map;
        expect(details['icon'], 'ic_stat_mishkat');
        expect(details['largeIcon'], 'ic_mishkat_large');
        expect(
          details['largeIconBitmapSource'],
          const DrawableResourceAndroidBitmap('ic_mishkat_large').source.index,
        );
      }
    },
  );
}
