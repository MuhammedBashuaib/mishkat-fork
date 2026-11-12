import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/home_widget_service.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/core/utils/app_formatters.dart';
import 'package:mishkat_app/features/khatma/data/models/khatma_plan.dart';
import 'package:mishkat_app/features/prayer_times/data/services/prayer_calculator.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/src/home_widget/prayer_times_widget.home_widget.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final binding = TestDefaultBinaryMessengerBinding.instance;
  late Directory directory;
  late HomeWidgetService service;
  late Map<String, dynamic> saved;
  late List<MethodCall> calls;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mishkat-widget-test-');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    saved = {};
    calls = [];
    now = DateTime(2026, 11, 5, 9, 11, 30);
    service = HomeWidgetService(
      adhkarRepository: AdhkarRepository(),
      now: () => now,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      paths,
      (_) async => directory.path,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      final args = call.arguments as Map? ?? {};
      switch (call.method) {
        case 'saveWidgetData':
          expect(args['appGroupId'], HomeWidgetService.appGroupId);
          saved[args['id'] as String] = args['data'];
          return true;
        case 'getWidgetData':
          return saved[args['id']];
        case 'getInstalledWidgets':
          return [
            {
              'androidClassName': '.WirdWidgetHomeWidgetReceiver',
              'widgetId': 1,
            },
            {
              'androidClassName': '.TasbihWidgetHomeWidgetReceiver',
              'widgetId': 2,
            },
          ];
        default:
          return true;
      }
    });
  });

  const located = AppSettings(
    latitude: 37.7749,
    longitude: -122.4194,
    city: 'سان فرانسيسكو',
    method: 'Makkah',
    methodSet: true,
    asr: 'Hanafi',
    tune: {'fajr': 3, 'asr': -2},
  );

  Future<Map<String, dynamic>> prayerTimeline() async {
    final file = File(
      saved['home_widget.PrayerTimesWidget.timedData'] as String,
    );
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  test(
    'prayer timer targets match the app calculator through a full week',
    () async {
      await service.sync(located);
      final timeline = await prayerTimeline();
      final expiry = now.add(const Duration(days: 7));
      expect(timeline.keys.first, '${now.millisecondsSinceEpoch}');
      expect(timeline.keys.last, '${expiry.millisecondsSinceEpoch}');
      expect(timeline.length, greaterThan(35));
      for (final entry in timeline.entries.take(timeline.length - 1)) {
        final at = DateTime.fromMillisecondsSinceEpoch(int.parse(entry.key));
        final data = PrayerTimesWidgetTimedData.fromJson(
          entry.value as Map<String, dynamic>,
        );
        final expected = const PrayerCalculator().schedule(
          now: at,
          latitude: located.latitude!,
          longitude: located.longitude!,
          methodKey: located.method,
          methodAuto: !located.methodSet,
          asr: located.asr,
          highLatitudes: located.highLatitudes,
          tune: located.tune,
        );
        expect(data.prayerNextAt, expected.next.at.millisecondsSinceEpoch);
        expect(data.prayerNextName, expected.next.name);
        expect(
          data.prayerRemaining,
          AppFormatters.duration(expected.next.at.difference(at)),
        );
        expect(data.prayerNextAt!, greaterThan(at.millisecondsSinceEpoch));
        expect(data.toJson()['prayerNextAt'], data.prayerNextAt);
      }
      expect(timeline.values.last['prayerNextAt'], 0);
      expect(timeline.values.last['prayerRemaining'], contains('تحديث'));
    },
  );

  test('last second does not advance the prayer before the app does', () async {
    final next = const PrayerCalculator()
        .schedule(
          now: now,
          latitude: located.latitude!,
          longitude: located.longitude!,
          methodKey: located.method,
          methodAuto: false,
          asr: located.asr,
          tune: located.tune,
        )
        .next;
    now = next.at.subtract(const Duration(milliseconds: 500));
    await service.sync(located);
    final timeline = await prayerTimeline();
    expect(
      timeline.values.first['prayerNextAt'],
      next.at.millisecondsSinceEpoch,
    );
    final boundary = timeline['${next.at.millisecondsSinceEpoch}'] as Map;
    expect(
      boundary['prayerNextAt'],
      greaterThan(next.at.millisecondsSinceEpoch),
    );
  });

  test(
    'removing location clears scheduled data and selects north fallback',
    () async {
      await service.sync(located);
      expect(
        saved['home_widget.QiblaWidget.qiblaBearingDegrees'],
        isA<double>(),
      );
      await service.sync(const AppSettings());
      expect(saved['home_widget.PrayerTimesWidget.timedData'], isNull);
      expect(saved['home_widget.QiblaWidget.qiblaBearingDegrees'], -1);
      expect(saved['home_widget.QiblaWidget.qiblaBearing'], 'الشمال');
      expect(
        calls.any((call) => call.method == 'cancelScheduledWidgetUpdates'),
        isTrue,
      );
    },
  );

  test('theme saves before redraw and refreshes all five widgets', () async {
    await service.sync(const AppSettings(widgetTheme: AppThemePreference.dark));
    expect(saved['widgetTheme'], 'dark');
    final refreshes = calls
        .where((call) => call.method == 'updateWidget')
        .toList();
    expect(
      refreshes
          .map((call) => (call.arguments as Map)['qualifiedAndroidName'])
          .toSet(),
      {
        'com.dakomn.mishkatapp.PrayerTimesWidgetHomeWidgetReceiver',
        'com.dakomn.mishkatapp.QiblaWidgetHomeWidgetReceiver',
        'com.dakomn.mishkatapp.AdhkarWidgetHomeWidgetReceiver',
        'com.dakomn.mishkatapp.WirdWidgetHomeWidgetReceiver',
        'com.dakomn.mishkatapp.TasbihWidgetHomeWidgetReceiver',
      },
    );
    final themeWrite = calls.indexWhere(
      (call) =>
          call.method == 'saveWidgetData' &&
          (call.arguments as Map)['id'] == 'widgetTheme',
    );
    expect(themeWrite, lessThan(calls.indexOf(refreshes.first)));
    await Future.wait([
      service.sync(const AppSettings(widgetTheme: AppThemePreference.light)),
      service.sync(const AppSettings()),
    ]);
    expect(saved['widgetTheme'], 'system');
  });

  test(
    'wird writes completion counts and resets progress when plan is removed',
    () async {
      final plan = KhatmaPlan(
        id: 'one',
        name: 'ختمتي',
        durationDays: 30,
        dailyPages: 20,
        startDate: now,
        startPage: 101,
        progressPage: 150,
        lastReadPage: 160,
        status: KhatmaStatus.active,
        createdAt: now,
      );
      await service.syncWird(plan);
      expect(
        saved['home_widget.WirdWidget.wirdProgressValue'],
        closeTo(50 / 504, 0.0001),
      );
      expect(
        saved['home_widget.WirdWidget.wirdCompletedPages'],
        'أنجزت ٥٠ صفحة',
      );
      expect(
        saved['home_widget.WirdWidget.wirdRemainingPages'],
        'باقي ٤٥٤ صفحة',
      );
      await service.syncWird(null);
      expect(saved['home_widget.WirdWidget.wirdProgressValue'], 0);
      expect(
        saved['home_widget.WirdWidget.wirdCompletedPages'],
        'أنجزت ٠ صفحة',
      );
      expect(saved['home_widget.WirdWidget.wirdRemainingPages'], 'باقي ٠ صفحة');
    },
  );

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, null);
    debugDefaultTargetPlatformOverride = null;
    await directory.delete(recursive: true);
  });

  test(
    'new widgets detect installations and request the correct providers',
    () async {
      for (final widget in [MishkatHomeWidget.wird, MishkatHomeWidget.tasbih]) {
        expect(await service.isInstalled(widget), isTrue);
        await service.requestPin(widget);
      }
      expect(
        calls
            .where((call) => call.method == 'requestPinWidget')
            .map((call) => (call.arguments as Map)['qualifiedAndroidName']),
        [
          'com.dakomn.mishkatapp.WirdWidgetHomeWidgetReceiver',
          'com.dakomn.mishkatapp.TasbihWidgetHomeWidgetReceiver',
        ],
      );
      await service.syncWird(null);
      expect(saved['home_widget.WirdWidget.wirdPages'], 'ابدأ ختمتك الأولى');
    },
  );

  test(
    'iOS lock-only prayer installation is not a Home Screen installation',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final installed = <Map<String, dynamic>>[
        {
          'kind': 'PrayerTimesWidgetHomeWidget',
          'family': 'accessoryRectangular',
        },
        {'kind': 'PrayerTimesWidgetHomeWidget', 'family': 'accessoryCircular'},
        {'kind': 'PrayerTimesWidgetHomeWidget', 'family': 'accessoryInline'},
      ];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'getInstalledWidgets') return installed;
        return true;
      });
      expect(await service.isInstalled(MishkatHomeWidget.prayerTimes), isFalse);
      installed.add({
        'kind': 'PrayerTimesWidgetHomeWidget',
        'family': 'systemMedium',
      });
      expect(await service.isInstalled(MishkatHomeWidget.prayerTimes), isTrue);
    },
  );

  test('tasbih coalesces taps and saves a midnight reset without losing the count', () async {
    service.scheduleTasbihSync(const TasbihState(count: 1));
    service.scheduleTasbihSync(const TasbihState(count: 2));
    // Backgrounding flushes the latest state immediately and cancels the timer.
    await service.syncTasbih(const TasbihState(count: 3));
    expect(saved['home_widget.TasbihWidget.tasbihCount'], '٣');
    expect(
      saved['home_widget.TasbihWidget.tasbihProgressValue'],
      closeTo(3 / 33, 0.0001),
    );
    expect(calls.where((call) => call.method == 'updateWidget'), hasLength(1));
    final file = File(saved['home_widget.TasbihWidget.timedData'] as String);
    final timeline = jsonDecode(await file.readAsString()) as Map;
    expect(timeline, hasLength(2));
    final reset = DateTime.fromMillisecondsSinceEpoch(
      int.parse(timeline.keys.last as String),
    );
    expect(reset.hour, 0);
    expect(reset.minute, 0);
    expect((timeline.values.last as Map)['tasbihToday'], 'اليوم ٠ تسبيحة');
  });
}
