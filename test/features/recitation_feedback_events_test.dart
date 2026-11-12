import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/models/recitation_feedback_event.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_state.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class _Quran extends QuranRepository {
  @override
  Future<QuranData> load() async => QuranData(
    chapters: [
      QuranChapter(
        number: 78,
        name: 'النبأ',
        englishName: 'An-Naba',
        revelationType: 'Meccan',
        page: 582,
        globalStart: 5673,
        ayahs: const [
          'عَمَّ يَتَسَآءَلُونَ',
          'عَنِ ٱلنَّبَإِ ٱلْعَظِيمِ',
          'ٱلَّذِى هُمْ فِيهِ مُخْتَلِفُونَ',
          'كَلَّا سَيَعْلَمُونَ',
          'ثُمَّ كَلَّا سَيَعْلَمُونَ',
        ],
      ),
    ],
    juz: const [],
    pages: const [],
  );
}

class _Speech extends MockSpeechRecognitionService {
  Completer<bool>? opening;
  Completer<void>? stopping;
  bool allowStart = true;

  @override
  Future<bool> startListening({
    String localeId = 'ar_SA',
    List<String> contextualPhrases = const [],
  }) async {
    if (!allowStart || (opening != null && !await opening!.future)) {
      return false;
    }
    return super.startListening(
      localeId: localeId,
      contextualPhrases: contextualPhrases,
    );
  }

  @override
  Future<void> stopListening() async {
    await stopping?.future;
    await super.stopListening();
  }
}

class _OfflineSpeech extends _Speech implements OfflineSpeechDiagnostics {
  @override
  bool get isOffline => true;
  @override
  Stream<double> get soundLevelStream => const Stream.empty();
  @override
  Stream<bool> get processingStream => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const throughMistake = 'عم يتساءلون عن النبأ العظيم الذي هم فيه مختلفين';
  const wholeRange =
      'عم يتساءلون عن النبأ العظيم الذي هم فيه مختلفون كلا سيعلمون ثم كلا سيعلمون';
  const wholeRangeWithMistake = '$throughMistake كلا سيعلمون ثم كلا سيعلمون';
  late Directory temp;
  late _Speech speech;
  late QuranMemorizationCubit memorization;
  late QuranOralRecitationCubit cubit;
  late List<RecitationFeedbackEvent> events;
  late List<QuranOralRecitationState> eventStates;
  late List<bool> captureAtEvent;

  Future<void> prepare() => cubit.prepareSession(
    surahNumber: 78,
    startGlobalAyah: 5673,
    endGlobalAyah: 5677,
  );

  Future<void> say(String text, {bool isFinal = true}) async {
    speech.emitTranscript(text, isFinal: isFinal);
    await pumpEventQueue();
  }

  Future<void> startAndClear() async {
    await cubit.startRecitation();
    expect(events.map((event) => event.cue), [RecitationCue.ready]);
    events.clear();
    eventStates.clear();
    captureAtEvent.clear();
  }

