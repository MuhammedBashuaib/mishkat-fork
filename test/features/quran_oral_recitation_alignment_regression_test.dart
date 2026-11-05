import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_alignment_engine.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class InMemoryLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> _data = {};
  @override
  Future<void> init() async {}
  @override
  Map<String, dynamic> readMap(String key) => _data[key] is Map
      ? Map<String, dynamic>.from(_data[key])
      : <String, dynamic>{};
  @override
  List<dynamic> readList(String key) =>
      _data[key] is List ? List<dynamic>.from(_data[key]) : <dynamic>[];
  @override
  int readInt(String key, [int fallback = 0]) =>
      _data[key] is num ? (_data[key] as num).toInt() : fallback;
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async =>
      _data[key] = value;
  @override
  Future<void> writeList(String key, List<dynamic> value) async =>
      _data[key] = value;
  @override
  Future<void> writeInt(String key, int value) async => _data[key] = value;
  @override
  Future<void> remove(String key) async => _data.remove(key);
  @override
  Future<void> clear() async => _data.clear();
}

class FakeQuranRepository extends QuranRepository {
  FakeQuranRepository({required this.data});
  final QuranData data;
  @override
  Future<QuranData> load() async => data;
}

class FakeAudioService extends QuranAudioService {
  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Surah Al-Fatiha (Ayahs 1-4)
  final fatihaChapter = QuranChapter(
    number: 1,
    name: 'الفاتحة',
    englishName: 'Al-Faatiha',
    revelationType: 'Meccan',
    page: 1,
    globalStart: 1,
    ayahs: const [
      'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ', // Ayah 1: words 0..3 (ends with الرحمن الرحيم)
      'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ', // Ayah 2: words 4..7
      'ٱلرَّحْمَٰنِ ٱلرَّحِيمِ', // Ayah 3: words 8..9 (REPEATED الرحمن الرحيم!)
      'مَٰلِكِ يَوْمِ ٱلدِّينِ', // Ayah 4: words 10..12
    ],
  );

  final testQuranData = QuranData(
    chapters: [fatihaChapter],
    juz: const [],
    pages: const [],
  );

