import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/home_widget_service.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
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

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mishkat-widget-test-');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    saved = {};
    calls = [];
    service = HomeWidgetService(adhkarRepository: AdhkarRepository());
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
            .map((call) => (call.arguments as Map)['android']),
        ['WirdWidgetHomeWidgetReceiver', 'TasbihWidgetHomeWidgetReceiver'],
      );
      await service.syncWird(null);
      expect(saved['home_widget.WirdWidget.wirdPages'], 'ابدأ ختمتك الأولى');
    },
  );

  test('tasbih coalesces taps and saves a midnight reset without losing the count', () async {
    service.scheduleTasbihSync(const TasbihState(count: 1));
    service.scheduleTasbihSync(const TasbihState(count: 2));
    // Backgrounding flushes the latest state immediately and cancels the timer.
    await service.syncTasbih(const TasbihState(count: 3));
    expect(saved['home_widget.TasbihWidget.tasbihCount'], '٣');
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
