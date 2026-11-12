import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/recitation_feedback_controller.dart';

/// Only the microphone packets and acoustic decoder are simulated. VAD,
/// service result delivery, alignment, Cubit and the feedback controller/output
/// all execute production code. No fake quiet getter bypasses the real gate.
class _MicrophoneAndDecoder {
  final audio = StreamController<Object?>.broadcast(sync: true);
  final calls = <String>[];
  String? session;
  String transcript = '';
  int nowMs = 0;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
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
        expect((call.arguments as Map)['pcm'], isA<Uint8List>());
        return transcript;
      default:
        throw StateError(call.method);
    }
  }

  void feed({required int milliseconds, bool voiced = false}) {
    assert(milliseconds % 30 == 0);
    for (var elapsed = 0; elapsed < milliseconds; elapsed += 30) {
      final bytes = ByteData(480 * 2);
      if (voiced) {
        for (var sample = 0; sample < 480; sample++) {
          bytes.setInt16(
            sample * 2,
            sample.isEven ? 1000 : -1000,
            Endian.little,
          );
        }
      }
      nowMs += 30;
      audio.add({
        'type': 'audio',
        'sessionId': session,
        'pcm': bytes.buffer.asUint8List(),
      });
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real 420ms VAD boundaries deliver mid-recitation error and correction sounds', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const speechChannel = MethodChannel('test/feedback_pcm_speech');
    const soundChannel = MethodChannel('test/feedback_pcm_sound');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final native = _MicrophoneAndDecoder();
    messenger.setMockMethodCallHandler(speechChannel, native.handle);
    final speech = OfflineSpeechRecognitionService(
      channel: speechChannel,
      audioEvents: native.audio.stream,
      clockMs: () => native.nowMs,
    );
    final sounds = <String>[];
    final quietAtPlayback = <bool>[];
    var armed = false;
    messenger.setMockMethodCallHandler(soundChannel, (call) async {
      switch (call.method) {
        case 'prepare':
          armed = true;
          return null;
        case 'stop':
        case 'dispose':
          armed = false;
          return null;
        case 'play':
          if (!armed) return false;
          sounds.add((call.arguments as Map)['cue'] as String);
          quietAtPlayback.add(speech.isQuietForFeedback);
          return true;
        default:
          throw StateError(call.method);
      }
    });
    final memory = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: LocalStorageService()),
    );
    final cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: QuranRepository(),
      memorizationCubit: memory,
    );
    RecitationFeedbackController? feedback;
    addTearDown(() async {
      await feedback?.dispose();
      await cubit.close();
      await speech.dispose();
      await native.audio.close();
      await memory.close();
      messenger.setMockMethodCallHandler(speechChannel, null);
      messenger.setMockMethodCallHandler(soundChannel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    await cubit.prepareSession(
      surahNumber: 78,
      startGlobalAyah: 5673,
      endGlobalAyah: 5677,
    );
    feedback = RecitationFeedbackController.bind(
      events: cubit.feedbackStream,
      states: cubit.stream,
      currentState: () => cubit.state,
      speechService: speech,
      output: NativeRecitationFeedbackOutput(channel: soundChannel),
      nowMs: () => native.nowMs,
    );
    await cubit.startRecitation();
    native.feed(milliseconds: 90);
    await pumpEventQueue();
    expect(sounds, ['ready']);

    native.transcript = 'عم يتساءلون عن النبأ العظيم الذي هم فيه مختلفين';
    native.feed(milliseconds: 600, voiced: true);
    native.feed(milliseconds: 210);
    await pumpEventQueue();
    expect(speech.isQuietForFeedback, isFalse);
    expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
    expect(sounds, ['ready']);
    native.feed(milliseconds: 180);
    await pumpEventQueue();
    expect(speech.isQuietForFeedback, isFalse);
    expect(sounds, ['ready']);
    native.feed(milliseconds: 30);
    await pumpEventQueue();
    expect(speech.isQuietForFeedback, isTrue);
    expect(cubit.state.unresolvedMistakeWordIndices, {8});
    expect(sounds, ['ready', 'mistake']);

    native.transcript = 'مختلفون';
    native.feed(milliseconds: 300, voiced: true);
    native.feed(milliseconds: 390);
    await pumpEventQueue();
    expect(speech.isQuietForFeedback, isFalse);
    expect(cubit.state.unresolvedMistakeWordIndices, {8});
    expect(sounds, ['ready', 'mistake']);
    native.feed(milliseconds: 30);
    await pumpEventQueue();
    expect(speech.isQuietForFeedback, isTrue);
    expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
    expect(sounds, ['ready', 'mistake', 'corrected']);
    expect(quietAtPlayback, [true, true, true]);
    expect(cubit.state.isListening, isTrue);
    expect(speech.isListening, isTrue);
    expect(native.calls.where((call) => call == 'start'), hasLength(1));
    expect(
      native.calls.where((call) => call == 'stop'),
      hasLength(1),
      reason:
          'Preparation cancels pre-existing capture once; cues never stop it.',
    );
  });
}