  group(
    'Q14 Al-Fatiha Repeated Phrases & Monotonic Progress Reproduction Tests',
    () {
      late MockSpeechRecognitionService mockSpeech;
      late FakeQuranRepository fakeQuranRepo;
      late InMemoryLocalStorageService storage;
      late QuranMemorizationRepository memRepo;
      late QuranMemorizationCubit memCubit;
      late FakeAudioService fakeAudioService;
      late QuranOralRecitationCubit cubit;

      setUp(() async {
        mockSpeech = MockSpeechRecognitionService(
          initialPermission: true,
          initialAvailable: true,
        );
        fakeQuranRepo = FakeQuranRepository(data: testQuranData);
        storage = InMemoryLocalStorageService();
        memRepo = QuranMemorizationRepository(storage: storage);
        memCubit = QuranMemorizationCubit(repository: memRepo);
        await memCubit.load();
        fakeAudioService = FakeAudioService();

        cubit = QuranOralRecitationCubit(
          speechService: mockSpeech,
          quranRepository: fakeQuranRepo,
          memorizationCubit: memCubit,
          audioService: fakeAudioService,
        );
        await cubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 4,
        );
        await cubit.startRecitation();
      });

      tearDown(() async {
        await cubit.close();
        await memCubit.close();
      });

      test('Test A: Exact user-reported sequence: Ayah 1 -> Ayah 2 -> Ayah 3 (الرحمن الرحيم) must maintain monotonic progress', () async {
        // 1. User recites Ayah 1: بسم الله الرحمن الرحيم
        mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
        await pumpEventQueue();

        // 2. User recites Ayah 2: الحمد لله رب العالمين
        mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
        await pumpEventQueue();

        // 3. User recites Ayah 3: الرحمن الرحيم (Exact repeated phrase from Ayah 1!)
        mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: true);
        await pumpEventQueue();

        // CRITICAL ASSERTIONS:
        // - Must advance reading frontier to Ayah 4 (word 10: مالك), not jump back to Ayah 1!
        // - Must have 10 matched words total (4 in Ayah 1 + 4 in Ayah 2 + 2 in Ayah 3)
        // - Must NOT report words in Basmalah as omitted
        // - Must have completed Ayahs 1, 2, and 3
        expect(
          cubit.state.currentGlobalAyah,
          4,
          reason: 'Cursor frontier must advance to Ayah 4, not jump back to Ayah 1 or 2',
        );
        expect(
          cubit.state.matchedWordsCount,
          10,
          reason: 'Must have matched 10 words through Ayah 3',
        );
        expect(
          cubit.state.omissionsCount,
          0,
          reason: 'Basmalah must NOT be falsely reported as omitted',
        );
        expect(
          cubit.state.discrepancies,
          isEmpty,
          reason: 'No false discrepancies',
        );
        expect(cubit.state.completedGlobalAyahs, containsAll(<int>{1, 2, 3}));

        // 4. User recites Ayah 4: مالك يوم الدين
        mockSpeech.emitTranscript('مالك يوم الدين', isFinal: true);
        await pumpEventQueue();

        expect(cubit.state.matchedWordsCount, 13);
        expect(cubit.state.omissionsCount, 0);
        expect(
          cubit.state.completedGlobalAyahs,
          containsAll(<int>{1, 2, 3, 4}),
        );
        expect(cubit.state.lifecycle.isCompleted, isTrue);
      });
      test('Test B: Repeated phrases at separate positions do not cause backward jump', () async {
        final engine = const QuranAlignmentEngine();
        final targetWords = engine.prepareTargetTokens(
          chapters: [fatihaChapter],
          startGlobalAyah: 1,
          endGlobalAyah: 4,
        );

        // Ayah 1 (words 0..3) committed
        final step1 = engine.align(
          targetWords: targetWords,
          transcript: 'بسم الله الرحمن الرحيم',
          isFinal: true,
        );
        expect(step1.committedTargetIndex, 4);

        // Ayah 2 (words 4..7) committed
        final step2 = engine.align(
          targetWords: targetWords,
          transcript: 'الحمد لله رب العالمين',
          committedTargetIndex: step1.committedTargetIndex,
          isFinal: true,
        );
        expect(step2.committedTargetIndex, 8);

        // Ayah 3: user recites repeated phrase 'الرحمن الرحيم'
        final step3 = engine.align(
          targetWords: targetWords,
          transcript: 'الرحمن الرحيم',
          committedTargetIndex: step2.committedTargetIndex,
          isFinal: true,
        );

        expect(step3.committedTargetIndex, 10);
        expect(step3.currentWordIndex, 10);
        expect(step3.omissionsCount, 0);

        // If user accidentally speaks an earlier phrase ('بسم الله') after reaching Ayah 3:
        final backwardStep = engine.align(
          targetWords: targetWords,
          transcript: 'بسم الله',
          committedTargetIndex: step3.committedTargetIndex,
          isFinal: true,
        );

        // Must remain at committed cursor 10, not jump back to 0
        expect(backwardStep.committedTargetIndex, greaterThanOrEqualTo(10));
        expect(backwardStep.rejectedBackwardCandidate, isNotNull);
        expect(
          backwardStep.rejectedBackwardCandidate,
          contains('Rejected backward match'),
        );
      });

      test('Test C: Partial recognition revisions replace provisional tokens without replaying', () async {
        // 1. Finalize Ayah 1
        mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 4);

        // 2. Partial hypothesis 1: 'الحمد'
        mockSpeech.emitTranscript('الحمد', isFinal: false);
        await pumpEventQueue();
        expect(
          cubit.state.committedTargetIndex,
          4,
          reason: 'Committed cursor unchanged on partial result',
        );
        expect(
          cubit.state.matchedWordsCount,
          5,
          reason: 'Provisional match displayed',
        );

        // 3. Partial hypothesis 2 (revised): 'الحمد لله'
        mockSpeech.emitTranscript('الحمد لله', isFinal: false);
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 4);
        expect(cubit.state.matchedWordsCount, 6);

