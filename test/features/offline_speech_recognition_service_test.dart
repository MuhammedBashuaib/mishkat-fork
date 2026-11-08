import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class _OfflineHarness {
  final audio = StreamController<Object?>.broadcast(sync: true);
  final calls = <MethodCall>[];
  String? session;
  bool permission = true;
  Completer<bool>? loading;
  Completer<bool>? starting;
  Completer<String>? decoding;
  final texts = <String>['الحمد لله رب العالمين', 'الرحمن الرحيم'];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'initialize':
        return loading?.future ?? true;
      case 'hasPermission':
        return permission;
      case 'start':
        session = (call.arguments as Map)['sessionId'] as String;
        return starting?.future ?? true;
      case 'stop':
        if ((call.arguments as Map)['sessionId'] == session) session = null;
        return null;
      case 'transcribe':
        return decoding?.future ?? texts.removeAt(0);
      case 'release':
        return null;
      default:
        throw StateError('Unexpected call ${call.method}');
    }
  }

  void packet(int amplitude, {String? sessionId}) {
    final bytes = ByteData(3200);
    for (var i = 0; i < 1600; i++) {
      bytes.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
    }
    audio.add({
      'type': 'audio',
      'sessionId': sessionId ?? session,
      'pcm': bytes.buffer.asUint8List(),
      'level': amplitude == 0 ? 0.0 : .5,
    });
  }

  void utterance({bool pause = true}) {
    // Keep lifecycle fixtures below the 900ms continuous-preview threshold,
    // including up to 300ms of pre-roll retained from the previous pause.
    for (var i = 0; i < 5; i++) {
      packet(1000);
    }
    if (pause) {
      for (var i = 0; i < 6; i++) {
        packet(0);
      }
    }
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/mishkat_offline_asr');
  late _OfflineHarness native;
  late OfflineSpeechRecognitionService service;
  late List<SpeechRecognitionResultData> results;
  late List<SpeechRecognitionFailure> failures;
  late List<String> statuses;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native = _OfflineHarness();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.handle);
    service = OfflineSpeechRecognitionService(
      channel: channel,
      audioEvents: native.audio.stream,
    );
    results = [];
    failures = [];
    statuses = [];
    service.resultsStream.listen(results.add);
    service.errorStream.listen(failures.add);
    service.statusStream.listen(statuses.add);
  });

  tearDown(() async {
    await service.dispose();
    await native.audio.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('completed pauses emit separate final segments without restarting microphone', () async {
    expect(
      await service.startListening(contextualPhrases: ['expected Quran text']),
      isTrue,
    );
    native.utterance();
    await _settle();
    native.utterance();
    await _settle();
    expect(results.map((result) => result.recognizedWords), [
      'الحمد لله رب العالمين',
      'الرحمن الرحيم',
    ]);
    expect(results.every((result) => result.isFinal), isTrue);
    expect(failures, isEmpty);
    expect(statuses, ['listening']);
    expect(service.isListening, isTrue);
    expect(native.calls.where((call) => call.method == 'start'), hasLength(1));
    expect(
      native.calls
          .where((call) => call.method == 'transcribe')
          .every(
            (call) => (call.arguments as Map).keys.toSet().containsAll([
              'pcm',
              'sessionId',
            ]),
          ),
      isTrue,
    );
    expect(
      native.calls.any(
        (call) => call.arguments.toString().contains('expected Quran text'),
      ),
      isFalse,
    );
  });

  test(
    'stop flushes unfinished speech and awaits its result before done',
    () async {
      await service.startListening();
      native.decoding = Completer<String>();
      native.utterance(pause: false);
      var stopped = false;
      final stop = service.stopListening().then((_) {
        stopped = true;
      });
      await _settle();
      expect(stopped, isFalse);
      expect(results, isEmpty);
      native.decoding!.complete('مالك يوم الدين');
      await stop;
      expect(results.single.recognizedWords, 'مالك يوم الدين');
      expect(statuses.last, 'done');
      expect(service.isListening, isFalse);
    },
  );

  test('cancel discards a decode already in flight and late PCM', () async {
    await service.startListening();
    final oldSession = native.session;
    native.decoding = Completer<String>();
    native.utterance();
    await _settle();
    await service.cancelListening();
    native.packet(1000, sessionId: oldSession);
    native.decoding!.complete('نص من جلسة ملغاة');
    await _settle();
    expect(results, isEmpty);
    expect(service.isListening, isFalse);
    expect(failures, isEmpty);
  });

  test('late microphone startup cannot reopen after cancellation', () async {
    native.starting = Completer<bool>();
    final startup = service.startListening();
    await _settle();
    expect(native.session, isNotNull);
    await service.cancelListening();
    native.starting!.complete(true);
    expect(await startup, isFalse);
    expect(native.session, isNull);
    expect(service.isListening, isFalse);
    expect(statuses, isEmpty);
  });

  test(
    'stop while model is loading prevents subsequent microphone acquisition',
    () async {
      native.loading = Completer<bool>();
      final startup = service.startListening();
      await _settle();
      await service.stopListening();
      native.loading!.complete(true);
      expect(await startup, isFalse);
      expect(native.calls.where((call) => call.method == 'start'), isEmpty);
    },
  );

  test(
    'room-noise pause publishes a final while microphone stays open',
    () async {
      await service.startListening();
      for (var i = 0; i < 5; i++) {
        native.packet(100);
      }
      for (var i = 0; i < 10; i++) {
        native.packet(1600);
      }
      for (var i = 0; i < 9; i++) {
        native.packet(100);
      }
      await _settle();
      expect(results.where((value) => value.isFinal), hasLength(1));
      expect(service.isListening, isTrue);
      expect(native.calls.where((call) => call.method == 'stop'), isEmpty);
    },
  );

  test('connected reading publishes previews before its first pause', () async {
    await service.startListening();
    for (var i = 0; i < 10; i++) {
      native.packet(1200);
    }
    await _settle();
    expect(results, hasLength(1));
    expect(results.single.isFinal, isFalse);
    expect(service.isListening, isTrue);
    expect(native.calls.where((call) => call.method == 'stop'), isEmpty);
    for (var i = 0; i < 6; i++) {
      native.packet(0);
    }
    await _settle();
    expect(results.last.isFinal, isTrue);
    expect(results, hasLength(2));
    expect(service.isListening, isTrue);
    expect(failures, isEmpty);
  });

  test(
    'closed speech outranks pending previews and discards stale preview decode',
    () async {
      await service.startListening();
      final pending = native.decoding = Completer<String>();
      for (var i = 0; i < 10; i++) {
        native.packet(1200);
      }
      await _settle();
      for (var i = 0; i < 40; i++) {
        native.packet(1200);
      }
      expect(
        native.calls.where((call) => call.method == 'transcribe'),
        hasLength(1),
      );
      for (var i = 0; i < 6; i++) {
        native.packet(0);
      }
      native.decoding = null;
      pending.complete('معاينة قديمة');
      await _settle();
      expect(results, hasLength(1));
      expect(results.single.isFinal, isTrue);
      expect(results.single.recognizedWords, 'الحمد لله رب العالمين');
      expect(
        native.calls.where((call) => call.method == 'transcribe'),
        hasLength(2),
      );
      expect(service.isListening, isTrue);
    },
  );

  test(
    'cancel discards an in-flight preview and its coalesced successor',
    () async {
      await service.startListening();
      native.decoding = Completer<String>();
      for (var i = 0; i < 10; i++) {
        native.packet(1200);
      }
      await _settle();
      for (var i = 0; i < 30; i++) {
        native.packet(1200);
      }
      await service.cancelListening();
      native.decoding!.complete('نتيجة جلسة ملغاة');
      await _settle();
      expect(results, isEmpty);
      expect(
        native.calls.where((call) => call.method == 'transcribe'),
        hasLength(1),
      );
    },
  );

  test('silence never invokes decoding or creates a transcript', () async {
    await service.startListening();
    for (var i = 0; i < 80; i++) {
      native.packet(0);
    }
    await service.stopListening();
    expect(results, isEmpty);
    expect(native.calls.where((call) => call.method == 'transcribe'), isEmpty);
  });

  test(
    'slow decoding has a bounded queue and explicitly pauses capture',
    () async {
      await service.startListening();
      native.decoding = Completer<String>();
      native.utterance();
      await _settle();
      for (var i = 0; i < 6; i++) {
        native.utterance();
      }
      await _settle();
      expect(service.isListening, isFalse);
      expect(failures.single.message, contains('آخر كلمة مؤكدة'));
      native.decoding!.complete('نص متأخر');
      await _settle();
      expect(results, isEmpty);
      expect(
        native.calls.where((call) => call.method == 'transcribe'),
        hasLength(1),
      );
    },
  );

  test(
    'overlapping pages share native events until the last owner disposes',
    () async {
      const eventsChannel = MethodChannel(
        'com.dakomn.mishkatapp/offline_recitation/audio',
      );
      final eventCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(eventsChannel, (call) async {
            eventCalls.add(call.method);
            return null;
          });
      final oldPage = OfflineSpeechRecognitionService(channel: channel);
      final newPage = OfflineSpeechRecognitionService(channel: channel);
      try {
        await oldPage.initialize();
        await newPage.initialize();
        await _settle();
        expect(eventCalls, ['listen']);
        await oldPage.dispose();
        expect(eventCalls, ['listen']);
        await newPage.dispose();
        expect(eventCalls, ['listen', 'cancel']);
      } finally {
        await oldPage.dispose();
        await newPage.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(eventsChannel, null);
      }
    },
  );

  test('permission failure never opens audio capture', () async {
    native.permission = false;
    expect(await service.startListening(), isFalse);
    expect(failures.single.type, SpeechRecognitionFailureType.permissionDenied);
    expect(native.calls.where((call) => call.method == 'start'), isEmpty);
  });

  test(
    'unsupported platforms remain explicitly unavailable without fallback',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await service.initialize(), isFalse);
      expect(
        failures.single.type,
        SpeechRecognitionFailureType.languageUnavailable,
      );
      expect(native.calls, isEmpty);
    },
  );
}
