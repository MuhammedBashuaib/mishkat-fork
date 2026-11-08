import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class _Decode {
  _Decode(this.pcm);

  final Uint8List pcm;
  final result = Completer<String>();
  int get audioMs => pcm.length * 1000 ~/ (16000 * 2);
}

/// Deterministic audio and decode timing, not a benchmark of native inference.
class _LatencyHarness {
  final audio = StreamController<Object?>.broadcast(sync: true);
  final decodes = <_Decode>[];
  int nowMs = 0;
  String? session;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'initialize':
      case 'hasPermission':
        return true;
      case 'start':
        session = (call.arguments as Map)['sessionId'] as String;
        return true;
      case 'stop':
      case 'release':
        return null;
      case 'transcribe':
        final decode = _Decode(
          Uint8List.fromList((call.arguments as Map)['pcm'] as Uint8List),
        );
        decodes.add(decode);
        return decode.result.future;
      default:
        throw StateError('Unexpected call ${call.method}');
    }
  }

  void feed(int durationMs, {int amplitude = 1000}) {
    var remainingMs = durationMs;
    while (remainingMs > 0) {
      final frameMs = remainingMs.clamp(1, 30);
      final sampleCount = frameMs * 16;
      final bytes = ByteData(sampleCount * 2);
      for (var i = 0; i < sampleCount; i++) {
        bytes.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
      }
      nowMs += frameMs;
      audio.add({
        'type': 'audio',
        'sessionId': session,
        'pcm': bytes.buffer.asUint8List(),
      });
      remainingMs -= frameMs;
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
  const channel = MethodChannel('test/mishkat_latency');
  late _LatencyHarness native;
  late OfflineSpeechRecognitionService service;
  late List<SpeechRecognitionResultData> results;
  late List<SpeechRecognitionFailure> failures;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native = _LatencyHarness();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.handle);
    service = OfflineSpeechRecognitionService(
      channel: channel,
      audioEvents: native.audio.stream,
      clockMs: () => native.nowMs,
    );
    results = [];
    failures = [];
    service.resultsStream.listen(results.add);
    service.errorStream.listen(failures.add);
    expect(await service.startListening(), isTrue);
  });

  tearDown(() async {
    await service.cancelListening();
    for (final decode in native.decodes) {
      if (!decode.result.isCompleted) decode.result.complete('');
    }
    await _settle();
    await service.dispose();
    await native.audio.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'first preview starts at 900ms and a busy decoder takes fresh audio',
    () async {
      native.feed(870);
      await _settle();
      expect(native.decodes, isEmpty);

      native.feed(30);
      await _settle();
      expect(native.decodes.single.audioMs, 900);
      expect(service.isListening, isTrue);

      native.feed(3000);
      await _settle();
      expect(native.decodes, hasLength(1));
      native.decodes.first.result.complete('الحمد');
      await _settle();

      expect(native.decodes, hasLength(2));
      expect(native.decodes.last.audioMs, 3900);
      expect(results.single.isFinal, isFalse);
      expect(failures, isEmpty);
    },
  );

  test('a 600ms decode leaves only 60ms of extra cadence wait', () async {
    native.feed(900);
    await _settle();
    native.feed(600);
    native.decodes.single.result.complete('الحمد');
    await _settle();
    expect(native.decodes, hasLength(1));

    native.feed(30);
    await _settle();
    expect(native.decodes, hasLength(1));
    native.feed(30);
    await _settle();
    expect(native.decodes, hasLength(2));
    expect(native.decodes.last.audioMs, 1560);
    expect(failures, isEmpty);
  });

  test(
    'a slow earlier utterance does not delay the next first preview',
    () async {
      native.feed(900);
      await _settle();
      native.feed(1200);
      native.feed(420, amplitude: 0);
      native.decodes.single.result.complete('الحمد لله');
      await _settle();
      // The final takes priority over the continuous preview that was waiting.
      expect(native.decodes, hasLength(2));
      expect(native.decodes.last.audioMs, 2310);
      expect(results, isEmpty);
      native.decodes.last.result.complete('الحمد لله رب العالمين');
      await _settle();
      expect(results.single.isFinal, isTrue);

      // A natural boundary retains 210ms of pre-roll. The next first preview
      // should start at 900ms buffered audio despite the previous slow decode.
      native.feed(660);
      await _settle();
      expect(native.decodes, hasLength(2));
      native.feed(30);
      await _settle();
      expect(native.decodes, hasLength(3));
      expect(native.decodes.last.audioMs, 900);
      expect(failures, isEmpty);
    },
  );

  test(
    'post-roll starts analysis before VAD final and identical PCM is reused',
    () async {
      native.feed(600);
      native.feed(180, amplitude: 0);
      await _settle();
      expect(native.decodes, isEmpty);
      native.feed(30, amplitude: 0);
      await _settle();
      expect(native.decodes.single.audioMs, 810);

      native.decodes.single.result.complete('الحمد لله رب العالمين');
      await _settle();
      expect(results, hasLength(1));
      expect(results.single.isFinal, isFalse);

      native.feed(210, amplitude: 0);
      await _settle();
      expect(native.decodes, hasLength(1));
      expect(results.map((result) => result.isFinal), [false, true]);
      expect(results.last.recognizedWords, 'الحمد لله رب العالمين');
      expect(service.isListening, isTrue);
      expect(failures, isEmpty);
    },
  );

  test(
    'in-flight pause candidate becomes only one final after VAD confirms it',
    () async {
      native.feed(600);
      native.feed(210, amplitude: 0);
      await _settle();
      expect(native.decodes.single.audioMs, 810);
      native.feed(210, amplitude: 0);
      await _settle();
      expect(results, isEmpty);

      native.decodes.single.result.complete('الحمد لله رب العالمين');
      await _settle();
      expect(native.decodes, hasLength(1));
      expect(results.single.isFinal, isTrue);
      expect(results.single.recognizedWords, 'الحمد لله رب العالمين');
      expect(service.isListening, isTrue);
      expect(failures, isEmpty);
    },
  );

  test(
    'resumed speech must be decoded and never finalized from an earlier pause',
    () async {
      native.feed(600);
      native.feed(210, amplitude: 0);
      await _settle();
      native.feed(300);
      native.feed(420, amplitude: 0);
      await _settle();

      native.decodes.first.result.complete('الحمد لله');
      await _settle();
      expect(results, isEmpty);
      expect(native.decodes, hasLength(2));
      expect(native.decodes.last.audioMs, 1320);
      native.decodes.last.result.complete('الحمد لله رب العالمين');
      await _settle();
      expect(results.single.isFinal, isTrue);
      expect(results.single.recognizedWords, 'الحمد لله رب العالمين');
      expect(failures, isEmpty);
    },
  );

  test(
    'cancel clears cached audio even when the next session sounds identical',
    () async {
      native.feed(600);
      native.feed(210, amplitude: 0);
      await _settle();
      native.decodes.single.result.complete('كلام من جلسة سابقة');
      await _settle();
      expect(results.single.isFinal, isFalse);
      await service.cancelListening();
      expect(await service.startListening(), isTrue);
      results.clear();

      native.feed(600);
      native.feed(420, amplitude: 0);
      await _settle();
      expect(native.decodes, hasLength(2));
      expect(native.decodes.last.pcm, orderedEquals(native.decodes.first.pcm));
      expect(results, isEmpty);
      native.decodes.last.result.complete('الحمد لله رب العالمين');
      await _settle();
      expect(results.single.isFinal, isTrue);
      expect(results.single.recognizedWords, 'الحمد لله رب العالمين');
      expect(failures, isEmpty);
    },
  );

  test(
    'stop includes a partial audio frame instead of reusing a shorter preview',
    () async {
      native.feed(600);
      native.feed(210, amplitude: 0);
      await _settle();
      native.decodes.single.result.complete('الحمد لله');
      await _settle();
      native.feed(10);
      final stop = service.stopListening();
      await _settle();
      expect(native.decodes, hasLength(2));
      expect(native.decodes.last.audioMs, 840);
      expect(results.every((result) => !result.isFinal), isTrue);

      native.decodes.last.result.complete('الحمد لله رب');
      await stop;
      expect(results.last.isFinal, isTrue);
      expect(results.last.recognizedWords, 'الحمد لله رب');
      expect(service.isListening, isFalse);
      expect(failures, isEmpty);
    },
  );
}
