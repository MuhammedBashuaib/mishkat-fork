import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class _Quran extends QuranRepository {
  @override
  Future<QuranData> load() async => QuranData(
    chapters: [
      QuranChapter(
        number: 1,
        name: 'الفاتحة',
        englishName: 'Al-Fatiha',
        revelationType: 'Meccan',
        page: 1,
        globalStart: 1,
        ayahs: const [
          'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
          'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
          'ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
        ],
      ),
    ],
    juz: const [],
    pages: const [],
  );
}

class _OfflineSpeech extends MockSpeechRecognitionService
    implements OfflineSpeechDiagnostics {
  @override
  bool get isOffline => true;
  @override
  Stream<double> get soundLevelStream => const Stream.empty();
  @override
  Stream<bool> get processingStream => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const basmala = 'بسم الله الرحمن الرحيم';
  late Directory temp;
  late _OfflineSpeech speech;
  late QuranMemorizationCubit memory;
  late QuranOralRecitationCubit cubit;

  Future<void> say(String text, {bool isFinal = false}) async {
    speech.emitTranscript(text, isFinal: isFinal);
    await pumpEventQueue();
  }

  Future<void> prepare({int first = 1}) async {
    await cubit.prepareSession(
      surahNumber: 1,
      startGlobalAyah: first,
      endGlobalAyah: 3,
    );
    await cubit.startRecitation();
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mishkat-fast-reveal-');
    final storage = LocalStorageService(directory: temp);
    await storage.init();
    memory = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: storage),
    );
    await memory.load();
    speech = _OfflineSpeech();
    cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: _Quran(),
      memorizationCubit: memory,
    );
    await prepare();
  });

  tearDown(() async {
    await cubit.close();
    await speech.dispose();
    await memory.close();
    await temp.delete(recursive: true);
  });

  test(
    'first exact prefix appears with a held trailing word and no credit',
    () async {
      await say(basmala);
      expect(cubit.state.visibleWordIndices, {0, 1, 2});
      expect(cubit.state.visibleWordIndices, isNot(contains(3)));
      expect(cubit.state.committedTargetIndex, 0);
      expect(cubit.state.completedGlobalAyahs, isEmpty);
      expect(cubit.state.mistakeWordIndices, isEmpty);
      expect(cubit.state.isListening, isTrue);
      await say(basmala);
      expect(cubit.state.visibleWordIndices, {0, 1, 2, 3});
      expect(cubit.state.visibleWordIndices, isNot(contains(4)));
      expect(cubit.state.committedTargetIndex, 0);
    },
  );

  test(
    'الحمدلله plus رب reveals the joined words on the first hypothesis',
    () async {
      await prepare(first: 2);
      await say('الحمدلله رب');
      expect(cubit.state.visibleWordIndices, {0, 1});
      expect(cubit.state.visibleWordIndices, isNot(contains(2)));
      expect(cubit.state.visibleWordIndices, isNot(contains(3)));
      expect(cubit.state.committedTargetIndex, 0);
    },
  );

  test('an entire trailing joined recognition group stays hidden', () async {
    await prepare(first: 2);
    await say('الحمدلله');
    expect(cubit.state.matchedWordsCount, 2);
    expect(cubit.state.visibleWordIndices, isEmpty);
    await say('الحمدلله');
    expect(cubit.state.visibleWordIndices, {0, 1});
    expect(cubit.state.committedTargetIndex, 0);
  });

  test('a new fast prefix starts at the committed frontier', () async {
    await say(basmala, isFinal: true);
    expect(cubit.state.committedTargetIndex, 4);
    await say('الحمدلله رب');
    expect(cubit.state.visibleWordIndices, {0, 1, 2, 3, 4, 5});
    expect(cubit.state.visibleWordIndices, isNot(contains(6)));
    expect(cubit.state.committedTargetIndex, 4);
    expect(cubit.state.completedGlobalAyahs, {1});
  });

  test(
    'a changing last group does not expose the uncertain tail or next ayah',
    () async {
      await say('بسم الله الرحمن');
      expect(cubit.state.visibleWordIndices, {0, 1});
      await say('بسم الله الرحيم');
      expect(cubit.state.visibleWordIndices, {0, 1});
      expect(cubit.state.assistedWordIndices, isEmpty);
      expect(cubit.state.mistakeWordIndices, isEmpty);
      expect(cubit.state.completedGlobalAyahs, isEmpty);
    },
  );

  test(
    'a wrong opening cannot fast-reveal correct words after the gap',
    () async {
      await say('رب الله الرحمن الرحيم');
      expect(cubit.state.visibleWordIndices, isEmpty);
      expect(cubit.state.mistakeWordIndices, isEmpty);
      expect(cubit.state.committedTargetIndex, 0);
    },
  );

  test(
    'a middle mistake ends the first-preview prefix before later matches',
    () async {
      await say('بسم الله العظيم الرحيم');
      expect(cubit.state.visibleWordIndices, {0});
      expect(cubit.state.visibleWordIndices, isNot(contains(3)));
      expect(cubit.state.mistakeWordIndices, isEmpty);
      expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
    },
  );

  test('documented Uthmani spellings supply exact trailing context', () async {
    await prepare(first: 2);
    // The alif expansion in العالمين is an explicit spelling of العٰلمين.
    await say('الحمد لله رب العالمين');
    expect(cubit.state.matchedWordsCount, 4);
    expect(cubit.state.visibleWordIndices, {0, 1, 2});
    expect(cubit.state.visibleWordIndices, isNot(contains(3)));
    await say('الحمد لله رب العالمين');
    expect(cubit.state.visibleWordIndices, {0, 1, 2, 3});
  });

  test('a similar word cannot supply exact trailing context', () async {
    await prepare(first: 2);
    await say('الحمد لله رب العالمون');
    expect(cubit.state.matchedWordsCount, 3);
    expect(cubit.state.visibleWordIndices, {0, 1});
    expect(cubit.state.mistakeWordIndices, isEmpty);
    expect(cubit.state.committedTargetIndex, 0);
  });

  test(
    'empty partial keeps a fast prefix but pause settles it without saving it',
    () async {
      await say(basmala);
      await say('');
      expect(cubit.state.visibleWordIndices, {0, 1, 2});
      expect(cubit.state.assistedWordIndices, isEmpty);
      expect(cubit.state.committedTargetIndex, 0);
      await cubit.pauseRecitation();
      expect(cubit.state.visibleWordIndices, isEmpty);
      expect(cubit.state.assistedWordIndices, {0, 1, 2});
      await cubit.finishSession();
      expect(cubit.state.summary!.matchedWords, 0);
      expect(cubit.state.summary!.matchedAyahs, 0);
      expect(cubit.state.summary!.assistedWords, 3);
    },
  );

  test(
    'confirmed earlier ayahs survive empty and incomplete next-ayah results',
    () async {
      await say(basmala, isFinal: true);
      await say('');
      expect(cubit.state.visibleWordIndices, {0, 1, 2, 3});
      expect(cubit.state.completedGlobalAyahs, {1});
      await say('الحمد لله رب');
      expect(cubit.state.visibleWordIndices, {0, 1, 2, 3, 4, 5});
      await say('الحمد لله رب العالمين', isFinal: true);
      await say('');
      expect(
        cubit.state.visibleWordIndices,
        Set.of(List.generate(8, (i) => i)),
      );
      expect(cubit.state.completedGlobalAyahs, {1, 2});
      await say('الرحمن');
      expect(
        cubit.state.visibleWordIndices,
        Set.of(List.generate(8, (i) => i)),
      );
      expect(cubit.state.visibleWordIndices, isNot(contains(9)));
      expect(cubit.state.committedTargetIndex, 8);
      expect(cubit.state.hintCount, 0);
    },
  );

  test(
    'a final confirming the fast prefix preserves unassisted credit',
    () async {
      await say(basmala);
      await say('$basmala الحمد لله رب العالمين الرحمن الرحيم', isFinal: true);
      expect(cubit.state.summary!.suggestedOutcome, ReviewOutcome.easy);
      expect(cubit.state.summary!.assistedWords, 0);
      expect(cubit.state.summary!.hintCount, 0);
      expect(cubit.state.completedGlobalAyahs, {1, 2, 3});
    },
  );
}
