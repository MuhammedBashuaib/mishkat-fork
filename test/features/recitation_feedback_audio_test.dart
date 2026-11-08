import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_segmenter.dart';

const _cues = ['ready', 'mistake', 'corrected', 'paused', 'complete'];

/// Reads the actual shipped WAV, including any optional RIFF chunks.
/// These are direct PCM tests, not speaker/microphone or acoustic echo tests.
Future<Int16List> _cuePcm(String cue, {int gain = 1}) async {
  final bytes = await File('assets/audio/recitation_$cue.wav').readAsBytes();
  final data = ByteData.sublistView(bytes);
  String tag(int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
  expect(tag(0), 'RIFF');
  expect(tag(8), 'WAVE');
  var offset = 12;
  var validFormat = false;
  Uint8List? audio;
  while (offset + 8 <= bytes.length) {
    final kind = tag(offset);
    final size = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    expect(start + size, lessThanOrEqualTo(bytes.length));
    if (kind == 'fmt ') {
      expect(size, greaterThanOrEqualTo(16));
      expect(data.getUint16(start, Endian.little), 1, reason: 'PCM encoding');
      expect(data.getUint16(start + 2, Endian.little), 1, reason: 'mono');
      expect(data.getUint32(start + 4, Endian.little), 16000);
      expect(data.getUint16(start + 12, Endian.little), 2);
      expect(data.getUint16(start + 14, Endian.little), 16);
      validFormat = true;
    } else if (kind == 'data') {
      audio = Uint8List.sublistView(bytes, start, start + size);
    }
    offset = start + size + (size.isOdd ? 1 : 0);
  }
  expect(validFormat, isTrue);
  expect(audio, isNotNull);
  expect(audio!.length.isEven, isTrue);
  final encoded = ByteData.sublistView(audio);
  final pcm = Int16List(audio.length ~/ 2);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (encoded.getInt16(i * 2, Endian.little) * gain).clamp(
      -32768,
      32767,
    );
  }
  expect(pcm.any((sample) => sample != 0), isTrue);
  return pcm;
}

Int16List _silence(int milliseconds) => Int16List(milliseconds * 16);

/// Deliberately synthetic voice-shaped frames. They exercise PCM preservation
/// and VAD scheduling, without making claims about recognition accuracy.
Int16List _voice(int milliseconds, {int seed = 1}) => Int16List.fromList([
  for (var i = 0; i < milliseconds * 16; i++)
    (i.isEven ? 1 : -1) * (900 + ((i * seed) % 61) * 17),
]);

Iterable<Int16List> _packets(
  Int16List samples, {
  int packetSamples = 480,
}) sync* {
  for (var offset = 0; offset < samples.length; offset += packetSamples) {
    final end = (offset + packetSamples).clamp(0, samples.length);
    yield Int16List.sublistView(samples, offset, end);
  }
}

class _AudioHarness {
  final audio = StreamController<Object?>.broadcast(sync: true);
  final methods = <String>[];
  final decodedPcm = <Int16List>[];
  String? session;
  Completer<void>? stopBarrier;
  int nowMs = 0;

  Future<Object?> handle(MethodCall call) async {
    methods.add(call.method);
    switch (call.method) {
      case 'initialize':
      case 'hasPermission':
        return true;
      case 'start':
        session = (call.arguments as Map)['sessionId'] as String;
        return true;
      case 'stop':
        await stopBarrier?.future;
        return null;
      case 'release':
        return null;
      case 'transcribe':
        final bytes = ByteData.sublistView(
          (call.arguments as Map)['pcm'] as Uint8List,
        );
        final pcm = Int16List(bytes.lengthInBytes ~/ 2);
        for (var i = 0; i < pcm.length; i++) {
          pcm[i] = bytes.getInt16(i * 2, Endian.little);
        }
        final id = decodedPcm.length;
        decodedPcm.add(pcm);
        // Distinguish final decoding from previews, including exact-PCM reuse.
        return 'decoded-$id';
      default:
        throw StateError('Unexpected method ${call.method}');
    }
  }

  void packet(Int16List pcm) {
    final bytes = ByteData(pcm.length * 2);
    for (var i = 0; i < pcm.length; i++) {
      bytes.setInt16(i * 2, pcm[i], Endian.little);
    }
    nowMs += pcm.length ~/ 16;
    audio.add({
      'type': 'audio',
      'sessionId': session,
      'pcm': bytes.buffer.asUint8List(),
    });
  }

