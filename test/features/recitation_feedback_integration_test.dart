import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/recitation_feedback_event.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/recitation_feedback_controller.dart';
import 'package:mishkat_app/features/quran/presentation/services/recitation_pause_diagnostics.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class _OfflineSpeech extends MockSpeechRecognitionService
    implements OfflineSpeechDiagnostics, RecitationPauseDiagnostics {
  @override
  bool get isOffline => true;
  @override
  Stream<double> get soundLevelStream => const Stream.empty();
  @override
  Stream<bool> get processingStream => const Stream.empty();
  @override
  Stream<bool> get feedbackQuietStream => const Stream.empty();
  @override
  bool get isQuietForFeedback => isListening;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/recitation_feedback_integration');
  const throughMistake = 'عم يتساءلون عن النبأ العظيم الذي هم فيه مختلفين';
  const wholeWithMistake = '$throughMistake كلا سيعلمون ثم كلا سيعلمون';
  late _OfflineSpeech speech;
  late QuranMemorizationCubit memory;
  late QuranOralRecitationCubit cubit;
  late RecitationFeedbackController feedback;
  late StreamSubscription<RecitationFeedbackEvent> eventSubscription;
  late List<RecitationCue> events;
  late List<String> sounds;
  late List<bool> captureAtPlayback;
  late int nowMs;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    speech = _OfflineSpeech();
    memory = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: LocalStorageService()),
    );
    cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: QuranRepository(),
      memorizationCubit: memory,
    );
    await cubit.prepareSession(
      surahNumber: 78,
      startGlobalAyah: 5673,
      endGlobalAyah: 5677,
    );
    events = [];
    sounds = [];
    captureAtPlayback = [];
    nowMs = 0;
    var armed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
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
              captureAtPlayback.add(speech.isListening);
              return true;
            default:
              throw StateError(call.method);
          }
        });
    // Use real Cubit emissions, which are asynchronous unlike hand-authored
    // state streams. This exposes stale draining snapshots arriving after a
    // terminal feedback event has already begun native preparation.
    feedback = RecitationFeedbackController.bind(
      events: cubit.feedbackStream,
      states: cubit.stream,
      currentState: () => cubit.state,
      speechService: speech,
      output: NativeRecitationFeedbackOutput(channel: channel),
      nowMs: () => nowMs,
    );
    eventSubscription = cubit.feedbackStream.listen(
      (event) => events.add(event.cue),
    );
  });

  tearDown(() async {
    await feedback.dispose();
    await eventSubscription.cancel();
    await cubit.close();
    await speech.dispose();
    await memory.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> start() async {
    await cubit.startRecitation();
    await pumpEventQueue();
    expect(sounds, ['ready']);
    nowMs = 1000;
  }

  Future<void> hear(String text) async {
    speech.emitTranscript(text, isFinal: true);
    await pumpEventQueue();
  }

  test(
    'ready, mid-range mistake and correction reach native playback',
    () async {
      await start();
      await hear(throughMistake);
      nowMs = 3000;
      await hear('مختلفون');
      expect(sounds, ['ready', 'mistake', 'corrected']);
      expect(captureAtPlayback, [true, true, true]);
      expect(cubit.state.isListening, isTrue);
    },
  );

  test(
    'automatic completion survives queued draining state notifications',
    () async {
      await start();
      final text = cubit.state.targetWords
          .map((word) => word.uthmaniText)
          .join(' ');
      await hear(text);
      expect(cubit.state.isCompleted, isTrue);
      expect(events.last, RecitationCue.complete);
      expect(sounds, ['ready', 'complete']);
      expect(captureAtPlayback.last, isFalse);
    },
  );

  test(
    'a terminal mistake remains audible as the automatic report opens',
    () async {
      await start();
      await hear(wholeWithMistake);
      expect(cubit.state.isCompleted, isTrue);
      expect(cubit.state.summary!.substitutionsCount, 1);
      expect(sounds, ['ready', 'mistake']);
      expect(captureAtPlayback.last, isFalse);
      expect(sounds, isNot(contains('complete')));
    },
  );

  test('manual early finish sounds paused after capture teardown', () async {
    await start();
    await cubit.finishSession();
    await pumpEventQueue();
    expect(cubit.state.isCompleted, isTrue);
    expect(sounds, ['ready', 'paused']);
    expect(captureAtPlayback.last, isFalse);
  });
}
