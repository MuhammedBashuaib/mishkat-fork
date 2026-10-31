import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/presentation/services/arabic_speech_model_service.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/arabic_speech_model_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/arabic_speech_model');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ArabicSpeechModelService service;
  late List<MethodCall> calls;
  late Map<String, Object?> platformStatus;

  setUp(() {
    calls = [];
    platformStatus = {'status': 'downloadable', 'localeId': 'ar-SA'};
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'downloadArabicModel') {
        platformStatus = {
          'status': 'pending',
          'localeId': call.arguments['localeId'],
        };
      }
      return platformStatus;
    });
    service = ArabicSpeechModelService(channel: channel);
  });

  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> emit(Map<String, Object?> status) =>
      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('arabicModelStatus', status)),
        (_) {},
      );

  test(
    'download request is pending until OS confirms installed Arabic',
    () async {
      await service.refresh();
      expect(service.status.canDownload, isTrue);
      await service.download();
      expect(service.status.isPending, isTrue);
      expect(service.status.isInstalled, isFalse);
      expect(calls.last.arguments['localeId'], 'ar-SA');
      await emit({'status': 'pending', 'localeId': 'ar-SA', 'progress': 100});
      expect(service.status.isInstalled, isFalse);
      await emit({'status': 'installed', 'localeId': 'ar-SA'});
      expect(service.status.isInstalled, isTrue);
    },
  );

  testWidgets('pending downloads poll until installed and then stop', (
    tester,
  ) async {
    service.addListener(() {});
    await service.refresh();
    await service.download();
    platformStatus = {'status': 'installed', 'localeId': 'ar-EG'};
    await tester.pump(const Duration(seconds: 5));
    expect(service.status.isInstalled, isTrue);
    expect(service.status.localeId, 'ar-EG');
    final count = calls.length;
    await tester.pump(const Duration(seconds: 10));
    expect(calls.length, count);
  });

  testWidgets('polling stops without a visible consumer or in background', (
    tester,
  ) async {
    void listener() {}
    service.addListener(listener);
    await service.refresh();
    await service.download();
    service.removeListener(listener);
    final count = calls.length;
    await tester.pump(const Duration(seconds: 15));
    expect(calls.length, count);
    service.addListener(listener);
    service.setForeground(false);
    await tester.pump(const Duration(seconds: 15));
    expect(calls.length, count);
    service.setForeground(true);
    await tester.pump(const Duration(seconds: 5));
    expect(calls.length, count + 1);
    service.removeListener(listener);
  });

  test(
    'download waits for an older refresh and keeps its pending response',
    () async {
      await service.refresh();
      final refreshReply = Completer<Map<String, Object?>>();
      final downloadReply = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return call.method == 'downloadArabicModel'
            ? downloadReply.future
            : refreshReply.future;
      });
      final refresh = service.refresh();
      final download = service.download();
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c.method == 'downloadArabicModel'), isEmpty);
      refreshReply.complete({'status': 'downloadable', 'localeId': 'ar-SA'});
      await refresh;
      await Future<void>.delayed(Duration.zero);
      final concurrentRefresh = service.refresh();
      downloadReply.complete({'status': 'pending', 'localeId': 'ar-SA'});
      await Future.wait([download, concurrentRefresh]);
      expect(service.status.isPending, isTrue);
      expect(
        calls.where((c) => c.method == 'getArabicModelStatus'),
        hasLength(2),
      );
      expect(
        calls.where((c) => c.method == 'downloadArabicModel'),
        hasLength(1),
      );
    },
  );

  test('unsupported platforms never offer an unverified download', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await service.refresh();
    await service.download();
    expect(
      service.status.availability,
      ArabicSpeechModelAvailability.unsupported,
    );
    expect(service.status.isInstalled, isFalse);
    expect(calls, isEmpty);
  });

  test(
    'a recognition failure survives automatic probes until explicit recheck',
    () async {
      platformStatus = {'status': 'installed', 'localeId': 'ar-SA'};
      await service.refresh();
      service.offlineOnly = true;
      service.reportUnavailable();
      await service.refresh();
      expect(service.status.isInstalled, isFalse);
      expect(service.offlineOnly, isTrue);
      expect(calls, hasLength(1));
      await service.refresh(retryUnavailable: true);
      expect(service.status.isInstalled, isTrue);
      expect(calls, hasLength(2));
    },
  );

  test('failed downloads remain unavailable and can be rechecked', () async {
    await service.refresh();
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'network');
    });
    await service.download();
    expect(service.status.reason, 'downloadFailed');
    expect(service.status.isInstalled, isFalse);
    expect(service.isRequestingDownload, isFalse);
  });

  test(
    'an old support response cannot overwrite a completed download event',
    () async {
      final pending = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(channel, (_) => pending.future);
      final first = service.refresh();
      final second = service.refresh();
      await emit({'status': 'installed', 'localeId': 'ar-SA'});
      pending.complete({'status': 'pending', 'localeId': 'ar-SA'});
      await Future.wait([first, second]);
      expect(service.status.isInstalled, isTrue);
    },
  );

  test(
    'non-Arabic installed locales cannot enable offline recitation',
    () async {
      platformStatus = {'status': 'installed', 'localeId': 'en-US'};
      await service.refresh();
      expect(service.status.isInstalled, isFalse);
      expect(service.status.reason, 'invalidLocale');
    },
  );

  testWidgets('download button sends request and does not show false success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArabicSpeechModelSheet(
            service: service,
            openSettings: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحميل حزمة اللغة العربية'));
    await tester.pump();
    expect(calls.where((c) => c.method == 'downloadArabicModel'), hasLength(1));
    expect(
      find.textContaining('طلب تنزيل العربية قيد التنفيذ'),
      findsOneWidget,
    );
    expect(find.text('التسميع دون إنترنت فقط'), findsNothing);
    await emit({'status': 'installed', 'localeId': 'ar-SA'});
    await tester.pumpAndSettle();
    expect(find.text('التسميع دون إنترنت فقط'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(service.offlineOnly, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unsupported iOS explains limitation and offers settings', (
    tester,
  ) async {
    platformStatus = {'status': 'unsupported', 'reason': 'iosManagedBySystem'};
    var settingsOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArabicSpeechModelSheet(
            service: service,
            openSettings: () async {
              settingsOpened = true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('تحميل حزمة اللغة العربية'), findsNothing);
    expect(find.textContaining('iOS لا تتيح تنزيل'), findsOneWidget);
    await tester.tap(find.text('فتح إعدادات خدمة الصوت'));
    expect(settingsOpened, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
