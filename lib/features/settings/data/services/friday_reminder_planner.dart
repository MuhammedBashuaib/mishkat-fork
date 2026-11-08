import 'dart:math' as math;

import '../../../../core/services/local_notification_service.dart';
import '../../../prayer_times/data/services/prayer_calculator.dart';
import '../models/app_settings.dart';

/// Weekly Friday reminders, rebuilt from each Friday's own prayer times.
class FridayReminderPlanner {
  const FridayReminderPlanner._();

  static const _base = 500000;

  static List<ScheduledAppNotification> build({
    required AppSettings settings,
    required DateTime now,
    required List<ScheduledAppNotification> existing,
  }) {
    if (!settings.notificationsEnabled || !settings.reminders.fridayEnabled) {
      return const [];
    }
    final offset = (DateTime.friday - now.weekday + 7) % 7;
    final firstFriday = DateTime(now.year, now.month, now.day + offset);
    final selected = <int, ScheduledAppNotification>{};
    // Some slots may have passed this Friday. Recalculate those next week;
    // adding seven days to today's prayer would retain an obsolete solar time.
    for (var week = 0; week < 2; week++) {
      final date = DateTime(
        firstFriday.year,
        firstFriday.month,
        firstFriday.day + week * 7,
      );
      for (final item in _forFriday(date, settings, existing)) {
        if (item.at.isAfter(now)) selected.putIfAbsent(item.id, () => item);
      }
    }
    return selected.values.toList()..sort((a, b) => a.at.compareTo(b.at));
  }

  static List<ScheduledAppNotification> _forFriday(
    DateTime date,
    AppSettings settings,
    List<ScheduledAppNotification> existing,
  ) {
    final times = settings.hasLocation
        ? const PrayerCalculator().calculate(
            date: date,
            latitude: settings.latitude!,
            longitude: settings.longitude!,
            methodKey: settings.method,
            methodAuto: !settings.methodSet,
            asr: settings.asr,
            highLatitudes: settings.highLatitudes,
            tune: settings.tune,
          )
        : null;
    bool sameDay(DateTime? value) =>
        value != null &&
        value.year == date.year &&
        value.month == date.month &&
        value.day == date.day;
    int minute(DateTime value) => value.hour * 60 + value.minute;
    final precise =
        sameDay(times?['dhuhr']) &&
        sameDay(times?['asr']) &&
        sameDay(times?['maghrib']) &&
        times!['asr']!.isAfter(times['dhuhr']!) &&
        times['maghrib']!.difference(times['asr']!).inMinutes >= 60;
    final dhuhr = precise ? minute(times['dhuhr']!) : 12 * 60;
    final asr = precise ? minute(times['asr']!) : 15 * 60;
    final maghrib = precise ? minute(times['maghrib']!) : 18 * 60;
    final sunrise = precise && sameDay(times['sunrise'])
        ? minute(times['sunrise']!) + 30
        : math.max(0, math.min(8 * 60, dhuhr - 120));
    final earliest = math.max(0, math.min(sunrise, dhuhr - 60));
    final latest = maghrib - 15;
    final busy = <int>[
      if (times != null)
        for (final entry in PrayerCalculator.order)
          if (!entry.noAdhan && sameDay(times[entry.key]))
            minute(times[entry.key]!),
      for (final item in existing)
        if (item.repeatsDaily ||
            (item.repeatsWeekly && item.at.weekday == DateTime.friday) ||
            sameDay(item.at))
          minute(item.at),
    ];
    final chosen = <int, int>{7: asr + 15, 8: maghrib - 30};
    busy.addAll(chosen.values);

    void place(
      int slot,
      int target, {
      int? start,
      int? end,
      bool afterMaghrib = false,
    }) {
      final lowerBound = afterMaghrib ? maghrib + 20 : earliest;
      final upperBound = afterMaghrib ? 1439 : latest;
      final low = math.max(lowerBound, start ?? lowerBound);
      final high = math.min(upperBound, end ?? upperBound);
      int? available(int lower, int upper) {
        if (lower > upper) return null;
        final center = target.clamp(lower, upper);
        for (var distance = 0; distance <= upper - lower; distance++) {
          for (final candidate in [center + distance, center - distance]) {
            if (candidate < lower || candidate > upper) continue;
            if (busy.every((value) => (value - candidate).abs() >= 15)) {
              return candidate;
            }
          }
        }
        return null;
      }

      final value =
          available(low, high) ??
          (afterMaghrib ? null : available(earliest, latest));
      if (value == null) return;
      chosen[slot] = value;
      busy.add(value);
    }

    place(0, 9 * 60, end: dhuhr - 30);
    place(1, dhuhr + 45, start: dhuhr + 15, end: asr - 15);
    // The final Kahf reminder follows Maghrib, leaving the pre-sunset slot
    // dedicated to dua. Never carry it into Saturday if sunset is very late.
    place(2, maghrib + 20, afterMaghrib: true);
    place(6, dhuhr + 90, start: dhuhr + 30, end: asr - 15);
    place(3, 10 * 60 + 30, end: dhuhr - 15);
    place(4, (dhuhr + asr) ~/ 2, start: dhuhr + 15, end: asr - 15);
    place(5, maghrib - 120, start: asr + 30, end: maghrib - 45);

    return [
      for (final entry in chosen.entries)
        ScheduledAppNotification(
          id: _base + entry.key,
          title: !precise && entry.key >= 7
              ? 'تذكير بدعاء الجمعة'
              : _titles[entry.key],
          body: switch (entry.key) {
            2 when !precise =>
              'خذ وقتًا هادئًا هذا المساء لقراءة سورة الكهف وتدبّر آياتها.',
            7 when !precise => 'تذكّر أن تجعل لك وقتًا للدعاء بعد العصر وقبل غروب الجمعة؛ تُرجى فيه الإجابة.',
            8 when !precise => 'تحرَّ آخر ساعة من الجمعة قبل الغروب، وأكثر من الدعاء بخيري الدنيا والآخرة.',
            _ => _bodies[entry.key],
          },
          at: DateTime(
            date.year,
            date.month,
            date.day,
            entry.value ~/ 60,
            entry.value % 60,
          ),
          payload: entry.key < 3
              ? 'quran:kahf'
              : entry.key < 6
              ? 'tasbih:salawat'
              : 'friday:dua',
          repeatsWeekly: true,
          kind: AppNotificationKind.friday,
          sound: settings.reminders.sound,
          vibrate: settings.vibrate,
        ),
    ];
  }

