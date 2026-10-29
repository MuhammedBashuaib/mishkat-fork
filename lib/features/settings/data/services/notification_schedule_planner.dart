import '../../../../core/services/local_notification_service.dart';
import '../../../khatma/data/models/khatma_plan.dart';
import '../../../prayer_times/data/services/prayer_calculator.dart';
import '../../../prayer_times/domain/models/prayer_models.dart';
import '../../../quran/data/models/memorization_plan.dart';
import '../../../quran/data/repositories/quran_memorization_repository.dart';
import '../models/app_settings.dart';
import '../models/adhan_preferences.dart';
import '../../../../core/services/local_storage_service.dart';

/// Builds one coherent notification calendar from the user's local data.
///
/// Keeping this planning in one place prevents one feature (for example Hifz)
/// from accidentally replacing the prayer or Khatma alarms.
class NotificationSchedulePlanner {
  const NotificationSchedulePlanner._();

  static const int _prayerBase = 100000;
  static const int _adhkarBase = 200000;
  static const int _dailyAdhkarBase = 290000;
  static const int _khatmaBase = 300000;
  static const int memorizationReminderId = 800001;

  static List<ScheduledAppNotification> build({
    required LocalStorageService storage,
    required AppSettings settings,
    DateTime? now,
    int days = 14,
  }) {
    final current = now ?? DateTime.now();
    final items = <ScheduledAppNotification>[];

    if (settings.hasLocation) {
      _addPrayerBasedNotifications(
        items: items,
        storage: storage,
        settings: settings,
        now: current,
        days: days,
      );
    }

    _addMemorizationReminder(
      items: items,
      storage: storage,
      settings: settings,
      now: current,
    );

    items.sort((a, b) => a.at.compareTo(b.at));
    return items;
  }

