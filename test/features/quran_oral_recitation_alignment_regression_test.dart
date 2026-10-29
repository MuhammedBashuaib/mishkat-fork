import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
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

  group('Q14 Al-Fatiha Repeated Phrases & Monotonic Progress Reproduction Tests', () {
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
      await Future<void>.delayed(Duration.zero);
      print(
        'Step 1: Ayah=${cubit.state.currentGlobalAyah}, wordIdx=${cubit.state.currentWordIndex}, matched=${cubit.state.matchedWordsCount}, omissions=${cubit.state.omissionsCount}',
      );

      // 2. User recites Ayah 2: الحمد لله رب العالمين
      mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
      await Future<void>.delayed(Duration.zero);
      print(
        'Step 2: Ayah=${cubit.state.currentGlobalAyah}, wordIdx=${cubit.state.currentWordIndex}, matched=${cubit.state.matchedWordsCount}, omissions=${cubit.state.omissionsCount}',
      );

      // 3. User recites Ayah 3: الرحمن الرحيم (Exact repeated phrase from Ayah 1!)
      mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: true);
      await Future<void>.delayed(Duration.zero);

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
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.matchedWordsCount, 13);
      expect(cubit.state.omissionsCount, 0);
      expect(cubit.state.completedGlobalAyahs, containsAll(<int>{1, 2, 3, 4}));
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
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.committedTargetIndex, 4);

      // 2. Partial hypothesis 1: 'الحمد'
      mockSpeech.emitTranscript('الحمد', isFinal: false);
      await Future<void>.delayed(Duration.zero);
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
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.committedTargetIndex, 4);
      expect(cubit.state.matchedWordsCount, 6);

      // 4. Final hypothesis: 'الحمد لله رب العالمين'
      mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.committedTargetIndex, 8);
      expect(cubit.state.matchedWordsCount, 8);
      expect(cubit.state.omissionsCount, 0);
    });

    test(
      'Test D: Actual omission is accurately detected and recorded',
      () async {
        // 1. Ayah 1
        mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
        await Future<void>.delayed(Duration.zero);

        // 2. Ayah 2 with omitted 'رب': user recites 'الحمد لله العالمين'
        mockSpeech.emitTranscript('الحمد لله العالمين', isFinal: true);
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.omissionsCount, 1);
        final omission = cubit.state.discrepancies.firstWhere(
          (d) => d.status.isOmission,
        );
        expect(omission.expectedNormalized, 'رب');
        expect(omission.expectedUthmani, 'رَبِّ');
        expect(omission.explanation, contains('سقط في التلاوة'));
        expect(cubit.state.committedTargetIndex, 8);
      },
    );

    test(
      'Test E: Actual substitution is accurately detected and recorded',
      () async {
        // 1. Ayahs 1, 2, 3
        mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
        await Future<void>.delayed(Duration.zero);
        mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
        await Future<void>.delayed(Duration.zero);
        mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: true);
        await Future<void>.delayed(Duration.zero);

        // 2. Ayah 4 substituted: user recites 'مالك يوم الحساب' instead of 'مالك يوم الدين'
        mockSpeech.emitTranscript('مالك يوم الحساب', isFinal: true);
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.substitutionsCount, 1);
        final substitution = cubit.state.discrepancies.firstWhere(
          (d) => d.status.isSubstitution,
        );
        expect(substitution.expectedNormalized, 'الدين');
        expect(substitution.recognizedWord, 'الحساب');
        expect(substitution.explanation, contains('خطأ أو استبدال'));
      },
    );

    test('Test F: Actual repetition (Tardid / Self-correction) is absorbed without penalty', () async {
      // 1. Ayah 1
      mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
      await Future<void>.delayed(Duration.zero);

      // 2. User repeats 'رب': 'الحمد لله رب رب العالمين'
      mockSpeech.emitTranscript('الحمد لله رب رب العالمين', isFinal: true);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.matchedWordsCount, 8);
      expect(cubit.state.omissionsCount, 0);
      expect(cubit.state.substitutionsCount, 0);
      expect(cubit.state.discrepancies, isEmpty);
    });

    test('Test G: Explicit restart resets cursor, streaming updates cannot move backward', () async {
      mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
      await Future<void>.delayed(Duration.zero);
      mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.committedTargetIndex, 8);

      // Streaming audio cannot move it backward:
      mockSpeech.emitTranscript('بسم الله', isFinal: true);
      await Future<void>.delayed(Duration.zero);
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
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.committedTargetIndex, 4);

      // Step 2: Cumulative transcript
      mockSpeech.emitTranscript(
        'بسم الله الرحمن الرحيم الحمد لله رب العالمين',
        isFinal: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.committedTargetIndex, 8);

      // Step 3: Cumulative transcript with repeated 'الرحمن الرحيم'
      mockSpeech.emitTranscript(
        'بسم الله الرحمن الرحيم الحمد لله رب العالمين الرحمن الرحيم',
        isFinal: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.committedTargetIndex, 10);
      expect(cubit.state.matchedWordsCount, 10);
      expect(cubit.state.omissionsCount, 0);
    });

    test('Test I: Device reality: Streaming partials with isFinal=false across Ayahs preserve monotonic progress and do not jump backward', () async {
      // Step 1: User recites Ayah 1 with isFinal=false (streaming partial from mic)
      mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: false);
      await Future<void>.delayed(Duration.zero);
      expect(
        cubit.state.committedTargetIndex,
        4,
        reason: 'Ayah 1 completion commits 4 words even on isFinal: false',
      );
      expect(cubit.state.matchedWordsCount, 4);
      expect(cubit.state.omissionsCount, 0);

      // Step 2: User recites Ayah 2 with isFinal=false (utterance-level)
      mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: false);
      await Future<void>.delayed(Duration.zero);
      expect(
        cubit.state.committedTargetIndex,
        8,
        reason: 'Ayah 2 completion commits up to word 8 even on isFinal: false',
      );
      expect(cubit.state.matchedWordsCount, 8);
      expect(cubit.state.omissionsCount, 0);

      // Step 3: User recites Ayah 3: repeated 'الرحمن الرحيم' with isFinal=false
      mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: false);
      await Future<void>.delayed(Duration.zero);

      // CRITICAL INVARIANT:
      // Must NOT jump back to Ayah 1 Basmalah!
      // Must advance to Ayah 4!
      expect(
        cubit.state.currentGlobalAyah,
        4,
        reason: 'Cursor must advance to Ayah 4',
      );
      expect(
        cubit.state.committedTargetIndex,
        10,
        reason: 'Ayah 3 completion commits up to word 10',
      );
      expect(cubit.state.matchedWordsCount, 10, reason: 'All 10 words matched');
      expect(
        cubit.state.omissionsCount,
        0,
        reason: 'Basmalah must NEVER be reported as omitted',
      );
      expect(
        cubit.state.discrepancies,
        isEmpty,
        reason: 'No false discrepancies',
      );
    });

    test('Test J: Device reality: Pause re-arm (status=notListening) without isFinal commits progress', () async {
      // Step 1: Ayah 1 streaming partial
      mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: false);
      await Future<void>.delayed(Duration.zero);
      // Device pause: recognizer pauses on silence, status fires notListening
      mockSpeech.emitStatus('notListening');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.committedTargetIndex, greaterThanOrEqualTo(4));

      // Step 2: Ayah 2 in new session
      mockSpeech.emitTranscript('الحمد لله رب العالمين', isFinal: false);
      await Future<void>.delayed(Duration.zero);
      mockSpeech.emitStatus('notListening');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.committedTargetIndex, greaterThanOrEqualTo(8));

      // Step 3: Ayah 3 in new session with repeated phrase
      mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: false);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.currentGlobalAyah, 4);
      expect(cubit.state.matchedWordsCount, 10);
      expect(cubit.state.omissionsCount, 0);
      expect(cubit.state.discrepancies, isEmpty);
    });

    test('Test K: Device reality: Mixed streaming where earlier Ayahs are cumulative and Ayah 3 flushes to utterance-only', () async {
      // Step 1: Cumulative partial 1
      mockSpeech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: false);
      await Future<void>.delayed(Duration.zero);

      // Step 2: Cumulative partial 2
      mockSpeech.emitTranscript(
        'بسم الله الرحمن الرحيم الحمد لله رب العالمين',
        isFinal: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.committedTargetIndex, 8);

      // Step 3: Recognizer buffer flushed, emits ONLY 'الرحمن الرحيم' (isFinal: false)
      mockSpeech.emitTranscript('الرحمن الرحيم', isFinal: false);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.currentGlobalAyah, 4);
      expect(cubit.state.committedTargetIndex, 10);
      expect(cubit.state.matchedWordsCount, 10);
      expect(cubit.state.omissionsCount, 0);
      expect(cubit.state.discrepancies, isEmpty);
    });
  });
}
