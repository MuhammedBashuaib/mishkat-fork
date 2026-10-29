import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../features/adhkar/data/models/adhkar_models.dart';
import '../../features/adhkar/data/repositories/adhkar_repository.dart';
import '../../features/prayer_times/data/services/prayer_calculator.dart';
import '../../features/prayer_times/domain/models/prayer_models.dart';
import '../../features/settings/data/models/app_settings.dart';
import '../../src/home_widget/adhkar_widget.home_widget.dart';
import '../../src/home_widget/prayer_times_widget.home_widget.dart';
import '../../src/home_widget/qibla_widget.home_widget.dart';
import '../utils/app_formatters.dart';

enum MishkatHomeWidget { prayerTimes, qibla, adhkar }

/// The latest deep link delivered by a Home Screen widget.
///
/// It intentionally mirrors the notification tap notifier so the shell can
/// route cold starts and warm launches through one predictable mechanism.
final ValueNotifier<Uri?> homeWidgetLaunchUri = ValueNotifier<Uri?>(null);

class HomeWidgetService {
  HomeWidgetService({
    required AdhkarRepository adhkarRepository,
    PrayerCalculator calculator = const PrayerCalculator(),
  }) : this._internal(adhkarRepository, calculator);

  HomeWidgetService._internal(this._adhkarRepository, this._calculator);

  static const appGroupId = 'group.com.dakomn.mishkatapp.widgets';

  final AdhkarRepository _adhkarRepository;
  final PrayerCalculator _calculator;
  StreamSubscription<Uri?>? _clickSubscription;

  bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get canRequestPin =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize(AppSettings settings) async {
    if (!isSupportedPlatform) return;
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      homeWidgetLaunchUri.value =
          await HomeWidget.initiallyLaunchedFromHomeWidget();
      _clickSubscription ??= HomeWidget.widgetClicked.listen((uri) {
        if (uri != null) homeWidgetLaunchUri.value = uri;
      });
    } on Object catch (error, stackTrace) {
      _reportOptionalFailure('while initializing', error, stackTrace);
    }
    await sync(settings);
  }

  /// Saves two days of local data and asks both native platforms to redraw.
  /// Timed entries let prayer and adhkar content advance while Flutter is not
  /// running; no network request or continuous background task is required.
  Future<void> sync(AppSettings settings) async {
    if (!isSupportedPlatform) return;
    await Future.wait([
      _guarded('while syncing prayer widget', () => _syncPrayer(settings)),
      _guarded('while syncing qibla widget', () => _syncQibla(settings)),
      _guarded('while syncing adhkar widget', _syncAdhkar),
    ]);
  }

  Future<bool> isInstalled(MishkatHomeWidget widget) async {
    if (!isSupportedPlatform) return false;
    try {
      final result = switch (widget) {
        MishkatHomeWidget.prayerTimes =>
          PrayerTimesWidgetHomeWidget.isInstalled(),
        MishkatHomeWidget.qibla => QiblaWidgetHomeWidget.isInstalled(),
        MishkatHomeWidget.adhkar => AdhkarWidgetHomeWidget.isInstalled(),
      };
      return await result;
    } on Object {
      return false;
    }
  }

  Future<bool> isPinRequestSupported() async {
    if (!canRequestPin) return false;
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } on Object {
      return false;
    }
  }

  Future<void> requestPin(MishkatHomeWidget widget) async {
    if (!canRequestPin) return;
    switch (widget) {
      case MishkatHomeWidget.prayerTimes:
        await PrayerTimesWidgetHomeWidget.requestPinWidget();
      case MishkatHomeWidget.qibla:
        await QiblaWidgetHomeWidget.requestPinWidget();
      case MishkatHomeWidget.adhkar:
        await AdhkarWidgetHomeWidget.requestPinWidget();
    }
  }

  Future<void> _syncPrayer(AppSettings settings) async {
    if (!settings.hasLocation) {
      await PrayerTimesWidgetHomeWidget.saveData(
        prayerCity: 'حدّد موقعك في مشكاة',
        timedData: const {},
      );
      await PrayerTimesWidgetHomeWidget.updateWidget();
      return;
    }

    final now = DateTime.now();
    final end = now.add(const Duration(hours: 48));
    final points = <DateTime>{now.subtract(const Duration(seconds: 1))};

    // Hourly points keep the human-friendly remaining estimate useful, while
    // exact prayer points advance the next-prayer title at the right moment.
    for (var hour = 1; hour <= 48; hour++) {
      points.add(now.add(Duration(hours: hour)));
    }
    for (var day = 0; day <= 2; day++) {
      final date = DateTime(now.year, now.month, now.day + day, 12);
      final schedule = _schedule(settings, date);
      points.addAll(
        schedule.moments
            .map((moment) => moment.at)
            .where((time) => time.isAfter(now) && !time.isAfter(end)),
      );
    }

    final ordered = points.where((time) => !time.isAfter(end)).toList()..sort();
    final timedData = <DateTime, PrayerTimesWidgetTimedData>{
      for (final point in ordered) point: _prayerDataAt(settings, point),
    };
    await PrayerTimesWidgetHomeWidget.saveData(
      prayerCity: settings.city.isEmpty ? 'موقعك الحالي' : settings.city,
      timedData: timedData,
    );
    await PrayerTimesWidgetHomeWidget.updateWidget();
  }

  PrayerTimesWidgetTimedData _prayerDataAt(AppSettings settings, DateTime at) {
    final schedule = _schedule(settings, at.add(const Duration(seconds: 1)));
    final remaining = schedule.next.at.difference(at);
    return PrayerTimesWidgetTimedData(
      prayerRemaining: _remainingLabel(remaining),
      prayerNextName: schedule.next.name,
      prayerNextTime: _arabicDigits(AppFormatters.time(schedule.next.at)),
      prayerUpcoming: _upcomingLabel(settings, schedule, at),
    );
  }

  String _upcomingLabel(
    AppSettings settings,
    PrayerSchedule schedule,
    DateTime at,
  ) {
    final upcoming = <PrayerMoment>[
      ...schedule.moments.where((moment) => moment.at.isAfter(at)),
    ];
    for (var day = 1; upcoming.length < 3 && day <= 2; day++) {
      final nextDay = DateTime(at.year, at.month, at.day + day);
      upcoming.addAll(_schedule(settings, nextDay).moments);
    }
    return upcoming
        .take(3)
        .map(
          (moment) =>
              '${moment.name} ${_arabicDigits(AppFormatters.time(moment.at))}',
        )
        .join('  •  ');
  }

  PrayerSchedule _schedule(AppSettings settings, DateTime now) =>
      _calculator.schedule(
        now: now,
        latitude: settings.latitude!,
        longitude: settings.longitude!,
        methodKey: settings.method,
        methodAuto: !settings.methodSet,
        asr: settings.asr,
        highLatitudes: settings.highLatitudes,
        tune: settings.tune,
      );

  Future<void> _syncQibla(AppSettings settings) async {
    if (!settings.hasLocation) {
      await QiblaWidgetHomeWidget.saveData(
        qiblaArrow: '↑',
        qiblaBearing: 'حدّد موقعك',
        qiblaDistance: 'افتح مشكاة للبوصلة الحية',
      );
      await QiblaWidgetHomeWidget.updateWidget();
      return;
    }
    final result = _calculator.qibla(settings.latitude!, settings.longitude!);
    await QiblaWidgetHomeWidget.saveData(
      qiblaArrow: _bearingArrow(result.bearing),
      qiblaBearing:
          '${_arabicDigits(result.bearing.round().toString())}° ${_bearingName(result.bearing)}',
      qiblaDistance:
          '${_arabicDigits(result.distanceKm.round().toString())} كم إلى الكعبة',
    );
    await QiblaWidgetHomeWidget.updateWidget();
  }

  Future<void> _syncAdhkar() async {
    final categories = await _adhkarRepository.load();
    final now = DateTime.now();
    final end = now.add(const Duration(hours: 48));
    final points = <DateTime>{now.subtract(const Duration(seconds: 1))};
    for (var day = 0; day <= 2; day++) {
      for (final hour in const [5, 12, 16, 22]) {
        final point = DateTime(now.year, now.month, now.day + day, hour);
        if (point.isAfter(now) && !point.isAfter(end)) points.add(point);
      }
    }
    final ordered = points.toList()..sort();
    await AdhkarWidgetHomeWidget.saveData(
      timedData: {
        for (final point in ordered)
          point: _dhikrDataAt(
            categories,
            point.add(const Duration(seconds: 1)),
          ),
      },
    );
    await AdhkarWidgetHomeWidget.updateWidget();
  }

  AdhkarWidgetTimedData _dhikrDataAt(
    List<AdhkarCategory> categories,
    DateTime at,
  ) {
    final categoryId = switch (at.hour) {
      >= 5 && < 12 => 1,
      >= 12 && < 16 => 130,
      >= 16 && < 22 => 133,
      _ => 2,
    };
    final category = categories.firstWhere(
      (item) => item.id == categoryId,
      orElse: () => categories.first,
    );
    final compactItems = category.items
        .where((item) => item.text.length >= 35 && item.text.length <= 190)
        .toList();
    final choices = compactItems.isEmpty ? category.items : compactItems;
    final day = at.difference(DateTime(at.year)).inDays;
    final slot = switch (categoryId) {
      1 => 0,
      130 => 1,
      133 => 2,
      _ => 3,
    };
    final item = choices[(day * 4 + slot) % choices.length];
    return AdhkarWidgetTimedData(
      dhikrCategory: category.name,
      dhikrCount: _countLabel(item.count),
      dhikrText: _cleanDhikr(item.text),
    );
  }

  Future<void> _guarded(
    String context,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      _reportOptionalFailure(context, error, stackTrace);
    }
  }

  void _reportOptionalFailure(
    String context,
    Object error,
    StackTrace stackTrace,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'Mishkat Home Widgets',
        context: ErrorDescription(context),
        silent: true,
      ),
    );
  }

  static String _remainingLabel(Duration duration) {
    if (duration.inMinutes < 1) return 'حان وقت الصلاة';
    if (duration.inMinutes < 60) return 'متبقي أقل من ساعة';
    final hours = (duration.inMinutes / 60).ceil();
    if (hours == 1) return 'متبقي نحو ساعة';
    if (hours == 2) return 'متبقي نحو ساعتين';
    return 'متبقي نحو ${_arabicDigits('$hours')} ساعات';
  }

  static String _countLabel(int count) {
    if (count <= 1) return 'مرة واحدة';
    if (count == 2) return 'مرتان';
    return '${_arabicDigits('$count')} مرات';
  }

  static String _cleanDhikr(String value) => value
      .replaceAll('((', '')
      .replaceAll('))', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _bearingArrow(double bearing) {
    const arrows = ['↑', '↗', '→', '↘', '↓', '↙', '←', '↖'];
    return arrows[((bearing + 22.5) ~/ 45) % 8];
  }

  static String _bearingName(double bearing) {
    const names = [
      'شمال',
      'شمال شرقي',
      'شرق',
      'جنوب شرقي',
      'جنوب',
      'جنوب غربي',
      'غرب',
      'شمال غربي',
    ];
    return names[((bearing + 22.5) ~/ 45) % 8];
  }

  static String _arabicDigits(String value) {
    const western = '0123456789';
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    var output = value;
    for (var index = 0; index < western.length; index++) {
      output = output.replaceAll(western[index], eastern[index]);
    }
    return output;
  }
}
