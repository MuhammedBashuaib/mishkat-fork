import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  static const _adhan = MethodChannel('com.dakomn.mishkatapp/adhan');
  Future<void> _pendingUpdate = Future.value();

  // Calendar replacement and cancellation must be atomic with respect to other
  // callers (settings, Khatma and Hifz all update the same OS calendar).
  Future<void> _serialize(Future<void> Function() action) {
    final operation = _pendingUpdate.then((_) => action());
    _pendingUpdate = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<bool> canSchedulePrecisely() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    _canUseExactAlarms =
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.canScheduleExactNotifications() ??
        false;
    return _canUseExactAlarms;
  }

  Future<void> initialize() async {
    if (kIsWeb) return;
    tz_data.initializeTimeZones();
    await _refreshTimeZone();
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

  Future<void> _refreshTimeZone() async {
    try {
      final deviceTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimeZone.identifier));
    } on Object {
      // Preserve the last known zone when the platform cannot report one.
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

  Future<void> scheduleAll(List<ScheduledAppNotification> notifications) {
    final snapshot = List<ScheduledAppNotification>.of(notifications);
    return _serialize(() => _scheduleAll(snapshot));
  }

  Future<void> _scheduleAll(
    List<ScheduledAppNotification> notifications,
  ) async {
    if (kIsWeb) return;
    await _refreshTimeZone();
    await canSchedulePrecisely();
    final groups = notifications.map((item) => _groupFor(item.id)).toSet();
    // The unified calendar also clears disabled good-deed reminders.
    if (groups.any((group) => group >= 1 && group <= 5)) {
      groups.addAll(const [1, 2, 3, 4, 5]);
    }
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (groups.contains(_groupFor(request.id))) {
        await _plugin.cancel(request.id);
      }
    }

    // The OS replaces requests by ID. Deduplicate before applying its capacity
    // limit so an updated request cannot occupy two slots in our selection.
    final byId = {for (final item in notifications) item.id: item};
    final future =
        byId.values
            .where(
              (item) =>
                  item.repeatsDaily ||
                  item.repeatsWeekly ||
                  item.at.isAfter(DateTime.now()),
            )
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at));
    final android = defaultTargetPlatform == TargetPlatform.android;
    // Keep recurring reminders before filling the remaining iOS slots with
    // dated prayers. Otherwise a late bedtime/reading reminder can be dropped.
    final retained = pending
        .where((item) => !groups.contains(_groupFor(item.id)))
        .length;
    // Native adhan and plugin alerts share Android's per-app AlarmManager
    // allowance. Reserve recurring reminders first, then fit dated adhan and
    // other alerts within one conservative budget.
    final pluginNotifications = future.where(
      (item) => !android || !_usesNativeAdhan(item),
    );
    final recurring = pluginNotifications
        .where((item) => item.repeatsDaily || item.repeatsWeekly)
        .toList();
    final androidBudget = (450 - retained).clamp(0, 450);
    final nativeAdhan = android
        ? future
              .where(_usesNativeAdhan)
              .take((androidBudget - recurring.length).clamp(0, androidBudget))
              .toList()
        : const <ScheduledAppNotification>[];
    if (android && groups.contains(1)) {
      await _adhan.invokeMethod<void>('replace', [
        for (final item in nativeAdhan) _nativeAdhan(item),
      ]);
    }
    final limit = defaultTargetPlatform == TargetPlatform.iOS
        ? (63 - retained).clamp(0, 58)
        : androidBudget - nativeAdhan.length;
    final selected = [
      ...recurring,
      ...pluginNotifications.where(
        (item) => !item.repeatsDaily && !item.repeatsWeekly,
      ),
    ].take(limit);
    for (final item in selected) {
      await _scheduleNotification(item);
    }
  }

  Future<void> _scheduleNotification(ScheduledAppNotification item) async {
    Future<void> schedule() {
      final at = _nextOccurrence(item);
      if (at == null) return Future.value();
      return _plugin.zonedSchedule(
        item.id,
        item.title,
        item.body,
        at,
        _detailsFor(item),
        payload: item.payload,
        androidScheduleMode: _canUseExactAlarms
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: item.repeatsWeekly
            ? DateTimeComponents.dayOfWeekAndTime
            : item.repeatsDaily
            ? DateTimeComponents.time
            : null,
      );
    }

    try {
      await schedule();
    } on PlatformException catch (error) {
      if (defaultTargetPlatform != TargetPlatform.android ||
          !_canUseExactAlarms ||
          error.code != 'exact_alarms_not_permitted') {
        rethrow;
      }
      // Permission can be revoked after the initial capability check. Keep
      // this reminder and the remaining calendar using Android's fallback.
      _canUseExactAlarms = false;
      await schedule();
    }
  }

  tz.TZDateTime? _nextOccurrence(ScheduledAppNotification item) {
    final now = tz.TZDateTime.now(tz.local);
    final source = tz.TZDateTime.from(item.at, tz.local);
    if (source.isAfter(now)) return source;
    if (!item.repeatsDaily && !item.repeatsWeekly) return null;

    // Calendar replacement can cross a reminder's first due time. Keep its
    // next occurrence instead of losing the recurrence or sending a late burst.
    // Calendar dates preserve wall-clock time across daylight-saving changes.
    final period = item.repeatsWeekly ? 7 : 1;
    final elapsedDays = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(source.year, source.month, source.day)).inDays;
    var days = elapsedDays ~/ period * period;
    while (true) {
      final candidate = tz.TZDateTime(
        tz.local,
        source.year,
        source.month,
        source.day + days,
        source.hour,
        source.minute,
        source.second,
        source.millisecond,
        source.microsecond,
      );
      if (candidate.isAfter(now)) return candidate;
      days += period;
    }
  }

  bool _usesNativeAdhan(ScheduledAppNotification item) =>
      item.kind == AppNotificationKind.adhan &&
      item.sound &&
      item.soundName != null &&
      !item.repeatsDaily &&
      !item.repeatsWeekly;

  Map<String, Object?> _nativeAdhan(ScheduledAppNotification item) => {
    'id': item.id,
    'title': item.title,
    'body': item.body,
    'at': item.at.millisecondsSinceEpoch,
    'soundName': item.soundName,
    'vibrate': item.vibrate,
    'payload': item.payload,
  };

  int _groupFor(int id) {
    if (id == 800001 || id == 800002) return id;
    if (id >= 100000 && id < 600000) return id ~/ 100000;
    return id;
  }

  Future<void> showTest({
    required bool sound,
    required bool vibrate,
    String? soundName,
  }) async {
    if (kIsWeb) return;
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
    if (defaultTargetPlatform == TargetPlatform.android &&
        _usesNativeAdhan(item)) {
      await _adhan.invokeMethod<void>('play', _nativeAdhan(item));
    } else {
      await _plugin.show(item.id, item.title, item.body, _detailsFor(item));
    }
  }

  Future<void> stopTest() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _adhan.invokeMethod<void>('stop');
    }
    await _plugin.cancel(999999);
  }

  NotificationDetails _detailsFor(ScheduledAppNotification item) {
    final customSound = item.sound && item.soundName != null;
    final androidSoundName = item.soundName;
    // iOS notification sounds are limited to 30 seconds. The bundled CAF
    // files use the base name and contain an opening-takbir excerpt under 30 seconds.
    final iosSoundName = item.soundName?.replaceFirst(RegExp(r'_short$'), '');
    final channelSuffix = !item.sound
        ? 'silent'
        : customSound
        ? item.soundName!
        : 'default';
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'mishkat_${item.kind.name}_${channelSuffix}_v2_${item.vibrate}',
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

  Future<void> cancelAll() => _serialize(() async {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _adhan.invokeMethod<void>('cancelAll');
      }
    } finally {
      await _plugin.cancelAll();
    }
  });
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
    this.repeatsWeekly = false,
    this.kind = AppNotificationKind.general,
  }) : assert(!repeatsDaily || !repeatsWeekly);
  final int id;
  final String title;
  final String body;
  final DateTime at;
  final String? payload;
  final bool sound;
  final bool vibrate;
  final String? soundName;
  final bool repeatsDaily;
  final bool repeatsWeekly;
  final AppNotificationKind kind;
}

enum AppNotificationKind {
  adhan('مواقيت الصلاة', 'تنبيهات الأذان عند دخول وقت الصلاة'),
  prayerReminder('تذكير الصلاة', 'تنبيهات الاستعداد قبل دخول وقت الصلاة'),
  adhkar('الأذكار اليومية', 'تذكير أذكار الصباح والمساء والنوم'),
  charity('التذكير بالصدقة', 'تذكير لطيف بالعطاء صباحًا ومساءً'),
  dhikr('ذكر الله', 'تسبيح واستغفار وصلاة على النبي خلال اليوم'),
  friday('تذكيرات الجمعة', 'سورة الكهف والصلاة على النبي والدعاء يوم الجمعة'),
  khatma('ورد الختمة', 'تذكير الورد اليومي لختمة القرآن'),
  memorization('الحفظ والمراجعة', 'تذكير خطة الحفظ والمراجعة اليومية'),
  general('تنبيهات مشكاة', 'تنبيهات تطبيق مشكاة');

  const AppNotificationKind(this.channelName, this.channelDescription);
  final String channelName;
  final String channelDescription;
}