  static const _titles = [
    'سورة الكهف في يوم الجمعة',
    'نور ما بين الجمعتين',
    'وقت قراءة سورة الكهف',
    'أكثر من الصلاة على النبي ﷺ',
    'عطّر جمعتك بالصلاة على النبي ﷺ',
    'صلِّ وسلِّم على النبي ﷺ',
    'اجعل للدعاء نصيبًا من جمعتك',
    'اغتنم ما بعد العصر بالدعاء',
    'آخر ساعة من الجمعة',
  ];
  static const _bodies = [
    'من فضل قراءة الكهف يوم الجمعة نور ما بين الجمعتين. افتح السورة وابدأ بما تيسّر.',
    'خذ وقتًا هادئًا لقراءة سورة الكهف في يوم الجمعة، وأكمل ما بدأته منها.',
    'بعد صلاة المغرب، خذ وقتًا هادئًا لقراءة سورة الكهف وتدبّر آياتها.',
    'اللهم صلِّ وسلِّم على نبينا محمد. أكثر من الصلاة عليه في يوم الجمعة.',
    'لحظة ذكر في يوم الجمعة: اللهم صلِّ وسلِّم على نبينا محمد.',
    'أكثر من الصلاة والسلام على النبي ﷺ، واجعل لسانك رطبًا بذكر الله.',
    'تذكّر آخر ساعة بعد العصر وقبل الغروب؛ تُرجى فيها الإجابة، فتهيّأ للدعاء.',
    'بعد صلاة العصر، اغتنم ما بقي قبل الغروب بالدعاء لنفسك وأهلك والمسلمين؛ تُرجى فيه الإجابة.',
    'اغتنم ما بقي قبل غروب الجمعة بالدعاء لنفسك وأهلك والمسلمين؛ تُرجى فيه الإجابة.',
  ];
}
