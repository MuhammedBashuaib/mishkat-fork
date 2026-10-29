import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Carries notification taps from the native callback to [AppShell], including
/// taps that launched the application from a terminated state.
final ValueNotifier<String?> notificationTapPayload = ValueNotifier(null);

class LocalNotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _canUseExactAlarms = false;

  Future<void> initialize() async {
    if (kIsWeb) return;
    tz_data.initializeTimeZones();
    try {
      final deviceTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimeZone.identifier));
    } on Object {
      // One-shot alarms still use the correct instant. Only daily repetition
      // falls back to UTC on an unusually configured device.
    }
    const initialization = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_mishkat'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(
      initialization,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload?.trim();
        if (payload != null && payload.isNotEmpty) {
          notificationTapPayload.value = payload;
        }
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launch?.notificationResponse?.payload?.trim();
    if (launch?.didNotificationLaunchApp == true &&
        launchPayload != null &&
        launchPayload.isNotEmpty) {
      notificationTapPayload.value = launchPayload;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      _canUseExactAlarms =
          await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.canScheduleExactNotifications() ??
          false;
    }
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notificationsAllowed =
          await android?.requestNotificationsPermission() ?? true;
      if (!notificationsAllowed) return false;
      _canUseExactAlarms =
          await android?.canScheduleExactNotifications() ?? false;
      if (!_canUseExactAlarms) {
        _canUseExactAlarms =
            await android?.requestExactAlarmsPermission() ?? false;
      }
      return true;
    }
    return false;
  }

  Future<void> scheduleAll(List<ScheduledAppNotification> notifications) async {
    if (kIsWeb) return;
    final groups = notifications.map((item) => _groupFor(item.id)).toSet();
    // Prayer, Adhkar, and Khatma form a single recalculated calendar. Always
    // clear all three so disabling one category removes its old alarms too.
    if (groups.any((group) => group >= 1 && group <= 3)) {
      groups.addAll(const [1, 2, 3]);
    }
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (groups.contains(_groupFor(request.id))) {
        await _plugin.cancel(request.id);
      }
    }

    final future =
        notifications.where((item) => item.at.isAfter(DateTime.now())).toList()
          ..sort((a, b) => a.at.compareTo(b.at));
    // iOS accepts at most 64 pending local notifications. Reserve room for
    // repeating Hifz alarms and system/test entries, and keep the nearest ones.
    final limit = defaultTargetPlatform == TargetPlatform.iOS
        ? 58
        : future.length;
    for (final item in future.take(limit)) {
      if (!item.at.isAfter(DateTime.now())) continue;
      await _plugin.zonedSchedule(
        item.id,
        item.title,
        item.body,
        tz.TZDateTime.from(item.at, tz.local),
        _detailsFor(item),
        payload: item.payload,
        androidScheduleMode: _canUseExactAlarms
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: item.repeatsDaily
            ? DateTimeComponents.time
            : null,
      );
    }
  }

  int _groupFor(int id) {
    if (id == 800001 || id == 800002) return id;
    if (id >= 100000 && id < 400000) return id ~/ 100000;
    return id;
  }

  Future<void> showTest({
    required bool sound,
    required bool vibrate,
    String? soundName,
  }) {
    final item = ScheduledAppNotification(
      id: 999999,
      title: soundName == null ? 'تنبيه تجريبي' : 'تجربة صوت الأذان',
      body: soundName == null
          ? 'التنبيهات تعمل بنجاح — بارك الله في وقتك.'
          : 'هذا هو الصوت الذي سيعمل عند دخول وقت الصلاة.',
      at: DateTime.now(),
      sound: sound,
      vibrate: vibrate,
      soundName: soundName,
      kind: soundName == null
          ? AppNotificationKind.general
          : AppNotificationKind.adhan,
    );
    return _plugin.show(item.id, item.title, item.body, _detailsFor(item));
  }

  NotificationDetails _detailsFor(ScheduledAppNotification item) {
    final customSound = item.sound && item.soundName != null;
    final androidSoundName = item.soundName;
    // iOS notification sounds are limited to 30 seconds. The bundled CAF
    // files use the base name and contain a 29-second excerpt.
    final iosSoundName = item.soundName?.replaceFirst(RegExp(r'_short$'), '');
    final channelSuffix = !item.sound
        ? 'silent'
        : customSound
        ? item.soundName!
        : 'default';
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'mishkat_${item.kind.name}_$channelSuffix',
        item.kind.channelName,
        channelDescription: item.kind.channelDescription,
        importance: item.kind == AppNotificationKind.adhan
            ? Importance.max
            : Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        playSound: item.sound,
        sound: customSound
            ? RawResourceAndroidNotificationSound(androidSoundName!)
            : null,
        enableVibration: item.vibrate,
      ),
      iOS: DarwinNotificationDetails(
        presentSound: item.sound,
        sound: customSound ? '$iosSoundName.caf' : null,
        interruptionLevel: item.kind == AppNotificationKind.adhan
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}

class ScheduledAppNotification {
  const ScheduledAppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    this.payload,
    this.sound = true,
    this.vibrate = true,
    this.soundName,
    this.repeatsDaily = false,
    this.kind = AppNotificationKind.general,
  });
  final int id;
  final String title;
  final String body;
  final DateTime at;
  final String? payload;
  final bool sound;
  final bool vibrate;
  final String? soundName;
  final bool repeatsDaily;
  final AppNotificationKind kind;
}

enum AppNotificationKind {
  adhan('مواقيت الصلاة', 'تنبيهات الأذان عند دخول وقت الصلاة'),
  prayerReminder('تذكير الصلاة', 'تنبيهات الاستعداد قبل دخول وقت الصلاة'),
  adhkar('الأذكار اليومية', 'تذكير أذكار الصباح والمساء'),
  khatma('ورد الختمة', 'تذكير الورد اليومي لختمة القرآن'),
  memorization('الحفظ والمراجعة', 'تذكير خطة الحفظ والمراجعة اليومية'),
  general('تنبيهات مشكاة', 'تنبيهات تطبيق مشكاة');

  const AppNotificationKind(this.channelName, this.channelDescription);
  final String channelName;
  final String channelDescription;
}