  void attach() {
    cubit.feedbackStream.listen((event) {
      events.add(event);
      eventStates.add(cubit.state);
      captureAtEvent.add(speech.isListening);
    });
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mishkat-feedback-events-');
    final storage = LocalStorageService(directory: temp);
    await storage.init();
    memorization = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: storage),
    );
    await memorization.load();
    speech = _OfflineSpeech();
    cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: _Quran(),
      memorizationCubit: memorization,
    );
    events = [];
    eventStates = [];
    captureAtEvent = [];
    attach();
    await prepare();
  });

  tearDown(() async {
    if (speech.opening case final opening? when !opening.isCompleted) {
      opening.complete(false);
    }
    if (speech.stopping case final stopping? when !stopping.isCompleted) {
      stopping.complete();
    }
    if (!cubit.isClosed) await cubit.close();
    await speech.dispose();
    await memorization.close();
    await temp.delete(recursive: true);
  });

  test(
    'ready waits for successful native startup instead of optimistic state',
    () async {
      speech.opening = Completer<bool>();
      final starting = cubit.startRecitation();
      await pumpEventQueue();
      expect(cubit.state.isListening, isTrue);
      expect(events, isEmpty);
      speech.opening!.complete(true);
      await starting;
      expect(events.single.cue, RecitationCue.ready);
      expect(events.single.sessionId, cubit.state.sessionId);
      expect(eventStates.single.isListening, isTrue);
      expect(captureAtEvent.single, isTrue);
    },
  );

  test('failed microphone startup never emits ready', () async {
    speech.allowStart = false;
    await cubit.startRecitation();
    expect(events, isEmpty);
    expect(cubit.state.isListening, isFalse);
  });

  test('a late startup after closing cannot emit ready', () async {
    speech.opening = Completer<bool>();
    final starting = cubit.startRecitation();
    await pumpEventQueue();
    await cubit.close();
    speech.opening!.complete(true);
    await starting;
    expect(events, isEmpty);
    expect(speech.isListening, isFalse);
  });

  test(
    'only a new confirmed error emits once and state is already updated',
    () async {
      await startAndClear();
      await say(throughMistake, isFinal: false);
      await say(throughMistake, isFinal: false);
      expect(events, isEmpty);
      await say(throughMistake);
      expect(events.single.cue, RecitationCue.mistake);
      expect(events.single.wordIndices, {8});
      expect(eventStates.single.unresolvedMistakeWordIndices, {8});
      expect(eventStates.single.mistakeWordIndices, {8});
      await say(throughMistake);
      await say('كلا سيعلمون');
      expect(events, hasLength(1));
      expect(cubit.state.isListening, isTrue);
    },
  );

  test('multiple mistakes in one final produce one grouped event', () async {
    await startAndClear();
    await say('عم يتساءلون عن النبأ الكبير الذي هم فيه مختلفين كلا سيعلمون');
    expect(events.single.cue, RecitationCue.mistake);
    expect(events.single.wordIndices, {4, 8});
    expect(cubit.state.isListening, isTrue);
  });

  test(
    'a new mistake takes priority over a correction in the same final',
    () async {
      await startAndClear();
      await say('عم يتساءلون عن النبأ الكبير');
      expect(cubit.state.unresolvedMistakeWordIndices, {4});
      events.clear();
      await say('عن النبأ العظيم الذي هم فيه مختلفين');
      expect(cubit.state.alignedWords[4].status, WordAlignmentStatus.matched);
      expect(cubit.state.unresolvedMistakeWordIndices, {8});
      expect(events.single.cue, RecitationCue.mistake);
      expect(events.single.wordIndices, {8});
    },
  );

  test('only confirmed matching correction emits and retained red history is silent', () async {
    await startAndClear();
    await say(throughMistake);
    events.clear();
    await say('مختلفون', isFinal: false);
    expect(events, isEmpty);
    await say('مختلفون');
    expect(events.single.cue, RecitationCue.corrected);
    expect(events.single.wordIndices, {8});
    expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
    expect(cubit.state.mistakeWordIndices, {8});
    await say('مختلفون');
    await say('');
    expect(events, hasLength(1));
  });

  test(
    'hints and bypassing a mistake do not emit correction or capture cues',
    () async {
      await startAndClear();
      cubit.hintCurrentWord();
      cubit.revealAyah(5673);
      cubit.hideAyah(5673);
      expect(events, isEmpty);
      await say(throughMistake);
      await say('كلا سيعلمون');
      events.clear();
      await cubit.skipCurrentWord();
      expect(events, isEmpty);
      expect(cubit.state.alignedWords[8].status, WordAlignmentStatus.uncertain);
      expect(cubit.state.isListening, isTrue);
    },
  );

  test('pause is emitted after capture has stopped and only once', () async {
    await startAndClear();
    speech.stopping = Completer<void>();
    final pausing = cubit.pauseRecitation();
    await pumpEventQueue();
    expect(cubit.state.isDraining, isTrue);
    expect(events, isEmpty);
    speech.stopping!.complete();
    await pausing;
    expect(events.single.cue, RecitationCue.paused);
    expect(eventStates.single.isPaused, isTrue);
    expect(eventStates.single.isDraining, isFalse);
    expect(captureAtEvent.single, isFalse);
    await cubit.pauseRecitation();
    expect(events, hasLength(1));
    await cubit.resumeRecitation();
    expect(events.map((event) => event.cue), [
      RecitationCue.paused,
      RecitationCue.ready,
    ]);
  });

  test(
    'a correct whole range finishes with complete and no separate pause',
    () async {
      await startAndClear();
      await say(wholeRange);
      expect(events.single.cue, RecitationCue.complete);
      expect(eventStates.single.isCompleted, isTrue);
      expect(captureAtEvent.single, isFalse);
      await cubit.finishSession();
      expect(events, hasLength(1));
    },
  );

  test(
    'manual finish without completed speech is a pause cue, not success',
    () async {
      await startAndClear();
      await cubit.finishSession();
      expect(events.single.cue, RecitationCue.paused);
      expect(eventStates.single.isCompleted, isTrue);
      expect(captureAtEvent.single, isFalse);
      expect(cubit.state.summary!.matchedWords, 0);
    },
  );

  test('manual finish with remaining mistakes never emits complete', () async {
    await startAndClear();
    await say(throughMistake);
    events.clear();
    await cubit.finishSession();
    expect(events.single.cue, RecitationCue.mistake);
    expect(events.single.wordIndices, {8});
    expect(cubit.state.unresolvedMistakeWordIndices, {8});
  });

  test(
    'automatic report with mistakes ends capture without a success cue',
    () async {
      await startAndClear();
      await say(wholeRangeWithMistake);
      expect(events.map((event) => event.cue), [
        RecitationCue.mistake,
        RecitationCue.mistake,
      ]);
      expect(eventStates.last.isCompleted, isTrue);
      expect(captureAtEvent.last, isFalse);
      expect(cubit.state.summary!.substitutionsCount, 1);
      await cubit.finishSession();
      expect(events, hasLength(2));
    },
  );

  test(
    'finish during pause shares drain and emits only its final cue',
    () async {
      await startAndClear();
      speech.stopping = Completer<void>();
      final pausing = cubit.pauseRecitation();
      await pumpEventQueue();
      final finishing = cubit.finishSession();
      speech.stopping!.complete();
      await Future.wait([pausing, finishing]);
      expect(events.single.cue, RecitationCue.paused);
      expect(eventStates.single.isCompleted, isTrue);
    },
  );

  test(
    'system errors are not recitation mistakes or successful pauses',
    () async {
      await startAndClear();
      speech.emitError(
        'الميكروفون غير متاح',
        type: SpeechRecognitionFailureType.audio,
      );
      await pumpEventQueue();
      expect(events, isEmpty);
      expect(cubit.state.isListening, isFalse);
    },
  );

  test('automatic native recovery does not replay the ready cue', () async {
    await cubit.close();
    await speech.dispose();
    speech = _Speech();
    cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: _Quran(),
      memorizationCubit: memorization,
    );
    attach();
    await prepare();
    await startAndClear();
    speech.emitStatus('done');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await pumpEventQueue();
    expect(speech.startListeningCount, 2);
    expect(cubit.state.isListening, isTrue);
    expect(events, isEmpty);
  });

  test(
    'a new attempt owns a new feedback session and may flag the same word',
    () async {
      await startAndClear();
      await say(throughMistake);
      final previousSession = events.single.sessionId;
      await cubit.retrySession();
      events.clear();
      await startAndClear();
      await say(throughMistake);
      expect(events.single.cue, RecitationCue.mistake);
      expect(events.single.sessionId, isNot(previousSession));
      expect(events.single.sessionId, cubit.state.sessionId);
    },
  );

  test('closing ends the feedback stream and discards late speech', () async {
    await startAndClear();
    var done = false;
    cubit.feedbackStream.listen((_) {}, onDone: () => done = true);
    await cubit.close();
    await say(throughMistake);
    expect(done, isTrue);
    expect(events, isEmpty);
  });
}