        // 4. Final hypothesis: 'الحمد لله رب العالمين'
        mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 8);
        expect(cubit.state.matchedWordsCount, 8);
        expect(cubit.state.omissionsCount, 0);
      });

      test(
        'Test D: Actual omission is accurately detected and recorded',
        () async {
          // 1. Ayah 1
          mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
          await pumpEventQueue();

          // 2. Ayah 2 with omitted 'رب': user recites 'الحمد لله العالمين'
          mockSpeech.emitTranscript('الحمد لله العالمين', isFinal: true);
          await pumpEventQueue();

          expect(cubit.state.omissionsCount, 1);
          final omission = cubit.state.discrepancies.firstWhere(
            (d) => d.status.isOmission,
          );
          expect(omission.expectedNormalized, 'رب');
          expect(omission.expectedUthmani, 'رَبِّ');
          expect(omission.explanation, contains('سقط في التلاوة'));
          expect(cubit.state.committedTargetIndex, 6);
          expect(cubit.state.currentWordIndex, 6);
          expect(cubit.state.alignedWords[7].status.isUpcoming, isTrue);
          expect(cubit.state.completedGlobalAyahs, {1});

          // Correcting the skipped word releases the gate and clears the error.
          mockSpeech.emitTranscript('رب العالمين', isFinal: true);
          await pumpEventQueue();
          expect(cubit.state.committedTargetIndex, 8);
          expect(cubit.state.matchedWordsCount, 8);
          expect(cubit.state.omissionsCount, 0);
          expect(cubit.state.discrepancies, isEmpty);
        },
      );

      test(
        'Test E: Actual substitution is accurately detected and recorded',
        () async {
          // 1. Ayahs 1, 2, 3
          mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
          await pumpEventQueue();
          mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
          await pumpEventQueue();
          mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: true);
          await pumpEventQueue();

          // 2. Ayah 4 substituted: user recites 'مالك يوم الحساب' instead of 'مالك يوم الدين'
          mockSpeech.emitTranscript('مالك يوم الحساب', isFinal: true);
          await pumpEventQueue();

          expect(cubit.state.substitutionsCount, 1);
          final substitution = cubit.state.discrepancies.firstWhere(
            (d) => d.status.isSubstitution,
          );
          expect(substitution.expectedNormalized, 'الدين');
          expect(substitution.recognizedWord, 'الحساب');
          expect(substitution.explanation, contains('خطأ أو استبدال'));
          expect(cubit.state.committedTargetIndex, 12);
          expect(cubit.state.lifecycle.isCompleted, isFalse);

          // A retry can include the recent correct prefix of the same ayah.
          mockSpeech.emitTranscript('مالك يوم الدين', isFinal: true);
          await pumpEventQueue();
          expect(cubit.state.lifecycle.isCompleted, isTrue);
          expect(cubit.state.matchedWordsCount, 13);
          expect(cubit.state.substitutionsCount, 0);
        },
      );

      test('Test F: Actual repetition (Tardid / Self-correction) is absorbed without penalty', () async {
        // 1. Ayah 1
        mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
        await pumpEventQueue();

        // 2. User repeats 'رب': 'الحمد لله رب رب العالمين'
        mockSpeech.emitTranscript('الحمد لله رب رب العالمين', isFinal: true);
        await pumpEventQueue();

        expect(cubit.state.matchedWordsCount, 8);
        expect(cubit.state.omissionsCount, 0);
        expect(cubit.state.substitutionsCount, 0);
        expect(cubit.state.discrepancies, isEmpty);
      });

      test('Test G: Explicit restart resets cursor, streaming updates cannot move backward', () async {
        mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
        await pumpEventQueue();
        mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 8);

        // Streaming audio cannot move it backward:
        mockSpeech.emitTranscript('بسم الله', isFinal: true);
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, greaterThanOrEqualTo(8));

        // Explicit restart resets to 0:
        await cubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 4,
        );
        expect(cubit.state.committedTargetIndex, 0);
        expect(cubit.state.matchedWordsCount, 0);
      });

      test('Test H: Cumulative streaming (iOS-style) maintains monotonic advancement', () async {
        // Step 1
        mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 4);

        // Step 2: Cumulative transcript
        mockSpeech.emitTranscript(
          'بسم الله الرحمن الرحيم الحمد لله رب العالمين',
          isFinal: true,
        );
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 8);

        // Step 3: Cumulative transcript with repeated 'الرحمن الرحيم'
        mockSpeech.emitTranscript(
          'بسم الله الرحمن الرحيم الحمد لله رب العالمين الرحمن الرحيم',
          isFinal: true,
        );
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 10);
        expect(cubit.state.matchedWordsCount, 10);
        expect(cubit.state.omissionsCount, 0);
      });

      test(
        'Test I: Partial ayahs remain revisable until each segment is final',
        () async {
          mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: false);
          await pumpEventQueue();
          expect(cubit.state.committedTargetIndex, 0);
          expect(cubit.state.matchedWordsCount, 4);
          expect(cubit.state.completedGlobalAyahs, isEmpty);

          mockSpeech.emitTranscript('بسم الله', isFinal: false);
          await pumpEventQueue();
          expect(cubit.state.committedTargetIndex, 0);
          expect(cubit.state.matchedWordsCount, 2);

          mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
          await pumpEventQueue();
          expect(cubit.state.committedTargetIndex, 4);
          mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: false);
          await pumpEventQueue();
          expect(cubit.state.committedTargetIndex, 4);
          expect(cubit.state.matchedWordsCount, 8);
          expect(cubit.state.completedGlobalAyahs, {1});
          mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
          await pumpEventQueue();
          expect(cubit.state.committedTargetIndex, 8);

          mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: false);
          await pumpEventQueue();
          expect(cubit.state.committedTargetIndex, 8);
          expect(cubit.state.currentGlobalAyah, 4);
          expect(cubit.state.matchedWordsCount, 10);
          mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: true);
          await pumpEventQueue();
          expect(cubit.state.committedTargetIndex, 10);
          expect(cubit.state.discrepancies, isEmpty);
        },
      );

      test(
        'Test J: A quiet recognizer status never commits a speculative ayah',
        () async {
          mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
          await pumpEventQueue();
          mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: false);
          await pumpEventQueue();
          expect(cubit.state.committedTargetIndex, 4);
          expect(cubit.state.matchedWordsCount, 8);

          mockSpeech.emitStatus('notListening');
          mockSpeech.emitStatus('done');
          await pumpEventQueue();
          expect(cubit.state.committedTargetIndex, 4);
          await cubit.pauseRecitation();
          expect(cubit.state.committedTargetIndex, 4);
          expect(cubit.state.matchedWordsCount, 4);
          expect(cubit.state.completedGlobalAyahs, {1});
          expect(
            cubit.state.alignedWords
                .skip(4)
                .every((word) => word.status.isUpcoming),
            isTrue,
          );
        },
      );

      test('Test K: Mixed cumulative and utterance-only formats retain the confirmed frontier', () async {
        mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
        await pumpEventQueue();
        mockSpeech.emitTranscript(
          'بسم الله الرحمن الرحيم الحمد لله رب العالمين',
          isFinal: false,
        );
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 4);
        expect(cubit.state.matchedWordsCount, 8);
        mockSpeech.emitTranscript(
          'بسم الله الرحمن الرحيم الحمد لله رب العالمين',
          isFinal: true,
        );
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 8);

        mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: false);
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 8);
        expect(cubit.state.matchedWordsCount, 10);
        mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: true);
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 10);
        expect(cubit.state.currentGlobalAyah, 4);
        expect(cubit.state.omissionsCount, 0);
        expect(cubit.state.discrepancies, isEmpty);
      });

      test('Test L: A finalized error at the first word survives pause and is cleared by retry', () async {
        mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 0);
        expect(cubit.state.omissionsCount, 1);
        expect(cubit.state.discrepancies.single.expectedNormalized, 'بسم');
        await cubit.pauseRecitation();
        expect(cubit.state.committedTargetIndex, 0);
        expect(cubit.state.omissionsCount, 1);
        expect(cubit.state.discrepancies.single.expectedNormalized, 'بسم');

        await cubit.resumeRecitation();
        mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
        await pumpEventQueue();
        expect(cubit.state.committedTargetIndex, 4);
        expect(cubit.state.discrepancies, isEmpty);
        expect(cubit.state.omissionsCount, 0);
      });
    },
  );
}
