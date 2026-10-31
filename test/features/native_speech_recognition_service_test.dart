import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/presentation/services/arabic_speech_model_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';
import 'package:speech_to_text/speech_to_text.dart';

// Exercise the production SpeechToText wrapper, including its singleton-style
// initialization and the platform bool that listen() itself discards.
class _NativeSpeechHarness {
  static const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  final calls = <MethodCall>[];
  Future<bool>? initialization;
  Future<bool>? listenResponse;
  Future<bool>? cancelResponse;
  Future<bool>? stopResponse;
  Future<List<String>>? localeResponse;
  bool acknowledgeListen = true;
  bool acceptListen = true;
  PlatformException? listenFailure;

  int count(String method) =>
      calls.where((call) => call.method == method).length;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'initialize':
        return initialization ?? true;
      case 'locales':
        return localeResponse ?? ['ar_SA:Arabic', 'en_US:English'];
      case 'listen':
        if (listenFailure != null) throw listenFailure!;
        if (acknowledgeListen) await emit('notifyStatus', 'listening');
        return listenResponse ?? acceptListen;
      case 'cancel':
        return cancelResponse ?? true;
      case 'stop':
        return stopResponse ?? true;
      default:
        throw StateError('Unexpected native speech call: ${call.method}');
    }
  }

  Future<void> emit(String method, Object argument) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, argument)),
          (_) {},
        );
  }

  Future<void> emitError(String error) =>
      emit('notifyError', jsonEncode({'errorMsg': error, 'permanent': true}));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _NativeSpeechHarness native;
  late SpeechToText engine;
  late NativeSpeechRecognitionService service;
  late ArabicSpeechModelService modelService;
  var modelStatus = <String, Object?>{'status': 'unknown'};
  const modelChannel = MethodChannel('test/arabic_speech_models');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native = _NativeSpeechHarness();
    modelStatus = {'status': 'unknown'};
    modelService = ArabicSpeechModelService(channel: modelChannel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(modelChannel, (_) async => modelStatus);
    engine = SpeechToText.withMethodChannel();
    service = NativeSpeechRecognitionService(
      speechToText: engine,
      arabicModelService: modelService,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_NativeSpeechHarness.channel, native.handle);
  });

  tearDown(() async {
    await service.dispose();
    modelService.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_NativeSpeechHarness.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(modelChannel, null);
  });

  void speechTest(String name, Future<void> Function() body) {
    test(name, () async {
      try {
        await body();
      } finally {
        await service.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  speechTest(
    'Android starts Arabic without waiting for on-device locales',
    () async {
      native.localeResponse = Completer<List<String>>().future;

      expect(
        await service.startListening(contextualPhrases: ['الحمد لله']),
        isTrue,
      );
      expect(native.count('locales'), 0);
      final options =
          native.calls.singleWhere((c) => c.method == 'listen').arguments
              as Map;
      expect(options['localeId'], 'ar-SA');
      expect(options['onDevice'], isFalse);
      expect(options['contextualPhrases'], ['الحمد لله']);
      final initialization =
          native.calls.singleWhere((c) => c.method == 'initialize').arguments
              as Map;
      expect(initialization['noBluetooth'], isTrue);
      expect(initialization['intentLookup'], isNull);
      await service.dispose();
    },
  );

  speechTest(
    'Android language recheck does not reject online Arabic',
    () async {
      native.localeResponse = Future.value(['en_US:English']);

      expect(await service.hasArabicLocale(), isNull);
      expect(native.count('locales'), 0);
      expect(await service.startListening(), isTrue);
      await service.dispose();
    },
  );

  speechTest(
    'delayed listening callback acknowledges successful startup',
    () async {
      native.acknowledgeListen = false;
      var completed = false;
      final start = service.startListening().then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(native.count('listen'), 1);
      expect(completed, isFalse);

      await native.emit('notifyStatus', 'listening');
      expect(await start, isTrue);
      await service.dispose();
    },
  );

  speechTest(
    'silent platform rejection times out and releases capture',
    () async {
      native.acknowledgeListen = false;
      native.acceptListen = false;
      final failures = <SpeechRecognitionFailure>[];
      final subscription = service.errorStream.listen(failures.add);
      bool? started;
      unawaited(service.startListening().then((value) => started = value));
      await Future<void>.delayed(Duration.zero);

      await Future<void>.delayed(const Duration(seconds: 7));

      expect(started, isFalse);
      expect(failures, hasLength(1));
      expect(failures.single.message, contains('لم تبدأ'));

      expect(native.count('cancel'), 1);
      await subscription.cancel();

      await service.dispose();
    },
  );

  speechTest(
    'cancelling before listening acknowledgement stops native capture',
    () async {
      native.acknowledgeListen = false;
      final statuses = <String>[];
      final subscription = service.statusStream.listen(statuses.add);
      final start = service.startListening();
      await Future<void>.delayed(Duration.zero);
      expect(service.isListening, isFalse);

      await service.cancelListening();
      expect(await start, isFalse);
      expect(native.count('cancel'), 1);
      await native.emit('notifyStatus', 'listening');
      await Future<void>.delayed(Duration.zero);
      expect(statuses, isEmpty);
      expect(service.isListening, isFalse);
      await subscription.cancel();
      await service.dispose();
    },
  );

  speechTest(
    'pausing before listening acknowledgement stops pending request',
    () async {
      native.acknowledgeListen = false;
      final start = service.startListening();
      await Future<void>.delayed(Duration.zero);

      await service.stopListening();
      expect(await start, isFalse);
      expect(native.count('stop'), 1);
      await service.dispose();
    },
  );

  speechTest(
    'cancelling during locale lookup never opens microphone later',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final locales = Completer<List<String>>();
      native.localeResponse = locales.future;
      final start = service.startListening();
      await Future<void>.delayed(Duration.zero);
      expect(native.count('locales'), 1);

      await service.cancelListening();
      locales.complete(['ar_SA:Arabic']);
      expect(await start, isFalse);
      expect(native.count('listen'), 0);
      await service.dispose();
    },
  );

  speechTest(
    'unresponsive locale lookup on other platforms has a deadline',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      native.localeResponse = Completer<List<String>>().future;
      final start = service.startListening();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(await start, isTrue);
      expect(native.count('listen'), 1);
      await service.dispose();
    },
  );

  speechTest(
    'reopening a page rebinds an already initialized speech engine',
    () async {
      expect(await service.startListening(), isTrue);
      await service.dispose();
      service = NativeSpeechRecognitionService(
        speechToText: engine,
        arabicModelService: modelService,
      );
      final statuses = <String>[];
      final failures = <SpeechRecognitionFailure>[];
      final statusSubscription = service.statusStream.listen(statuses.add);
      final errorSubscription = service.errorStream.listen(failures.add);

      expect(await service.startListening(), isTrue);
      await native.emitError('error_audio_error');
      await Future<void>.delayed(Duration.zero);
      expect(native.count('initialize'), 1);
      expect(statuses, contains('listening'));
      expect(failures.single.type, SpeechRecognitionFailureType.audio);
      await statusSubscription.cancel();
      await errorSubscription.cancel();
      await service.dispose();
    },
  );

  speechTest(
    'late disposal of an old page cannot cancel the replacement capture',
    () async {
      expect(await service.startListening(), isTrue);
      final oldService = service;
      service = NativeSpeechRecognitionService(
        speechToText: engine,
        arabicModelService: modelService,
      );
      expect(await service.startListening(), isTrue);
      final cancellationCount = native.count('cancel');
      await oldService.dispose();

      expect(native.count('cancel'), cancellationCount);
      expect(service.isListening, isTrue);
    },
  );

  speechTest(
    'concurrent initialization and startup use one native request',
    () async {
      final initialization = Completer<bool>();
      native.initialization = initialization.future;
      final first = service.initialize();
      final second = service.initialize();
      final start = service.startListening();
      final repeatedStart = service.startListening();
      await Future<void>.delayed(Duration.zero);
      expect(native.count('initialize'), 1);

      initialization.complete(true);
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(await start, isTrue);
      expect(await repeatedStart, isTrue);
      expect(native.count('listen'), 1);
      await service.dispose();
    },
  );

  speechTest(
    'late native listen completion is cleaned up after cancellation',
    () async {
      native.acknowledgeListen = false;
      final nativeReply = Completer<bool>();
      native.listenResponse = nativeReply.future;
      final start = service.startListening();
      await Future<void>.delayed(Duration.zero);

      await service.cancelListening();
      nativeReply.complete(true);
      expect(await start, isFalse);
      // The second cancellation clears timers the plugin installs only after
      // the late platform reply, without requiring isListening to be true.
      expect(native.count('cancel'), 2);
      expect(service.isListening, isFalse);
      await service.dispose();
    },
  );

  speechTest(
    'disposing during initialization cannot start microphone afterwards',
    () async {
      final initialization = Completer<bool>();
      native.initialization = initialization.future;
      final start = service.startListening();
      await Future<void>.delayed(Duration.zero);
      await service.dispose();
      initialization.complete(true);

      expect(await start, isFalse);
      expect(native.count('listen'), 0);
      expect(service.isAvailable, isFalse);
    },
  );

  speechTest(
    'native startup error preserves specific failure classification',
    () async {
      native.acknowledgeListen = false;
      final failures = <SpeechRecognitionFailure>[];
      final subscription = service.errorStream.listen(failures.add);
      final start = service.startListening();
      await Future<void>.delayed(Duration.zero);

      await native.emitError('error_language_unavailable');
      expect(await start, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(
        failures.single.type,
        SpeechRecognitionFailureType.languageUnavailable,
      );
      await subscription.cancel();

      await service.dispose();
    },
  );

  speechTest(
    'resume waits until previous cancellation releases the engine',
    () async {
      expect(await service.startListening(), isTrue);
      final cancellation = Completer<bool>();
      native.cancelResponse = cancellation.future;
      final cancel = service.cancelListening();
      final resume = service.startListening();
      await Future<void>.delayed(Duration.zero);

      expect(native.count('listen'), 1);
      cancellation.complete(true);
      await cancel;
      expect(await resume, isTrue);
      expect(native.count('listen'), 2);
      expect(service.isListening, isTrue);
    },
  );

  speechTest(
    'terminal failure ignores late status and duplicate error callbacks',
    () async {
      final statuses = <String>[];
      final failures = <SpeechRecognitionFailure>[];
      final statusSubscription = service.statusStream.listen(statuses.add);
      final errorSubscription = service.errorStream.listen(failures.add);
      expect(await service.startListening(), isTrue);
      await native.emitError('error_network');
      await native.emit('notifyStatus', 'notListening');
      await native.emit('notifyStatus', 'doneNoResult');
      await native.emitError('error_client');
      await Future<void>.delayed(Duration.zero);

      expect(statuses, ['listening']);
      expect(failures.single.type, SpeechRecognitionFailureType.network);
      expect(native.count('cancel'), 1);
      expect(service.isListening, isFalse);
      await statusSubscription.cancel();
      await errorSubscription.cancel();
    },
  );

  speechTest(
    'installed Arabic model uses its exact locale and local recognizer',
    () async {
      modelStatus = {'status': 'installed', 'localeId': 'ar-EG'};
      expect(await service.startListening(), isTrue);
      final options =
          native.calls.singleWhere((c) => c.method == 'listen').arguments
              as Map;
      expect(options['onDevice'], isTrue);
      expect(options['localeId'], 'ar-EG');
    },
  );

  speechTest(
    'offline-only without verified Arabic never starts online capture',
    () async {
      modelService.offlineOnly = true;
      modelStatus = {'status': 'downloadable', 'localeId': 'ar-SA'};
      final failures = <SpeechRecognitionFailure>[];
      final subscription = service.errorStream.listen(failures.add);

      expect(await service.startListening(), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(native.count('listen'), 0);
      expect(
        failures.single.type,
        SpeechRecognitionFailureType.languageUnavailable,
      );
      await subscription.cancel();
    },
  );

  speechTest(
    'downloaded model is used on resume without reopening the page',
    () async {
      expect(await service.startListening(), isTrue);
      await service.stopListening();
      modelStatus = {'status': 'installed', 'localeId': 'ar-SA'};
      await modelService.refresh();
      modelService.offlineOnly = true;

      expect(await service.startListening(), isTrue);
      final options =
          native.calls.lastWhere((c) => c.method == 'listen').arguments as Map;
      expect(options['onDevice'], isTrue);
    },
  );

  for (final entry in {
    'error_speech_recognizer_already_active': SpeechRecognitionFailureType.busy,
    'error_speech_recognizer_connection_invalidated':
        SpeechRecognitionFailureType.network,
    'error_speech_recognizer_connection_interrupted':
        SpeechRecognitionFailureType.network,
    'error_assets_not_installed':
        SpeechRecognitionFailureType.languageUnavailable,
    'error_speech_recognizer_request_not_authorized':
        SpeechRecognitionFailureType.permissionDenied,
  }.entries) {
    speechTest(
      'iOS ${entry.key} preserves its actionable failure type',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final failures = <SpeechRecognitionFailure>[];
        final subscription = service.errorStream.listen(failures.add);
        expect(await service.startListening(), isTrue);
        await native.emitError(entry.key);
        await Future<void>.delayed(Duration.zero);
        expect(failures.single.type, entry.value);
        expect(service.isListening, isFalse);
        await subscription.cancel();
      },
    );
  }

  speechTest(
    'a removed local model reports language failure without online fallback',
    () async {
      modelStatus = {'status': 'installed', 'localeId': 'ar-SA'};
      modelService.offlineOnly = true;
      native.listenFailure = PlatformException(code: 'onDeviceError');
      final failures = <SpeechRecognitionFailure>[];
      final subscription = service.errorStream.listen(failures.add);

      expect(await service.startListening(), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(
        failures.single.type,
        SpeechRecognitionFailureType.languageUnavailable,
      );
      expect(modelService.status.isInstalled, isFalse);
      expect(modelService.status.reason, 'modelUnavailable');
      expect(modelService.offlineOnly, isTrue);
      final calls = native.calls
          .where((call) => call.method == 'listen')
          .toList();
      expect(calls, hasLength(1));
      expect((calls.single.arguments as Map)['onDevice'], isTrue);
      await subscription.cancel();
    },
  );

  for (final offlineOnly in [false, true]) {
    speechTest(
      'missing iOS assets invalidate readiness across reopening (offlineOnly=$offlineOnly)',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        modelStatus = {'status': 'installed', 'localeId': 'ar-SA'};
        modelService.offlineOnly = offlineOnly;
        expect(await service.startListening(), isTrue);
        await native.emitError('error_assets_not_installed');
        await Future<void>.delayed(Duration.zero);
        expect(modelService.status.isInstalled, isFalse);
        expect(modelService.status.reason, 'modelUnavailable');
        expect(modelService.offlineOnly, offlineOnly);

        await service.dispose();
        service = NativeSpeechRecognitionService(
          speechToText: engine,
          arabicModelService: modelService,
        );
        expect(await service.startListening(), !offlineOnly);
        expect(modelService.status.isInstalled, isFalse);
        final calls = native.calls
            .where((call) => call.method == 'listen')
            .toList();
        expect(calls, hasLength(offlineOnly ? 1 : 2));
        if (!offlineOnly) {
          expect((calls.last.arguments as Map)['onDevice'], isFalse);
        }
      },
    );
  }
}
