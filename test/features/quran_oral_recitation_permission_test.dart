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
  bool stopCalled = false;
  @override
  Future<void> stop() async {
    stopCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    ],
  );

  final testQuranData = QuranData(
    chapters: [fatihaChapter],
    juz: const [],
    pages: const [],
  );

  late MockSpeechRecognitionService mockSpeech;
  late FakeQuranRepository fakeQuranRepo;
  late InMemoryLocalStorageService storage;
  late QuranMemorizationRepository memRepo;
  late QuranMemorizationCubit memCubit;
  late FakeAudioService fakeAudioService;
  late QuranOralRecitationCubit cubit;

  setUp(() async {
    mockSpeech = MockSpeechRecognitionService(
      initialAvailable: true,
      initialPermission: false, // Default: permission not yet granted
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
  });

  tearDown(() async {
    await cubit.close();
    await memCubit.close();
  });

  group('Q14 Microphone Permission State Machine Tests', () {
    test(
      '1. Initial state without permission enters permissionDenied gate',
      () async {
        await cubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );

        expect(cubit.state.lifecycle, OralRecitationLifecycle.permissionDenied);
        expect(cubit.state.errorMessage, isNull);
      },
    );

    test(
      '2. Permission already granted transitions directly to ready',
      () async {
        mockSpeech.setPermission(true);
        mockSpeech.setAvailable(true);

        await cubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );

        expect(cubit.state.lifecycle, OralRecitationLifecycle.ready);
        expect(cubit.state.errorMessage, isNull);
      },
    );

    test('3. Permission initially undetermined and then granted transitions to ready', () async {
      await cubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 2,
      );
      expect(cubit.state.lifecycle, OralRecitationLifecycle.permissionDenied);

      // User grants permission on prompt
      mockSpeech.autoGrantOnRequest = true;
      await cubit.requestPermissionAndInitialize();

      expect(mockSpeech.permissionRequestCount, 1);
      expect(cubit.state.lifecycle, OralRecitationLifecycle.ready);
      expect(cubit.state.errorMessage, isNull);
    });

    test('4. Permission denied transitions to permissionDenied with Arabic feedback', () async {
      await cubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 2,
      );

      // User denies permission
      mockSpeech.setPermission(false);
      await cubit.requestPermissionAndInitialize();

      expect(mockSpeech.permissionRequestCount, 1);
      expect(cubit.state.lifecycle, OralRecitationLifecycle.permissionDenied);
      expect(cubit.state.errorMessage, contains('نحتاج إلى إذن الميكروفون'));
    });

    test(
      '5. Permission permanently denied shows instructions and openAppSettings',
      () async {
        mockSpeech.setPermanentlyDenied(true);
        await cubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );

        await cubit.openAppSettings();

        expect(mockSpeech.openAppSettingsCount, 1);
        expect(
          cubit.state.lifecycle,
          OralRecitationLifecycle.permissionPermanentlyDenied,
        );
        expect(
          cubit.state.errorMessage,
          contains('إذن الميكروفون مرفوض من إعدادات الجهاز'),
        );
      },
    );

    test(
      '6. User returns from Settings and grants permission refreshes to ready',
      () async {
        mockSpeech.setPermission(false);
        await cubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );
        await cubit.openAppSettings();
        expect(
          cubit.state.lifecycle,
          OralRecitationLifecycle.permissionPermanentlyDenied,
        );

        // User switches toggle in Settings
        mockSpeech.setPermission(true);
        mockSpeech.setAvailable(true);

        // App resumes
        await cubit.checkAndRefreshPermission();

        expect(cubit.state.lifecycle, OralRecitationLifecycle.ready);
        expect(cubit.state.errorMessage, isNull);
      },
    );

    test('7. Speech engine unavailable emits recognizerUnavailable with actionable message', () async {
      mockSpeech.setPermission(true);
      mockSpeech.setAvailable(
        false,
      ); // Engine missing (e.g. no Google Speech Services)

      await cubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 2,
      );

      expect(
        cubit.state.lifecycle,
        OralRecitationLifecycle.recognizerUnavailable,
      );
      expect(cubit.state.errorMessage, contains('حزمة اللغة العربية'));
    });

    test(
      '8. Rapid repeated calls to requestPermissionAndInitialize are guarded',
      () async {
        // Wrap speech service to simulate latency
        final slowSpeech = MockSpeechRecognitionService(
          initialPermission: false,
        )..autoGrantOnRequest = true;
        final testCubit = QuranOralRecitationCubit(
          speechService: slowSpeech,
          quranRepository: fakeQuranRepo,
          memorizationCubit: memCubit,
          audioService: fakeAudioService,
        );
        await testCubit.prepareSession(surahNumber: 1);

        // Trigger 4 concurrent requests rapidly
        final future1 = testCubit.requestPermissionAndInitialize();
        final future2 = testCubit.requestPermissionAndInitialize();
        final future3 = testCubit.requestPermissionAndInitialize();
        final future4 = testCubit.requestPermissionAndInitialize();

        await Future.wait([future1, future2, future3, future4]);

        // Only 1 native request should have executed
        expect(slowSpeech.permissionRequestCount, 1);
        expect(testCubit.state.lifecycle, OralRecitationLifecycle.ready);
        await testCubit.close();
      },
    );

    test(
      '9. startRecitation stops background audio and requires ready state',
      () async {
        mockSpeech.setPermission(true);
        mockSpeech.setAvailable(true);
        await cubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );

        await cubit.startRecitation();

        expect(fakeAudioService.stopCalled, isTrue);
        expect(mockSpeech.isListening, isTrue);
        expect(cubit.state.lifecycle, OralRecitationLifecycle.listening);
      },
    );
  });

  group('Q14 Microphone Permission Widget Tests', () {
    testWidgets(
      'Opening the page requests permission and transitions to ready',
      (tester) async {
        mockSpeech.setPermission(false);
        mockSpeech.autoGrantOnRequest = true;
        mockSpeech.setAvailable(true);

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

        // The page immediately asks for the native permission.
        expect(mockSpeech.permissionRequestCount, 1);

        // Canvas transitions to ready
        expect(find.text('جاهز للتسميع'), findsOneWidget);
        expect(find.text('بدء التسميع'), findsOneWidget);
      },
    );

    testWidgets(
      'Permission permanently denied shows فتح إعدادات التطبيق button',
      (tester) async {
        mockSpeech.setPermission(false);
        mockSpeech.setPermanentlyDenied(true);

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

        // The automatic request detects permanent denial and offers Settings.
        expect(mockSpeech.permissionRequestCount, 1);
        expect(
          find.text('إذن الميكروفون مرفوض من إعدادات الجهاز'),
          findsOneWidget,
        );
        expect(find.text('فتح إعدادات التطبيق'), findsOneWidget);
        expect(find.text('إعادة التحقق من الإذن'), findsOneWidget);

        // Tap فتح إعدادات التطبيق
        await tester.tap(find.text('فتح إعدادات التطبيق'));
        await tester.pumpAndSettle();
        expect(mockSpeech.openAppSettingsCount, 1);
      },
    );
  });
}