  void feed(Int16List pcm) {
    for (final part in _packets(pcm)) {
      packet(part);
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

  for (final cue in _cues) {
    for (final gain in [1, 2]) {
      test(
        '$cue WAV at encoded amplitude ×$gain cannot form a speech segment alone',
        () async {
          final segmenter = SpeechSegmenter();
          final pcm = await _cuePcm(cue, gain: gain);
          expect(pcm.length * 1000 / 16000, lessThan(segmenter.minVoicedMs));
          final segments = <SpeechSegment>[];
          for (final part in [_silence(600), pcm, _silence(600)]) {
            for (final packet in _packets(part, packetSamples: 1600)) {
              segments.addAll(segmenter.push(packet));
              expect(segmenter.snapshot(), isNull);
              expect(segmenter.pauseSnapshot(), isNull);
            }
          }
          final tail = segmenter.flush();
          if (tail != null) segments.add(tail);
          expect(segments, isEmpty);
        },
      );
    }
  }

  group('offline service quiet diagnostics', () {
    const channel = MethodChannel('test/mishkat_feedback_audio');
    late _AudioHarness native;
    late OfflineSpeechRecognitionService service;
    late List<bool> quiet;
    late List<SpeechRecognitionResultData> results;
    late List<SpeechRecognitionFailure> errors;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      native = _AudioHarness();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, native.handle);
      service = OfflineSpeechRecognitionService(
        channel: channel,
        audioEvents: native.audio.stream,
        clockMs: () => native.nowMs,
      );
      quiet = [];
      results = [];
      errors = [];
      service.feedbackQuietStream.listen(quiet.add);
      service.resultsStream.listen(results.add);
      service.errorStream.listen(errors.add);
      expect(await service.startListening(), isTrue);
    });

    tearDown(() async {
      if (native.stopBarrier case final barrier? when !barrier.isCompleted) {
        barrier.complete();
      }
      await service.dispose();
      await native.audio.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'quiet waits for the full 420ms boundary and stops with capture',
      () async {
        expect(service.isQuietForFeedback, isFalse);
        native.feed(_silence(90));
        expect(service.isQuietForFeedback, isTrue);
        native.feed(_voice(600));
        expect(service.isQuietForFeedback, isFalse);
        native.feed(_silence(180));
        expect(service.isQuietForFeedback, isFalse);
        native.feed(_silence(30));
        expect(service.isQuietForFeedback, isFalse);
        expect(quiet, [true, false]);
        native.feed(_silence(180));
        expect(service.isQuietForFeedback, isFalse);
        expect(quiet, [true, false]);
        native.feed(_silence(30));
        expect(service.isQuietForFeedback, isTrue);
        native.feed(_voice(30));
        expect(service.isQuietForFeedback, isFalse);
        native.feed(_silence(420));
        expect(service.isQuietForFeedback, isTrue);
        await service.stopListening();
        expect(service.isQuietForFeedback, isFalse);
        expect(quiet, [true, false, true, false, true, false]);
        expect(errors, isEmpty);
      },
    );

    test('an empty forced-cut tail still requires 420ms of actual quiet', () async {
      await service.dispose();
      quiet.clear();
      final segmenter = SpeechSegmenter(
        maxSegmentMs: 600,
        forcedCutWindowMs: 30,
      );
      service = OfflineSpeechRecognitionService(
        channel: channel,
        audioEvents: native.audio.stream,
        segmenter: segmenter,
        clockMs: () => native.nowMs,
      );
      service.feedbackQuietStream.listen(quiet.add);
      service.resultsStream.listen(results.add);
      service.errorStream.listen(errors.add);
      expect(await service.startListening(), isTrue);
      native.feed(_voice(600));
      expect(segmenter.bufferedDurationMs, 0);
      expect(service.isQuietForFeedback, isFalse);
      expect(quiet, isEmpty);
      native.feed(_silence(390));
      expect(service.isQuietForFeedback, isFalse);
      expect(quiet, isEmpty);
      native.feed(_silence(30));
      expect(service.isQuietForFeedback, isTrue);
      expect(quiet, [true]);
      await service.stopListening();
      expect(service.isQuietForFeedback, isFalse);
      expect(quiet, [true, false]);
      expect(errors, isEmpty);
    });

    test(
      'late stop-tail audio never reopens the quiet feedback window',
      () async {
        native.feed(_silence(90));
        expect(service.isQuietForFeedback, isTrue);
        native.stopBarrier = Completer<void>();
        final stopping = service.stopListening();
        expect(service.isQuietForFeedback, isFalse);
        native.feed(_silence(90));
        expect(service.isQuietForFeedback, isFalse);
        expect(quiet, [true, false]);
        native.stopBarrier!.complete();
        await stopping;
        expect(quiet, [true, false]);
        expect(errors, isEmpty);
      },
    );

    test('isolated doubled cues never invoke the native recognizer', () async {
      for (final cue in _cues) {
        native.feed(_silence(600));
        native.feed(await _cuePcm(cue, gain: 2));
        native.feed(_silence(600));
        await _settle();
      }
      await service.stopListening();
      expect(native.decodedPcm, isEmpty);
      expect(results, isEmpty);
      expect(errors, isEmpty);
    });

    for (final cue in _cues) {
      test(
        'quiet observation preserves every VAD sample around $cue and resumed speech',
        () async {
          final reference = SpeechSegmenter();
          final expected = <SpeechSegment>[];
          final input = [
            _silence(300),
            _voice(600),
            _silence(210),
            await _cuePcm(cue, gain: 2),
            _silence(90),
            _voice(570, seed: 7),
            _silence(600),
          ];
          for (final section in input) {
            for (final packet in _packets(section)) {
              expected.addAll(reference.push(packet));
              native.packet(packet);
            }
          }
          final remaining = reference.flush();
          if (remaining != null) expected.add(remaining);
          expect(service.isListening, isTrue);
          await service.stopListening();
          final finals = results.where((result) => result.isFinal).toList();
          expect(expected, isNotEmpty);
          expect(finals, hasLength(expected.length));
          for (var i = 0; i < finals.length; i++) {
            final id = int.parse(
              finals[i].recognizedWords.substring('decoded-'.length),
            );
            expect(native.decodedPcm[id], orderedEquals(expected[i].samples));
          }
          expect(
            native.methods.where((method) => method == 'start'),
            hasLength(1),
          );
          expect(
            native.methods.where((method) => method == 'stop'),
            hasLength(1),
          );
          expect(quiet, containsAll([true, false]));
          expect(service.isQuietForFeedback, isFalse);
          expect(errors, isEmpty);
        },
      );
    }
  });
}
