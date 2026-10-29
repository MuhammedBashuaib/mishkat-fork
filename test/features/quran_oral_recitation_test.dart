import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_oral_recitation_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_alignment_engine.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class InMemoryLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> _data = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) {
    final v = _data[key];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  @override
  List<dynamic> readList(String key) {
    final value = _data[key];
    return value is List ? List<dynamic>.from(value) : <dynamic>[];
  }

  @override
  int readInt(String key, [int fallback = 0]) {
    final value = _data[key];
    return value is num ? value.toInt() : fallback;
  }

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _data[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _data[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> clear() async {
    _data.clear();
  }
}

class FakeQuranRepository extends QuranRepository {
  FakeQuranRepository({required this.data});
  final QuranData data;

  @override
  Future<QuranData> load() async => data;
}

class FakeAudioService extends QuranAudioService {
  bool stopCalled = false;

  @override
  Future<void> stop() async {
    stopCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Test Fixture: Surah Al-Fatiha (Ayahs 1-4)
  final fatihaChapter = QuranChapter(
    number: 1,
    name: 'الفاتحة',
    englishName: 'Al-Faatiha',
    revelationType: 'Meccan',
    page: 1,
    globalStart: 1,
    ayahs: const [
      'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
      'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
      'ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
      'مَٰلِكِ يَوْمِ ٱلدِّينِ',
    ],
  );

  final testQuranData = QuranData(
    chapters: [fatihaChapter],
    juz: const [],
    pages: const [],
  );

  group('QuranAlignmentEngine Production Tests', () {
    const engine = QuranAlignmentEngine();

    late List<AuthoritativeWord> targetWords;

    setUp(() {
      targetWords = engine.prepareTargetTokens(
        chapters: [fatihaChapter],
        startGlobalAyah: 1,
        endGlobalAyah: 4,
      );
    });

    test('1. Prepare tokens extracts authoritative words with normalized comparisons', () {
      expect(targetWords.isNotEmpty, isTrue);
      // Ayah 1: بسم الله الرحمن الرحيم = 4 words
      expect(targetWords[0].uthmaniText, 'بِسْمِ');
      expect(targetWords[0].normalizedText, 'بسم');
      expect(targetWords[1].uthmaniText, 'ٱللَّهِ');
      expect(targetWords[1].normalizedText, 'الله');
      expect(targetWords[2].uthmaniText, 'ٱلرَّحْمَٰنِ');
      expect(targetWords[2].normalizedText, 'الرحمن');
      expect(targetWords[3].uthmaniText, 'ٱلرَّحِيمِ');
      expect(targetWords[3].normalizedText, 'الرحيم');
    });

    test('2. Perfect recitation matches all words and completes sequence', () {
      const transcript =
          'بسم الله الرحمن الرحيم الحمد لله رب العالمين الرحمن الرحيم مالك يوم الدين';

      final result = engine.align(
        targetWords: targetWords,
        transcript: transcript,
      );

      expect(result.isCompleted, isTrue);
      expect(result.omissionsCount, 0);
      expect(result.substitutionsCount, 0);
      expect(result.matchedWordsCount, targetWords.length);
      expect(result.discrepancies, isEmpty);
      expect(result.progressPercentage, 100.0);
    });

    test('3. Reciter omits a word (Likely Omission detected in red)', () {
      // Omitted 'رب' from 'الحمد لله رب العالمين'
      const transcript = 'بسم الله الرحمن الرحيم الحمد لله العالمين';

      final result = engine.align(
        targetWords: targetWords,
        transcript: transcript,
      );

      expect(result.omissionsCount, greaterThanOrEqualTo(1));
      final omission = result.discrepancies.firstWhere(
        (d) => d.status.isOmission,
      );
      expect(omission.expectedNormalized, 'رب');
      expect(omission.explanation, contains('سقط في التلاوة'));
    });

    test('4. Reciter substitutes a word (Likely Substitution detected)', () {
      // Substituted 'يوم الدين' with 'يوم الحساب'
      const transcript =
          'بسم الله الرحمن الرحيم الحمد لله رب العالمين الرحمن الرحيم مالك يوم الحساب';

      final result = engine.align(
        targetWords: targetWords,
        transcript: transcript,
      );

      expect(result.substitutionsCount, greaterThanOrEqualTo(1));
      final sub = result.discrepancies.firstWhere(
        (d) => d.status.isSubstitution,
      );
      expect(sub.expectedNormalized, 'الدين');
      expect(sub.recognizedWord, 'الحساب');
      expect(sub.explanation, contains('خطأ أو استبدال'));
    });

    test('5. Reciter repeats a word (Repetition / self-correction handled gracefully)', () {
      // Reciter repeats 'الرحمن'
      const transcript = 'بسم الله الرحمن الرحمن الرحيم';

      final result = engine.align(
        targetWords: targetWords.sublist(0, 4),
        transcript: transcript,
      );

      // Repetition should not be counted as an error
      expect(result.substitutionsCount, 0);
      expect(result.omissionsCount, 0);
      expect(result.matchedWordsCount, 4);
    });

    test('6. Low confidence marks word as uncertain rather than error', () {
      const transcript = 'بسم الله الرحمن الرحيم';

      final result = engine.align(
        targetWords: targetWords.sublist(0, 4),
        transcript: transcript,
        confidence: 0.5, // low confidence
      );

      expect(result.uncertainCount, greaterThan(0));
      expect(result.discrepancies.any((d) => d.status.isUncertain), isTrue);
    });

    test(
      '7. Basmalah preamble before non-Fatiha surah is handled without error',
      () {
        // Target is Ayah 2 onwards (الحمد لله رب العالمين)
        final subTarget = targetWords.sublist(4, 8);
        // User recites Basmalah first then starts
        const transcript = 'بسم الله الرحمن الرحيم الحمد لله رب العالمين';

        final result = engine.align(
          targetWords: subTarget,
          transcript: transcript,
        );

        expect(result.omissionsCount, 0);
        expect(result.substitutionsCount, 0);
        expect(result.matchedWordsCount, 4);
      },
    );
  });

  group('QuranOralRecitationCubit Production Tests', () {
    late MockSpeechRecognitionService mockSpeech;
    late FakeQuranRepository fakeQuranRepo;
    late InMemoryLocalStorageService storage;
    late QuranMemorizationRepository memRepo;
    late QuranMemorizationCubit memCubit;
    late FakeAudioService fakeAudioService;
    late QuranOralRecitationCubit oralCubit;

    setUp(() async {
      mockSpeech = MockSpeechRecognitionService();
      fakeQuranRepo = FakeQuranRepository(data: testQuranData);
      storage = InMemoryLocalStorageService();
      memRepo = QuranMemorizationRepository(storage: storage);
      memCubit = QuranMemorizationCubit(repository: memRepo);
      await memCubit.load();
      fakeAudioService = FakeAudioService();

      oralCubit = QuranOralRecitationCubit(
        speechService: mockSpeech,
        quranRepository: fakeQuranRepo,
        memorizationCubit: memCubit,
        audioService: fakeAudioService,
      );
    });

    tearDown(() async {
      await oralCubit.close();
      await memCubit.close();
    });

    test(
      '1. prepareSession initializes target tokens and sets ready state',
      () async {
        await oralCubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );

        expect(oralCubit.state.surahName, 'الفاتحة');
        expect(
          oralCubit.state.targetWords.length,
          8,
        ); // 4 words in Ayah 1 + 4 words in Ayah 2
        expect(oralCubit.state.lifecycle, OralRecitationLifecycle.ready);
        expect(oralCubit.state.sessionId, isNotNull);
      },
    );

    test(
      '2. startRecitation stops background audio and begins listening',
      () async {
        await oralCubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );
        await oralCubit.startRecitation();

        expect(fakeAudioService.stopCalled, isTrue);
        expect(mockSpeech.isListening, isTrue);
        expect(oralCubit.state.lifecycle, OralRecitationLifecycle.listening);
        expect(mockSpeech.lastLocaleId, 'ar_SA');
        expect(
          mockSpeech.lastContextualPhrases,
          containsAll(<String>['بسم', 'الله', 'الرحمن', 'الرحيم']),
        );
      },
    );

    test('3. Permission denial emits permissionDenied lifecycle', () async {
      mockSpeech.setPermission(false);
      await oralCubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 2,
      );
      await oralCubit.startRecitation();

      expect(
        oralCubit.state.lifecycle,
        OralRecitationLifecycle.permissionDenied,
      );
      expect(oralCubit.state.errorMessage, isNotNull);
    });

    test(
      '3a. Permanent permission denial directs the user to app settings',
      () async {
        mockSpeech
          ..setPermission(false)
          ..setPermanentlyDenied(true);
        await oralCubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );

        await oralCubit.startRecitation();

        expect(
          oralCubit.state.lifecycle,
          OralRecitationLifecycle.permissionPermanentlyDenied,
        );
        expect(mockSpeech.permissionRequestCount, 1);

        await oralCubit.openAppSettings();
        expect(mockSpeech.openAppSettingsCount, 1);
      },
    );

    test(
      '3b. Missing Arabic locale shows repair state and recovers after setup',
      () async {
        await oralCubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );
        await oralCubit.startRecitation();
        mockSpeech.setArabicLocale(false);

        mockSpeech.emitError(
          'العربية غير مفعّلة في خدمة التعرف الصوتي.',
          type: SpeechRecognitionFailureType.languageUnavailable,
          isPermanent: true,
        );
        await pumpEventQueue();

        expect(
          oralCubit.state.lifecycle,
          OralRecitationLifecycle.languageUnavailable,
        );
        expect(mockSpeech.isListening, isFalse);

        await oralCubit.openSpeechRecognitionSettings();
        expect(mockSpeech.openSpeechRecognitionSettingsCount, 1);

        mockSpeech.setArabicLocale(true);
        await oralCubit.checkAndRefreshPermission();
        expect(oralCubit.state.lifecycle, OralRecitationLifecycle.ready);
        expect(oralCubit.state.errorMessage, isNull);
      },
    );

    test(
      '4. Streaming speech transcript updates alignment and progress',
      () async {
        await oralCubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );
        await oralCubit.startRecitation();

        mockSpeech.emitTranscript('بسم الله الرحمن الرحيم');
        await pumpEventQueue();

        expect(oralCubit.state.matchedWordsCount, 4);
        expect(oralCubit.state.progressPercentage, 50.0);
        expect(oralCubit.state.liveTranscript, 'بسم الله الرحمن الرحيم');
        expect(oralCubit.state.completedGlobalAyahs, contains(1));
      },
    );

    test(
      '5. Pausing and resuming recitation controls recognition stream',
      () async {
        await oralCubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );
        await oralCubit.startRecitation();

        await oralCubit.pauseRecitation();
        expect(oralCubit.state.lifecycle, OralRecitationLifecycle.paused);
        expect(mockSpeech.isListening, isFalse);

        await oralCubit.resumeRecitation();
        expect(oralCubit.state.lifecycle, OralRecitationLifecycle.listening);
        expect(mockSpeech.isListening, isTrue);
      },
    );

    test('5a. completed native cycle restarts only after done', () async {
      await oralCubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 2,
      );
      await oralCubit.startRecitation();
      expect(mockSpeech.startListeningCount, 1);

      mockSpeech.emitStatus('notListening');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(mockSpeech.startListeningCount, 1);

      mockSpeech.emitStatus('done');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(mockSpeech.startListeningCount, 2);
      expect(oralCubit.state.lifecycle, OralRecitationLifecycle.listening);
      expect(mockSpeech.isListening, isTrue);
    });

    test(
      '5b. silence error re-arms recognition without pausing the session',
      () async {
        await oralCubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );
        await oralCubit.startRecitation();

        mockSpeech.emitError(
          'لم أتمكن من تمييز الكلام بوضوح. اقترب من الميكروفون وحاول مجددًا.',
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));

        expect(oralCubit.state.lifecycle, OralRecitationLifecycle.listening);
        expect(oralCubit.state.errorMessage, isNull);
        expect(mockSpeech.startListeningCount, 2);
        expect(mockSpeech.isListening, isTrue);
      },
    );

    test('6. Revealing and hiding authoritative Ayah text', () async {
      await oralCubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 2,
      );

      oralCubit.revealAyah(1);
      expect(oralCubit.state.revealedGlobals, contains(1));

      oralCubit.hideAyah(1);
      expect(oralCubit.state.revealedGlobals, isNot(contains(1)));
    });

    test('7. Completing full sequence triggers summary and allows memorization commit', () async {
      await oralCubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 2,
      );
      await oralCubit.startRecitation();

      mockSpeech.emitTranscript('بسم الله الرحمن الرحيم الحمد لله رب العالمين');
      await pumpEventQueue();

      expect(oralCubit.state.lifecycle, OralRecitationLifecycle.completed);
      expect(oralCubit.state.summary, isNotNull);
      expect(oralCubit.state.summary!.accuracyPercentage, 100.0);

      // Commit to memorization cubit
      await oralCubit.commitToMemorization();
      expect(oralCubit.state.isMemorizationCommitted, isTrue);

      // Verify that memorization cubit recorded the review
      expect(memCubit.state.history.length, 2); // 2 Ayahs committed
      expect(memCubit.state.history.first.globalAyah, 1);
    });

    test(
      '8. Recognition failure pauses safely and preserves session progress',
      () async {
        await oralCubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );
        await oralCubit.startRecitation();
        mockSpeech.emitTranscript('بسم الله');
        await pumpEventQueue();
        final progressBeforeError = oralCubit.state.matchedWordsCount;

        mockSpeech.emitError('تعذّر الوصول إلى الميكروفون.');
        await pumpEventQueue();

        expect(oralCubit.state.lifecycle, OralRecitationLifecycle.paused);
        expect(oralCubit.state.matchedWordsCount, progressBeforeError);
        expect(oralCubit.state.errorMessage, contains('الميكروفون'));
      },
    );

    test('9. Empty session cannot write false review history', () async {
      await oralCubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 2,
      );
      await oralCubit.finishSession();
      await oralCubit.commitToMemorization();

      expect(oralCubit.state.isMemorizationCommitted, isFalse);
      expect(memCubit.state.history, isEmpty);
      expect(oralCubit.state.errorMessage, contains('لم تُسمع آية'));
    });

    test(
      '10. Memorization outcome is calculated independently for each Ayah',
      () async {
        await oralCubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );
        await oralCubit.startRecitation();
        mockSpeech.emitTranscript(
          'بسم الله الرحمن الرحيم خطأ خطأ خطأ خطأ',
          isFinal: true,
        );
        await pumpEventQueue();
        await oralCubit.commitToMemorization();

        expect(memCubit.state.history, hasLength(2));
        final first = memCubit.state.history.firstWhere(
          (record) => record.globalAyah == 1,
        );
        final second = memCubit.state.history.firstWhere(
          (record) => record.globalAyah == 2,
        );
        expect(first.outcome.name, 'easy');
        expect(second.outcome.name, 'failed');
      },
    );
  });

  group('QuranOralRecitationPage Widget Tests', () {
    late MockSpeechRecognitionService mockSpeech;
    late FakeQuranRepository fakeQuranRepo;
    late InMemoryLocalStorageService storage;
    late QuranMemorizationRepository memRepo;
    late QuranMemorizationCubit memCubit;

    setUp(() async {
      mockSpeech = MockSpeechRecognitionService();
      fakeQuranRepo = FakeQuranRepository(data: testQuranData);
      storage = InMemoryLocalStorageService();
      memRepo = QuranMemorizationRepository(storage: storage);
      memCubit = QuranMemorizationCubit(repository: memRepo);
      await memCubit.load();
    });

    testWidgets('Renders Oral Recitation page with setup and start button', (
      tester,
    ) async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranMemorizationCubit>.value(value: memCubit),
            RepositoryProvider<QuranRepository>.value(value: fakeQuranRepo),
          ],
          child: MaterialApp(
            home: QuranOralRecitationPage(
              surahNumber: 1,
              startGlobalAyah: 1,
              endGlobalAyah: 2,
              speechService: mockSpeech,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('التسميع الشفهي الذكي'), findsOneWidget);
      expect(find.text('بدء التسميع'), findsOneWidget);
      expect(find.text('جاهز للتسميع'), findsOneWidget);
    });

    testWidgets(
      'Page requests microphone access on entry and becomes ready when granted',
      (tester) async {
        final gatedSpeech = MockSpeechRecognitionService(
          initialPermission: false,
        )..autoGrantOnRequest = true;

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<QuranMemorizationCubit>.value(value: memCubit),
              RepositoryProvider<QuranRepository>.value(value: fakeQuranRepo),
            ],
            child: MaterialApp(
              home: QuranOralRecitationPage(
                surahNumber: 1,
                startGlobalAyah: 1,
                endGlobalAyah: 2,
                speechService: gatedSpeech,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(gatedSpeech.permissionRequestCount, 1);
        expect(find.text('جاهز للتسميع'), findsOneWidget);
        expect(find.text('بدء التسميع'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await gatedSpeech.dispose();
      },
    );

    testWidgets(
      'Arabic recognition failure shows an in-page settings repair action',
      (tester) async {
        final languageSpeech = MockSpeechRecognitionService();
        final languageCubit = QuranOralRecitationCubit(
          speechService: languageSpeech,
          quranRepository: fakeQuranRepo,
          memorizationCubit: memCubit,
        );
        await languageCubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );
        await languageCubit.startRecitation();

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<QuranMemorizationCubit>.value(value: memCubit),
              RepositoryProvider<QuranRepository>.value(value: fakeQuranRepo),
            ],
            child: MaterialApp(
              home: QuranOralRecitationPage(cubit: languageCubit),
            ),
          ),
        );
        await tester.pump();

        languageSpeech.emitError(
          'العربية غير مفعّلة في خدمة التعرف الصوتي.',
          type: SpeechRecognitionFailureType.languageUnavailable,
          isPermanent: true,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('فعّل العربية للتسميع الصوتي'), findsOneWidget);
        expect(find.text('فتح إعدادات الإدخال الصوتي'), findsOneWidget);

        await tester.tap(find.text('فتح إعدادات الإدخال الصوتي'));
        await tester.pump();
        expect(languageSpeech.openSpeechRecognitionSettingsCount, 1);

        await tester.pumpWidget(const SizedBox());
        await languageCubit.close();
        await languageSpeech.dispose();
      },
    );

    testWidgets(
      'Tapping start activates microphone listening state and updates UI',
      (tester) async {
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<QuranMemorizationCubit>.value(value: memCubit),
              RepositoryProvider<QuranRepository>.value(value: fakeQuranRepo),
            ],
            child: MaterialApp(
              home: QuranOralRecitationPage(
                surahNumber: 1,
                startGlobalAyah: 1,
                endGlobalAyah: 2,
                speechService: mockSpeech,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        await tester.tap(find.text('بدء التسميع'));
        await tester.pumpAndSettle();

        expect(find.text('جاري الاستماع...'), findsOneWidget);
        expect(find.text('إيقاف مؤقت'), findsOneWidget);

        // Emit recognized words
        mockSpeech.emitTranscript('بسم الله');
        await tester.pumpAndSettle();

        expect(find.text('مسموع: '), findsOneWidget);
        expect(find.text('بسم الله'), findsOneWidget);
      },
    );

    testWidgets('Omitted Quran word remains visible in red at its position', (
      tester,
    ) async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranMemorizationCubit>.value(value: memCubit),
            RepositoryProvider<QuranRepository>.value(value: fakeQuranRepo),
          ],
          child: MaterialApp(
            home: QuranOralRecitationPage(
              surahNumber: 1,
              startGlobalAyah: 1,
              endGlobalAyah: 3,
              speechService: mockSpeech,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('بدء التسميع'));
      await tester.pump();

      // Omit «رَبِّ» while continuing with «ٱلْعَٰلَمِينَ».
      mockSpeech.emitTranscript(
        'بسم الله الرحمن الرحيم الحمد لله العالمين',
        isFinal: true,
      );
      await tester.pump();

      final omitted = tester.widget<Text>(find.text('رَبِّ'));
      expect(omitted.style?.color, isNotNull);
      expect(omitted.style?.decoration, TextDecoration.underline);
      final color = omitted.style!.color!;
      expect(color.r, greaterThan(color.g));
      expect(color.r, greaterThan(color.b));
    });

    testWidgets('Moving app to background pauses microphone capture', (
      tester,
    ) async {
      final oralCubit = QuranOralRecitationCubit(
        speechService: mockSpeech,
        quranRepository: fakeQuranRepo,
        memorizationCubit: memCubit,
      );
      await oralCubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 2,
      );
      await oralCubit.startRecitation();

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<QuranMemorizationCubit>.value(value: memCubit),
            RepositoryProvider<QuranRepository>.value(value: fakeQuranRepo),
          ],
          child: MaterialApp(home: QuranOralRecitationPage(cubit: oralCubit)),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockSpeech.isListening, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(mockSpeech.isListening, isFalse);
      expect(oralCubit.state.lifecycle, OralRecitationLifecycle.paused);
      await oralCubit.close();
    });
  });
}
