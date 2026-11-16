// Automated Android device diagnostic. Never used by the production entry point.
// Build with ORG_GRADLE_PROJECT_mishkatDevelopmentBuild=true, install on an
// emulator, grant notifications/exact alarms, then launch the .dev application.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final info = await PackageInfo.fromPlatform();
  if (info.packageName != 'com.dakomn.mishkatapp.dev') {
    throw StateError('Notification smoke tests require the isolated .dev app.');
  }
  final service = LocalNotificationService();
  await service.initialize();
  final android = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (await android?.areNotificationsEnabled() != true) {
    throw StateError(
      'Grant notification permission to the .dev test app first.',
    );
  }
  final exact = await service.canSchedulePrecisely();
  await service.cancelAll();
  final now = DateTime.now();
  await service.scheduleAll([
    ScheduledAppNotification(
      id: 400991,
      title: 'فحص إشعار مشكاة',
      body: 'اختبار الشعار الجديد والتنبيه المجدول في الخلفية',
      at: now.add(const Duration(seconds: 20)),
      sound: false,
      vibrate: false,
      payload: 'charity',
    ),
    ScheduledAppNotification(
      id: 100991,
      title: 'فحص أذان مشكاة',
      body: 'اختبار الأذان المجدول والشعار الجديد',
      at: now.add(const Duration(seconds: 40)),
      soundName: 'adhan1_short',
      vibrate: false,
      payload: 'prayer:fajr',
      kind: AppNotificationKind.adhan,
    ),
  ]);
  final pending = await FlutterLocalNotificationsPlugin()
      .pendingNotificationRequests();
  debugPrint(
    'MISHKAT_NOTIFICATION_SMOKE scheduled exact=$exact plugin=${pending.map((p) => p.id).toList()}',
  );
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Notification smoke test scheduled')),
      ),
    ),
  );
  // Leave the Activity before either alarm fires; the OS must deliver both.
  await Future<void>.delayed(const Duration(seconds: 2));
  await SystemNavigator.pop();
}
