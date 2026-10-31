import '../../../../core/services/local_notification_service.dart';
import '../../../khatma/data/models/khatma_plan.dart';
import '../../../prayer_times/data/services/prayer_calculator.dart';
import '../../../quran/data/models/memorization_plan.dart';
import '../../../quran/data/repositories/quran_memorization_repository.dart';
import '../../../tasbih/presentation/cubit/tasbih_state.dart';
import '../models/reminder_preferences.dart';
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
  static const int _dailyAdhkarBase = 290000;
  static const int _khatmaBase = 300000;
  static const int _goodDeedBase = 400000;
  static const int memorizationReminderId = 800001;

  static List<ScheduledAppNotification> build({
    required LocalStorageService storage,
    required AppSettings settings,
    DateTime? now,
    int days = 14,
  }) {
    final current = now ?? DateTime.now();
    if (!settings.notificationsEnabled) return const [];
    final items = <ScheduledAppNotification>[
      // Clear the old prayer calendar even when every prayer is disabled or
      // the location has been removed. This marker is never scheduled.
      ScheduledAppNotification(
        id: _prayerBase,
        title: '',
        body: '',
        at: DateTime(1970),
        sound: false,
      ),
    ];

    if (settings.hasLocation) {
      _addPrayerBasedNotifications(
        items: items,
        storage: storage,
        settings: settings,
        now: current,
        days: days,
      );
    }

    _addTimedAdhkar(items, settings, current);
    _addGoodDeedReminders(items, storage, settings, current);

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
    final khatmaPlans = settings.reminders.dailyWirdEnabled
        ? _activeKhatmaPlans(storage)
        : const <KhatmaPlan>[];

    for (var day = 0; day < days; day++) {
      final date = DateTime(now.year, now.month, now.day + day);
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

      if (day != 0) continue;
      for (var planIndex = 0; planIndex < khatmaPlans.length; planIndex++) {
        final plan = khatmaPlans[planIndex];
        final prayer = plan.reminderPrayer;
        final prayerTime = prayer == null ? null : times[prayer];
        if (prayerTime == null) continue;
        final at = _nextDailyOccurrence(
          prayerTime.add(const Duration(minutes: 15)),
          now,
        );
        items.add(
          ScheduledAppNotification(
            id: _khatmaBase + day * 100 + planIndex,
            title: 'ورد ${plan.name}',
            body: 'حان وقت وردك من القرآن. افتح خطتك لتكمل من موضعك المحفوظ.',
            repeatsDaily: true,
            at: at,
            payload: 'khatma:${plan.id}',
            sound: settings.reminders.sound,
            vibrate: settings.vibrate,
            kind: AppNotificationKind.khatma,
          ),
        );
      }
    }
  }

  static void _addTimedAdhkar(
    List<ScheduledAppNotification> items,
    AppSettings settings,
    DateTime now,
  ) {
    if (!settings.adhkarNotifications) return;
    final times = settings.hasLocation
        ? const PrayerCalculator().calculate(
            date: DateTime(now.year, now.month, now.day),
            latitude: settings.latitude!,
            longitude: settings.longitude!,
            methodKey: settings.method,
            methodAuto: !settings.methodSet,
            asr: settings.asr,
            highLatitudes: settings.highLatitudes,
            tune: settings.tune,
          )
        : null;
    final sleepMinute = ReminderPreferences.fromJson(
      settings.reminders.toJson(),
    ).sleepMinute;
    final moments = [
      (
        times?['fajr']?.add(const Duration(minutes: 20)) ??
            DateTime(now.year, now.month, now.day, 6, 30),
        'adhkar:3',
        _wakeTitles,
        _wakeBodies,
      ),
      (
        times?['sunrise']?.add(const Duration(minutes: 30)) ??
            DateTime(now.year, now.month, now.day, 7),
        'adhkar:1',
        _morningTitles,
        _morningBodies,
      ),
      (
        times?['asr']?.add(const Duration(minutes: 30)) ??
            DateTime(now.year, now.month, now.day, 18),
        'adhkar:133',
        _eveningTitles,
        _eveningBodies,
      ),
      (
        DateTime(
          now.year,
          now.month,
          now.day,
          sleepMinute ~/ 60,
          sleepMinute % 60,
        ),
        'adhkar:2',
        _sleepTitles,
        _sleepBodies,
      ),
    ];
    for (var index = 0; index < moments.length; index++) {
      final (source, payload, titles, bodies) = moments[index];
      items.add(
        ScheduledAppNotification(
          id: _dailyAdhkarBase + index,
          title: _pick(titles, now),
          body: _pick(bodies, now),
          at: _nextDailyOccurrence(source, now),
          payload: payload,
          sound: settings.reminders.sound,
          vibrate: settings.vibrate,
          repeatsDaily: true,
          kind: AppNotificationKind.adhkar,
        ),
      );
    }
  }

  static void _addGoodDeedReminders(
    List<ScheduledAppNotification> items,
    LocalStorageService storage,
    AppSettings settings,
    DateTime now,
  ) {
    final preferences = ReminderPreferences.fromJson(
      settings.reminders.toJson(),
    );
    void add(
      int slot,
      int minute,
      String title,
      String body,
      String payload,
      AppNotificationKind kind,
    ) {
      // Keep gentle reminders apart from each other and prayer alarms.
      // Only these reminders use the 08:00–22:00 daytime window.
      int? availableMinute;
      for (var attempt = 0; attempt < 112; attempt++) {
        final offset = ((attempt + 1) ~/ 2) * 15 * (attempt.isOdd ? 1 : -1);
        final candidate = minute + offset;
        if (candidate < 8 * 60 || candidate >= 22 * 60) continue;
        final busy = items.any(
          (item) =>
              item.at.isAfter(now) &&
              ((item.at.hour * 60 + item.at.minute) - candidate).abs() < 15,
        );
        if (!busy) {
          availableMinute = candidate;
          break;
        }
      }
      if (availableMinute == null) return;
      final candidate = availableMinute;
      items.add(
        ScheduledAppNotification(
          id: _goodDeedBase + slot,
          title: title,
          body: body,
          at: _nextDailyOccurrence(
            DateTime(
              now.year,
              now.month,
              now.day,
              candidate ~/ 60,
              candidate % 60,
            ),
            now,
          ),
          payload: payload,
          sound: preferences.sound,
          vibrate: settings.vibrate,
          repeatsDaily: true,
          kind: kind,
        ),
      );
    }

    if (preferences.charityEnabled) {
      add(
        0,
        preferences.charityMorningMinute,
        'ابدأ يومك بصدقة',
        _pick(_charityMorningBodies, now),
        'charity',
        AppNotificationKind.charity,
      );
      add(
        1,
        preferences.charityEveningMinute,
        'هل تصدّقت اليوم؟',
        _pick(_charityEveningBodies, now),
        'charity',
        AppNotificationKind.charity,
      );
    }
    if (preferences.dailyWirdEnabled &&
        (!settings.hasLocation || _activeKhatmaPlans(storage).isEmpty)) {
      add(
        2,
        preferences.dailyWirdMinute,
        'موعدك مع القرآن',
        _pick(_wirdBodies, now),
        'wird',
        AppNotificationKind.khatma,
      );
    }
    if (preferences.dhikrEnabled) {
      final minutes = switch (preferences.dhikrPerDay) {
        1 => [13 * 60 + 15],
        5 => [
          10 * 60 + 15,
          12 * 60 + 45,
          15 * 60 + 15,
          17 * 60 + 45,
          20 * 60 + 15,
        ],
        _ => [10 * 60 + 45, 14 * 60 + 15, 19 * 60 + 45],
      };
      final seed = _daySeed(now);
      for (var index = 0; index < minutes.length; index++) {
        final (id, title, invitation) =
            _dhikrMessages[(seed + index) % _dhikrMessages.length];
        final dhikr = tasbihDhikrOptions.singleWhere((item) => item.id == id);
        add(
          10 + index,
          minutes[index],
          title,
          '${dhikr.text} — $invitation',
          'tasbih:$id',
          AppNotificationKind.dhikr,
        );
      }
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
    if (!result.isAfter(now)) {
      result = DateTime(
        now.year,
        now.month,
        now.day + 1,
        source.hour,
        source.minute,
      );
    }
    return result;
  }

  static String _pick(List<String> values, DateTime date) =>
      values[_daySeed(date) % values.length];

  static int _daySeed(DateTime date) => DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(2020)).inDays.abs();

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
  static const _charityMorningBodies = [
    'اجعل لك اليوم نصيبًا من الخير، ولو بصدقة يسيرة لمن يحتاجها.',
    'باب خير ينتظرك: طعام لمحتاج، أو سقيا ماء، أو عون لمن حولك.',
    'انوِ الخير وابدأ بخطوة صغيرة. صدقتك اليوم قد تسعد قلبًا.',
  ];
  static const _charityEveningBodies = [
    'ما زالت أمامك فرصة للخير. لا تنسَ صدقتك ولو بالقليل.',
    'قبل أن ينتهي يومك، تفقّد محتاجًا أو أسعد أحدًا بعطاء.',
    'هل كان لك اليوم نصيب من العطاء؟ اجعل في ختام يومك صدقة.',
  ];
  static const _wirdBodies = [
    'دقائق مع القرآن تضيء يومك. أكمل من آخر موضع قرأته.',
    'ورد قليل تداوم عليه؛ افتح مصحفك وخذ لحظة للتلاوة.',
    'اجعل لقلبك موعدًا مع القرآن. وردك اليومي ينتظرك.',
  ];
  static const _dhikrMessages = [
    ('subhan_allah', 'سبّح الله', 'خذ لحظة هادئة للتسبيح.'),
    ('salawat', 'صلِّ على النبي ﷺ', 'عطّر وقتك بالصلاة والسلام عليه.'),
    ('istighfar', 'لا تنسَ الاستغفار', 'اجعل بين أشغالك لحظة استغفار.'),
    ('alhamdulillah', 'لحظة حمد', 'تذكّر نعمة واحمد الله عليها.'),
    ('tahlil', 'جدّد ذكرك لله', 'اذكر الله بقلب حاضر.'),
    ('hawqalah', 'استعن بالله', 'استعن بالله في يومك وأشغالك.'),
    ('subhan_bihamdih', 'دقيقة ذكر', 'افتح المسبحة وابدأ بما تيسّر.'),
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
        if (plan.status == KhatmaStatus.active &&
            const [
              'fajr',
              'dhuhr',
              'asr',
              'maghrib',
              'isha',
            ].contains(plan.reminderPrayer)) {
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
    if (!at.isAfter(now)) {
      at = DateTime(now.year, now.month, now.day + 1, hour, minute);
    }
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