  static void _addPrayerBasedNotifications({
    required List<ScheduledAppNotification> items,
    required LocalStorageService storage,
    required AppSettings settings,
    required DateTime now,
    required int days,
  }) {
    const calculator = PrayerCalculator();
    final khatmaPlans = _activeKhatmaPlans(storage);

    for (var day = 0; day < days; day++) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: day));
      final times = calculator.calculate(
        date: date,
        latitude: settings.latitude!,
        longitude: settings.longitude!,
        methodKey: settings.method,
        methodAuto: !settings.methodSet,
        asr: settings.asr,
        highLatitudes: settings.highLatitudes,
        tune: settings.tune,
      );

      var prayerIndex = 0;
      for (final prayer in PrayerCalculator.order.where(
        (item) => !item.noAdhan,
      )) {
        final at = times[prayer.key];
        final enabled = settings.prayerNotifications[prayer.key] == true;
        final adhanEnabled =
            settings.adhanSound &&
            settings.prayerAdhanEnabled[prayer.key] == true;
        if (at != null && enabled) {
          if (settings.preMinutes > 0) {
            final reminderAt = at.subtract(
              Duration(minutes: settings.preMinutes),
            );
            if (reminderAt.isAfter(now)) {
              items.add(
                ScheduledAppNotification(
                  id: _prayerBase + day * 20 + prayerIndex * 2,
                  title: 'اقتربت صلاة ${prayer.name}',
                  body: 'بقي ${settings.preMinutes} دقيقة على الأذان.',
                  at: reminderAt,
                  payload: 'prayer:${prayer.key}:pre',
                  sound: true,
                  vibrate: settings.vibrate,
                  kind: AppNotificationKind.prayerReminder,
                ),
              );
            }
          }
          if (at.isAfter(now)) {
            final place = settings.city.trim();
            items.add(
              ScheduledAppNotification(
                id: _prayerBase + day * 20 + prayerIndex * 2 + 1,
                title: 'حان الآن موعد صلاة ${prayer.name}',
                body: place.isEmpty
                    ? 'حيّ على الصلاة — تقبّل الله طاعتك.'
                    : '$place — حيّ على الصلاة، حيّ على الفلاح.',
                at: at,
                payload: 'prayer:${prayer.key}',
                sound: adhanEnabled,
                vibrate: settings.vibrate,
                soundName: adhanEnabled
                    ? AdhanVoice.byId(settings.adhanFile)
                          .soundName(settings.adhanPlaybackMode)
                    : null,
                kind: AppNotificationKind.adhan,
              ),
            );
          }
        }
        prayerIndex++;
      }

      if (settings.adhkarNotifications) {
        final morning = times['sunrise']?.add(const Duration(minutes: 30));
        final evening = times['asr']?.add(const Duration(minutes: 30));
        if (morning != null && morning.isAfter(now)) {
          items.add(
            ScheduledAppNotification(
              id: _adhkarBase + day * 10,
              title: _pick(_morningTitles, date),
              body: _pick(_morningBodies, date),
              at: morning,
              payload: 'adhkar:1',
              sound: true,
              vibrate: settings.vibrate,
              kind: AppNotificationKind.adhkar,
            ),
          );
        }
        if (evening != null && evening.isAfter(now)) {
          items.add(
            ScheduledAppNotification(
              id: _adhkarBase + day * 10 + 1,
              title: _pick(_eveningTitles, date),
              body: _pick(_eveningBodies, date),
              at: evening,
              payload: 'adhkar:133',
              sound: true,
              vibrate: settings.vibrate,
              kind: AppNotificationKind.adhkar,
            ),
          );
        }
        if (day == 0) {
          _addRecurringDailyAdhkar(
            items: items,
            times: times,
            now: now,
            vibrate: settings.vibrate,
          );
        }
      }

      for (var planIndex = 0; planIndex < khatmaPlans.length; planIndex++) {
        final plan = khatmaPlans[planIndex];
        final prayer = plan.reminderPrayer;
        final prayerTime = prayer == null ? null : times[prayer];
        if (prayerTime == null) continue;
        final at = prayerTime.add(const Duration(minutes: 15));
        if (!at.isAfter(now)) continue;
        items.add(
          ScheduledAppNotification(
            id: _khatmaBase + day * 100 + planIndex,
            title: 'ورد ${plan.name}',
            body:
                'ورد اليوم ${plan.dailyPages} صفحة — من صفحة '
                '${plan.nextPage} إلى ${plan.todayEnd}.',
            at: at,
            payload: 'khatma:${plan.id}',
            sound: true,
            vibrate: settings.vibrate,
            kind: AppNotificationKind.khatma,
          ),
        );
      }
    }
  }

  static void _addRecurringDailyAdhkar({
    required List<ScheduledAppNotification> items,
    required PrayerTimes times,
    required DateTime now,
    required bool vibrate,
  }) {
    final wakeSource = times['fajr']?.add(const Duration(minutes: 20));
    final daytimeSource = times['dhuhr']?.add(const Duration(minutes: 75));
    final sleepSource = times['isha']?.add(const Duration(minutes: 90));
    final seedDate = DateTime(now.year, now.month, now.day);

    if (wakeSource != null) {
      items.add(
        ScheduledAppNotification(
          id: _dailyAdhkarBase,
          title: _pick(_wakeTitles, seedDate),
          body: _pick(_wakeBodies, seedDate),
          at: _nextDailyOccurrence(wakeSource, now),
          payload: 'adhkar:3',
          vibrate: vibrate,
          repeatsDaily: true,
          kind: AppNotificationKind.adhkar,
        ),
      );
    }
    if (daytimeSource != null) {
      final useIstighfar = _daySeed(seedDate).isOdd;
      items.add(
        ScheduledAppNotification(
          id: _dailyAdhkarBase + 1,
          title: _pick(_daytimeTitles, seedDate),
          body: _pick(_daytimeBodies, seedDate),
          at: _nextDailyOccurrence(daytimeSource, now),
          payload: useIstighfar ? 'adhkar:129' : 'adhkar:130',
          vibrate: vibrate,
          repeatsDaily: true,
          kind: AppNotificationKind.adhkar,
        ),
      );
    }
    if (sleepSource != null) {
      items.add(
        ScheduledAppNotification(
          id: _dailyAdhkarBase + 2,
          title: _pick(_sleepTitles, seedDate),
          body: _pick(_sleepBodies, seedDate),
          at: _nextDailyOccurrence(sleepSource, now),
          payload: 'adhkar:2',
          vibrate: vibrate,
          repeatsDaily: true,
          kind: AppNotificationKind.adhkar,
        ),
      );
    }
  }

  static DateTime _nextDailyOccurrence(DateTime source, DateTime now) {
    var result = DateTime(
      now.year,
      now.month,
      now.day,
      source.hour,
      source.minute,
    );
    if (!result.isAfter(now)) result = result.add(const Duration(days: 1));
    return result;
  }

  static String _pick(List<String> values, DateTime date) =>
      values[_daySeed(date) % values.length];

  static int _daySeed(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(2020)).inDays.abs();

  static const _wakeTitles = [
    'استيقظ على ذكر الله',
    'صباحٌ بنعمة الله',
    'ابدأ يومك بالحمد',
  ];
  static const _wakeBodies = [
    'الحمد لله الذي أحيانا بعدما أماتنا وإليه النشور.',
    'احمد الله على يوم جديد، ثم اقرأ أذكار الاستيقاظ.',
    'دقائق يسيرة من أذكار الاستيقاظ تفتح يومك بالطمأنينة.',
  ];
  static const _morningTitles = [
    'عطّر صباحك بذكر الله',
    'حصّن صباحك',
    'ورد الصباح ينتظرك',
  ];
  static const _morningBodies = [
    'ابدأ صباحك بأذكار تحفظ قلبك وتبارك يومك.',
    'أصبحنا وأصبح الملك لله — لا تنسَ أذكار الصباح.',
    'خذ نفسًا هادئًا، وابدأ ورد أذكار الصباح.',
  ];
  static const _daytimeTitles = [
    'سبّح الله',
    'دقيقة ذكر',
    'لا تنسَ الاستغفار',
    'أحبّ الكلام إلى الله',
  ];
  static const _daytimeBodies = [
    'سبحان الله وبحمده، سبحان الله العظيم.',
    'سبحان الله، والحمد لله، ولا إله إلا الله، والله أكبر.',
    'استغفر الله وأتوب إليه — ذكر خفيف وأجر عظيم.',
    'اجعل بين أشغالك لحظةً يطمئن فيها قلبك بذكر الله.',
  ];
  static const _eveningTitles = [
    'عطّر مساءك بذكر الله',
    'حصّن مساءك',
    'ورد المساء ينتظرك',
  ];
  static const _eveningBodies = [
    'أمسينا وأمسى الملك لله — حان وقت أذكار المساء.',
    'اختم نهارك بسكينة أذكار المساء.',
    'لا تنسَ ورد المساء؛ كلمات يسيرة وحفظ بإذن الله.',
  ];
  static const _sleepTitles = [
    'لا تنسَ أذكار النوم',
    'نم على ذكر الله',
    'اختم يومك بالذكر',
  ];
  static const _sleepBodies = [
    'باسمك اللهم أموت وأحيا — اقرأ أذكار النوم قبل أن تنام.',
    'آية الكرسي والمعوذات من هدي المسلم قبل نومه.',
    'هدّئ قلبك، واترك يومك بين يدي الله بأذكار النوم.',
  ];

  static List<KhatmaPlan> _activeKhatmaPlans(LocalStorageService storage) {
    final raw = storage.readMap('khatma')['plans'];
    if (raw is! List) return const [];
    final plans = <KhatmaPlan>[];
    for (final value in raw) {
      if (value is! Map) continue;
      try {
        final plan = KhatmaPlan.fromJson(Map<String, dynamic>.from(value));
        if (plan.status == KhatmaStatus.active && plan.reminderPrayer != null) {
          plans.add(plan);
        }
      } on Object {
        // A damaged plan must not prevent the remaining reminders.
      }
    }
    return plans;
  }

  static void _addMemorizationReminder({
    required List<ScheduledAppNotification> items,
    required LocalStorageService storage,
    required AppSettings settings,
    required DateTime now,
  }) {
    MemorizationPlan? active;
    final raw = storage.readMap(
      QuranMemorizationRepository.storageKey,
    )['plans'];
    if (raw is List) {
      for (final value in raw) {
        if (value is! Map) continue;
        try {
          final plan = MemorizationPlan.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (plan.isActive && !plan.isCompleted) {
            active = plan;
            break;
          }
        } on Object {
          // Continue with the next valid plan.
        }
      }
    }

    final hour = active?.reminderHour;
    final minute = active?.reminderMinute;
    if (hour == null || minute == null) {
      // A past item acts as a cancellation marker for a previously scheduled
      // repeating reminder while keeping the service API compact.
      items.add(
        ScheduledAppNotification(
          id: memorizationReminderId,
          title: '',
          body: '',
          at: DateTime.fromMillisecondsSinceEpoch(0),
          sound: false,
          vibrate: false,
          kind: AppNotificationKind.memorization,
        ),
      );
      return;
    }

    var at = DateTime(now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    items.add(
      ScheduledAppNotification(
        id: memorizationReminderId,
        title: 'ورد الحفظ والمراجعة',
        body: active == null
            ? 'حان موعد وردك اليومي من حفظ القرآن الكريم ومراجعته.'
            : 'حان موعد «${active.title}» — خطوة ثابتة كل يوم.',
        at: at,
        payload: 'memorization:${active?.id ?? ''}',
        sound: true,
        vibrate: settings.vibrate,
        repeatsDaily: true,
        kind: AppNotificationKind.memorization,
      ),
    );
  }
}
