import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/quran_audio_station.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_state.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_audio_player_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_index_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_memorization_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_search_page.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/quran_search_history_view.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/quran_search_reference_card.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/quran_search_result_tile.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

class InMemoryLocalStorage implements LocalStorageService {
  final Map<String, dynamic> _store = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) {
    final val = _store[key];
    return val is Map ? Map<String, dynamic>.from(val) : <String, dynamic>{};
  }

  @override
  List<dynamic> readList(String key) {
    final val = _store[key];
    return val is List ? List<dynamic>.from(val) : <dynamic>[];
  }

  @override
  int readInt(String key, [int fallback = 0]) {
    final val = _store[key];
    return val is num ? val.toInt() : fallback;
  }

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _store[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _store[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    _store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

class TestQuranAudioService implements QuranAudioService {
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  String? lastPlayedReciter;
  int? lastPlayedAyah;
  String? lastPlayedStreamUrl;
  bool isPlayingState = false;

  @override
  Stream<PlayerState> get playerState => _stateController.stream;

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();

  @override
  bool get isPlaying => isPlayingState;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  Duration? get duration => const Duration(seconds: 10);

  @override
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async {
    lastPlayedReciter = reciter;
    lastPlayedAyah = globalAyah;
    isPlayingState = true;
    _stateController.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    isPlayingState = false;
    _stateController.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> resume() async {
    isPlayingState = true;
    _stateController.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    isPlayingState = false;
    lastPlayedStreamUrl = null;
    _stateController.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> seek(Duration position) async {}

  Future<void> playStreamUrl(String url) async {
    lastPlayedStreamUrl = url;
    isPlayingState = true;
    _stateController.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
  }
}

class FakeLocationService implements LocationService {
  @override
  Future<AppPosition> currentPosition() async {
    return const AppPosition(
      latitude: 14.5425,
      longitude: 49.1242,
      label: 'المكلا، حضرموت',
      suggestedMethod: 'MWL',
    );
  }

  @override
  NearbyCity closestCity(double latitude, double longitude) {
    return const NearbyCity('المكلا، حضرموت', 14.5425, 49.1242, 'MWL', 0);
  }
}

class FakeNotificationService implements LocalNotificationService {
  @override
  Future<bool> canSchedulePrecisely() async => true;

  @override
  Future<void> stopTest() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleAll(
    List<ScheduledAppNotification> notifications,
  ) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> showTest({
    required bool sound,
    required bool vibrate,
    String? soundName,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranRepository globalQuranRepo;
  late InMemoryLocalStorage storage;
  late TestQuranAudioService audioService;
  late SettingsCubit settingsCubit;

  setUpAll(() async {
    globalQuranRepo = QuranRepository();
    await globalQuranRepo.load();

    final layoutRepo = MushafLayoutRepository.instance;
    if (!layoutRepo.isLoaded) {
      await layoutRepo.load();
    }
  });

  setUp(() async {
    storage = InMemoryLocalStorage();
    audioService = TestQuranAudioService();
    settingsCubit = SettingsCubit(
      storage: storage,
      locationService: FakeLocationService(),
      notifications: FakeNotificationService(),
    );
    await settingsCubit.load();
  });

  tearDown(() {
    settingsCubit.close();
    audioService.dispose();
  });

  Widget buildTestApp({
    required QuranCubit quranCubit,
    QuranMemorizationCubit? memCubit,
    ThemeMode themeMode = ThemeMode.light,
    Size size = const Size(390, 844),
  }) {
    final effectiveMemCubit =
        memCubit ??
        QuranMemorizationCubit(
          repository: QuranMemorizationRepository(storage: storage),
        );

    return RepositoryProvider<LocalStorageService>.value(
      value: storage,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
          BlocProvider<QuranCubit>.value(value: quranCubit),
          BlocProvider<QuranMemorizationCubit>.value(value: effectiveMemCubit),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(1.0),
          darkTheme: AppTheme.dark(1.0),
          themeMode: themeMode,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQueryData(size: size),
              child: const Scaffold(body: QuranPage()),
            ),
          ),
        ),
      ),
    );
  }

  void setTestViewport(
    WidgetTester tester, {
    Size size = const Size(390, 1200),
  }) {
    tester.view.physicalSize = Size(size.width * 2, size.height * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Quran Home Hub Redesign — Stage 5 Production Tests', () {
    testWidgets('1. Three-section hub renders with correct Arabic hierarchy', (
      tester,
    ) async {
      setTestViewport(tester, size: const Size(390, 1200));

      final quranCubit = QuranCubit(
        repository: globalQuranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();

      await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
      await pumpScreen(tester);

      // Top Header
      expect(find.text('القرآن الكريم'), findsOneWidget);
      expect(find.text('مصحف المدينة · حفص عن عاصم'), findsOneWidget);

      // Section A: المصحف الشريف
      expect(find.text('المصحف الشريف'), findsOneWidget);
      expect(find.text('اقرأ وتدبّر، وتابع من موضعك'), findsOneWidget);
      expect(find.text('فتح المصحف'), findsOneWidget);

      // Section B: المشغّل القرآني
      expect(find.text('المشغّل القرآني'), findsOneWidget);
      expect(find.text('استمع إلى التلاوات والإذاعات'), findsOneWidget);
      expect(find.text('فتح المشغّل القرآني'), findsOneWidget);

      // Section C: التحفيظ والمراجعة
      expect(find.text('التحفيظ والمراجعة'), findsOneWidget);
      expect(find.text('خطّط لحفظك، سمّع، وراجع تقدّمك'), findsOneWidget);
      expect(find.text('لوحة التحفيظ'), findsOneWidget);

      // The landing page keeps only the two universal shortcuts.
      expect(find.text('ابحث عن سورة أو آية'), findsOneWidget);
      expect(find.text('آخر علامة'), findsOneWidget);
      expect(find.text('فهرس السور'), findsNothing);
      expect(find.text('الأجزاء'), findsNothing);

      quranCubit.close();
    });

    testWidgets(
      '2. Opening Mushaf navigates to QuranIndexPage and then to production QuranReaderPage',
      (tester) async {
        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
        await pumpScreen(tester);

        // Tap 'فتح المصحف'
        final openMushafBtn = find.text('فتح المصحف');
        expect(openMushafBtn, findsOneWidget);
        await tester.tap(openMushafBtn);
        await pumpScreen(tester);

        // Verify QuranIndexPage is pushed with the 3 tabs
        expect(find.byType(QuranIndexPage), findsOneWidget);
        expect(find.text('فهرس القرآن الكريم'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'السور'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'الأجزاء'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'العلامات'), findsOneWidget);

        // Tap on a Surah (Al-Fatihah)
        final fatihahTile = find.textContaining('فَاتِحَة');
        expect(fatihahTile, findsWidgets);
        await tester.tap(fatihahTile.first);
        await pumpScreen(tester);

        // Verify production QuranReaderPage is opened
        expect(find.byType(QuranReaderPage), findsOneWidget);
        expect(find.text('حجم الصفحة'), findsOneWidget);
        expect(find.byTooltip('تكبير المصحف'), findsOneWidget);
        expect(find.byTooltip('تصغير المصحف'), findsOneWidget);

        quranCubit.close();
      },
    );

    testWidgets('3. Search entry opens the dedicated Quran search page', (
      tester,
    ) async {
      final quranCubit = QuranCubit(
        repository: globalQuranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();

      await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
      await pumpScreen(tester);

      await tester.tap(find.text('ابحث عن سورة أو آية'));
      await pumpScreen(tester);
      expect(find.byType(QuranSearchPage), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      quranCubit.close();
    });

    for (final scenario in [
      (query: 'الكهف', surah: 18, ayah: 1, kind: 'surah'),
      (query: 'قل هو الله احد', surah: 112, ayah: 1, kind: 'ayah'),
      (query: '٢:٢٥٥', surah: 2, ayah: 255, kind: 'reference'),
    ]) {
      testWidgets('Search result opens the correct ${scenario.kind}', (
        tester,
      ) async {
        setTestViewport(tester, size: const Size(800, 1200));
        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();
        addTearDown(quranCubit.close);

        await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
        await tester.tap(find.text('ابحث عن سورة أو آية'));
        await pumpScreen(tester);
        await tester.enterText(find.byType(TextField), scenario.query);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        final data = quranCubit.state.data!;
        final global = data.globalFor(scenario.surah, scenario.ayah);
        final page = data.pageForGlobal(global);
        final target = switch (scenario.kind) {
          'surah' =>
            find.text('سورة ${data.chapter(scenario.surah).name}').last,
          'ayah' =>
            find
                .descendant(
                  of: find.byType(QuranSearchResultTile).first,
                  matching: find.byType(RichText),
                )
                .first,
          _ => find.byType(QuranSearchReferenceCard),
        };
        await tester.ensureVisible(target);
        await tester.tap(target);
        await pumpScreen(tester);

        expect(tester.takeException(), isNull);
        expect(find.byType(QuranReaderPage), findsOneWidget);
        expect(quranCubit.state.currentPage, page);
        expect(quranCubit.state.lastRead?.global, global);
        expect(
          tester
              .widget<QuranReaderPage>(find.byType(QuranReaderPage))
              .initialGlobalAyah,
          global,
        );
        expect(
          tester.widget<PageView>(find.byType(PageView)).controller!.page,
          (page - 1).toDouble(),
        );
        expect(storage.readList('quran_search_history'), [scenario.query]);

        // History must survive closing and reopening the search page.
        await tester.tap(find.byTooltip('العودة إلى الفهرس'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ابحث عن سورة أو آية'));
        await pumpScreen(tester);
        expect(
          tester
              .widget<QuranSearchHistoryView>(
                find.byType(QuranSearchHistoryView),
              )
              .recentSearches,
          [scenario.query],
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('4. First-use bookmark state stays concise and actionable', (
      tester,
    ) async {
      final quranCubit = QuranCubit(
        repository: globalQuranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();

      await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
      await pumpScreen(tester);

      expect(find.text('آخر علامة'), findsOneWidget);
      expect(find.text('لم تضف علامة بعد'), findsOneWidget);

      quranCubit.close();
    });

    testWidgets('5. Destination B: المشغّل القرآني navigation and tabs', (
      tester,
    ) async {
      setTestViewport(tester, size: const Size(500, 1600));

      final quranCubit = QuranCubit(
        repository: globalQuranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();

      await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
      await pumpScreen(tester);

      // Tap 'فتح المشغّل القرآني'
      await tester.tap(find.text('فتح المشغّل القرآني'));
      await pumpScreen(tester);

      // Verify on QuranAudioPlayerPage
      expect(find.byType(QuranAudioPlayerPage), findsOneWidget);
      expect(find.text('القراء والتلاوات'), findsOneWidget);
      expect(find.text('البث المباشر'), findsOneWidget);
      expect(find.text('إذاعات القرآن'), findsWidgets);

      // Verify verified reciters present
      expect(find.text('مشاري العفاسي'), findsOneWidget);
      expect(find.text('عبد الرحمن السديس'), findsOneWidget);
      expect(find.text('ماهر المعيقلي'), findsOneWidget);
      expect(find.text('سعود الشريم'), findsOneWidget);

      // Verify newly connected reciters are available in the main catalog.
      expect(find.text('بندر بليلة'), findsOneWidget);
      expect(find.text('عبدالله عواد الجهني'), findsOneWidget);
      expect(find.text('ناصر القطامي'), findsOneWidget);
      expect(find.text('ياسر الدوسري'), findsOneWidget);
      expect(find.textContaining('بانتظار توثيق'), findsNothing);
      expect(find.text('غير متاح حالياً'), findsNothing);

      quranCubit.close();
    });

    testWidgets(
      '6. Live Streams and Radio Stations are verified and playable',
      (tester) async {
        setTestViewport(tester, size: const Size(600, 2200));

        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
        await pumpScreen(tester);

        await tester.tap(find.text('فتح المشغّل القرآني'));
        await pumpScreen(tester);

        // Switch to Live Streams tab
        await tester.tap(find.text('البث المباشر'));
        await pumpScreen(tester);

        expect(find.text('بث المسجد الحرام'), findsOneWidget);
        expect(find.text('بث المسجد النبوي'), findsOneWidget);
        expect(find.text('مباشر الآن'), findsNWidgets(2));
        expect(find.text('مصدر رسمي'), findsNWidgets(2));
        expect(find.text('شاهد البث'), findsNWidgets(2));

        final liveStreams = QuranAudioStation.defaultCatalog
            .where(
              (station) => station.category == AudioStationCategory.liveStream,
            )
            .toList(growable: false);
        expect(liveStreams, hasLength(2));
        expect(liveStreams.every((station) => station.isWatchable), isTrue);
        expect(
          liveStreams.map((station) => station.watchUrl),
          containsAll(<String>[
            'https://www.youtube.com/@SaudiQuranTv/live',
            'https://www.youtube.com/@SaudiSunnahTv/live',
          ]),
        );
        expect(
          liveStreams.map((station) => station.youtubeChannelId),
          containsAll(<String>[
            'UCos52azQNBgW63_9uDJoPDA',
            'UCROKYPep-UuODNwyipe6JMw',
          ]),
        );

        // Switch to Radio Stations tab (tap the tab in the TabBar)
        await tester.tap(
          find.widgetWithText(Tab, 'إذاعات القرآن'),
          warnIfMissed: false,
        );
        await pumpScreen(tester);

        expect(find.text('إذاعة القرآن الكريم من القاهرة'), findsOneWidget);
        expect(find.text('إذاعة القرآن الكريم من الرياض'), findsOneWidget);
        expect(find.text('إذاعة القرآن الكريم من الشارقة'), findsOneWidget);
        expect(find.text('إذاعة القرآن الكريم من قطر'), findsOneWidget);
        expect(find.text('إذاعة القرآن الكريم من البحرين'), findsOneWidget);
        expect(find.text('إذاعة التلاوات الخاشعة'), findsOneWidget);
        expect(find.text('إذاعة تراتيل قصيرة'), findsOneWidget);
        expect(find.text('إذاعة آيات السكينة'), findsOneWidget);
        expect(find.text('إذاعة سورة البقرة'), findsOneWidget);
        expect(find.text('بانتظار اعتماد المصدر الموثق'), findsNothing);

        final radios = QuranAudioStation.defaultCatalog
            .where((station) => station.category == AudioStationCategory.radio)
            .toList(growable: false);
        expect(radios, hasLength(9));
        expect(radios.every((station) => station.isAudioPlayable), isTrue);
        expect(
          radios.every(
            (station) => Uri.tryParse(station.streamUrl!)?.scheme == 'https',
          ),
          isTrue,
        );

        quranCubit.close();
      },
    );

    testWidgets('6a. Radio card toggles playback inside the app', (
      tester,
    ) async {
      setTestViewport(tester, size: const Size(390, 900));

      final quranCubit = QuranCubit(
        repository: globalQuranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();

      await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
      await pumpScreen(tester);
      await tester.tap(find.text('فتح المشغّل القرآني'));
      await tester.pumpAndSettle();
      tester.widget<TabBarView>(find.byType(TabBarView)).controller!.index = 2;
      await tester.pumpAndSettle();

      final cairoCard = find.text('إذاعة القرآن الكريم من القاهرة').first;
      await tester.tap(cairoCard);
      await pumpScreen(tester);

      expect(quranCubit.state.audioStatus, QuranAudioStatus.playing);
      expect(quranCubit.state.activeStation?.id, 'radio_cairo');
      expect(audioService.lastPlayedStreamUrl, isNotNull);

      await tester.tap(cairoCard);
      await pumpScreen(tester);

      expect(quranCubit.state.audioStatus, QuranAudioStatus.idle);
      expect(quranCubit.state.activeStation, isNull);

      quranCubit.close();
    });

    testWidgets(
      '6b. Official live stream cards remain clear on compact mobile width',
      (tester) async {
        setTestViewport(tester, size: const Size(320, 900));

        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        await tester.pumpWidget(
          buildTestApp(quranCubit: quranCubit, size: const Size(320, 900)),
        );
        await pumpScreen(tester);
        await tester.tap(find.text('فتح المشغّل القرآني'));
        await pumpScreen(tester);
        await tester.tap(find.text('البث المباشر'));
        await pumpScreen(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('شاهد البث'), findsNWidgets(2));

        quranCubit.close();
      },
    );

    testWidgets(
      '7. Single audio playback authority prevents simultaneous audio sources',
      (tester) async {
        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        // 1. Play an Ayah
        await quranCubit.playAyah(1);
        expect(quranCubit.state.audioGlobalAyah, 1);
        expect(quranCubit.state.activeStation, isNull);

        // 2. Play a station (even unplayable station attempts through single authority)
        final station = QuranAudioStation.defaultCatalog.first;
        await quranCubit.playStation(station);

        // Ayah playback must be stopped when station is selected
        expect(quranCubit.state.audioGlobalAyah, isNull);
        expect(quranCubit.state.activeStation, station);

        // 3. Play Ayah again -> Station is cleared
        await quranCubit.playAyah(255);
        expect(quranCubit.state.audioGlobalAyah, 255);
        expect(quranCubit.state.activeStation, isNull);

        quranCubit.close();
      },
    );

    testWidgets(
      '8. Destination C: التحفيظ والمراجعة navigates and exposes Q11/Q13 workflows',
      (tester) async {
        setTestViewport(tester, size: const Size(800, 1800));

        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        final memCubit = QuranMemorizationCubit(
          repository: QuranMemorizationRepository(storage: storage),
        );
        await memCubit.load();

        // Create an active plan
        await memCubit.createPlan(
          title: 'حفظ سورة الكهف',
          startGlobalAyah: 2141,
          endGlobalAyah: 2250,
          dailyTarget: 5,
        );

        await tester.pumpWidget(
          buildTestApp(quranCubit: quranCubit, memCubit: memCubit),
        );
        await pumpScreen(tester);

        // Plan details stay inside the destination page to keep the hub calm.
        expect(find.text('الخطة النشطة: حفظ سورة الكهف'), findsNothing);

        // Tap 'لوحة التحفيظ'
        await tester.tap(find.text('لوحة التحفيظ'));
        await pumpScreen(tester);

        // Verify QuranMemorizationPage opened
        expect(find.byType(QuranMemorizationPage), findsOneWidget);
        expect(
          find.text('التسميع والاستحضار البصري في المصحف'),
          findsOneWidget,
        );

        memCubit.close();
        quranCubit.close();
      },
    );

    testWidgets(
      '9. Memorization destination opens its dedicated details page',
      (tester) async {
        setTestViewport(tester, size: const Size(800, 1600));

        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
        await pumpScreen(tester);

        // Secondary memorization tools live inside their destination page.
        await tester.tap(find.text('التحفيظ والمراجعة'));
        await pumpScreen(tester);

        expect(find.byType(QuranMemorizationPage), findsOneWidget);

        quranCubit.close();
      },
    );

    testWidgets(
      '10. Responsive layout: Compact 320px width renders with 0 overflow',
      (tester) async {
        setTestViewport(tester, size: const Size(320, 1600));

        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        // Test on extra narrow screen (320 width)
        await tester.pumpWidget(
          buildTestApp(quranCubit: quranCubit, size: const Size(320, 1600)),
        );
        await pumpScreen(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('المصحف الشريف'), findsOneWidget);
        expect(find.text('المشغّل القرآني'), findsOneWidget);
        expect(find.text('التحفيظ والمراجعة'), findsOneWidget);

        quranCubit.close();
      },
    );

    testWidgets('11. Theme compatibility: Dark theme renders cleanly', (
      tester,
    ) async {
      setTestViewport(tester, size: const Size(390, 1200));

      final quranCubit = QuranCubit(
        repository: globalQuranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();

      await tester.pumpWidget(
        buildTestApp(quranCubit: quranCubit, themeMode: ThemeMode.dark),
      );
      await pumpScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('المصحف الشريف'), findsOneWidget);
      expect(find.text('المشغّل القرآني'), findsOneWidget);
      expect(find.text('التحفيظ والمراجعة'), findsOneWidget);

      quranCubit.close();
    });

    testWidgets('12. Quran index is reached through the Mushaf destination', (
      tester,
    ) async {
      setTestViewport(tester, size: const Size(390, 1200));

      final quranCubit = QuranCubit(
        repository: globalQuranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();

      await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
      await pumpScreen(tester);

      await tester.tap(find.text('المصحف الشريف'));
      await pumpScreen(tester);

      // Verify on QuranIndexPage
      expect(find.byType(QuranIndexPage), findsOneWidget);
      expect(find.textContaining('فَاتِحَة'), findsOneWidget);
      expect(find.textContaining('بَقَرَة'), findsOneWidget);

      quranCubit.close();
    });

    testWidgets(
      '13. Audio station playback integrity: switching, error handling, and Last Read isolation',
      (tester) async {
        // Set initial Last Read
        await storage.writeMap('quran', {
          'currentPage': 100,
          'lastRead': {'s': 4, 'a': 140, 'g': 633},
        });

        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        // Verify initial state
        expect(quranCubit.state.currentPage, 100);
        expect(quranCubit.state.lastRead?.global, 633);

        // 1. Play an Ayah (Global 50)
        await quranCubit.playAyah(50);
        expect(quranCubit.state.audioGlobalAyah, 50);
        expect(quranCubit.state.activeStation, isNull);
        final lastReadBeforeStation = quranCubit.state.lastRead?.global;
        expect(lastReadBeforeStation, 50);

        // 2. Play verified station (Sharjah)
        final sharjahStation = QuranAudioStation.defaultCatalog.firstWhere(
          (s) => s.id == 'radio_sharjah',
        );
        expect(sharjahStation.isPlayable, isTrue);
        await quranCubit.playStation(sharjahStation);

        // Ayah audio stopped, active station set, audioService received URL
        expect(quranCubit.state.audioGlobalAyah, isNull);
        expect(quranCubit.state.activeStation, sharjahStation);
        expect(audioService.lastPlayedStreamUrl, sharjahStation.streamUrl);

        // CRITICAL: Station playback must NEVER mutate Last Read in storage or state
        final storedData = storage.readMap('quran');
        final storedLastRead = storedData['lastRead'] as Map<String, dynamic>;
        expect(storedLastRead['g'], lastReadBeforeStation);
        expect(quranCubit.state.lastRead?.global, lastReadBeforeStation);

        // 3. Switch to another verified station (Cairo)
        final cairoStation = QuranAudioStation.defaultCatalog.firstWhere(
          (s) => s.id == 'radio_cairo',
        );
        expect(cairoStation.isPlayable, isTrue);
        await quranCubit.playStation(cairoStation);

        expect(quranCubit.state.audioStatus, QuranAudioStatus.playing);
        expect(quranCubit.state.activeStation, cairoStation);
        expect(audioService.lastPlayedStreamUrl, cairoStation.streamUrl);
        expect(quranCubit.state.error, isNull);

        // 4. Switch back to Ayah recitation -> station is cleared and stream stopped
        await quranCubit.playAyah(1);
        expect(quranCubit.state.audioGlobalAyah, 1);
        expect(quranCubit.state.activeStation, isNull);

        // 5. Clean stop
        await quranCubit.stopAudio();
        expect(quranCubit.state.audioStatus, QuranAudioStatus.idle);
        expect(quranCubit.state.audioGlobalAyah, isNull);
        expect(quranCubit.state.activeStation, isNull);

        // Last read remains intact at Ayah 1
        expect(quranCubit.state.lastRead?.global, 1);

        quranCubit.close();
      },
    );

    testWidgets(
      '14. Tapping المصحف الشريف card header/body navigates to QuranIndexPage',
      (tester) async {
        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
        await pumpScreen(tester);

        // Tap on the text 'المصحف الشريف'
        await tester.tap(find.text('المصحف الشريف'));
        await pumpScreen(tester);

        // Verify QuranIndexPage is pushed
        expect(find.byType(QuranIndexPage), findsOneWidget);
        expect(find.text('فهرس القرآن الكريم'), findsOneWidget);

        quranCubit.close();
      },
    );

    testWidgets('15. Juz details stay inside the Mushaf destination page', (
      tester,
    ) async {
      setTestViewport(tester, size: const Size(600, 1600));

      final quranCubit = QuranCubit(
        repository: globalQuranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();

      await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
      await pumpScreen(tester);

      await tester.tap(find.text('المصحف الشريف'));
      await pumpScreen(tester);

      // Verify on QuranIndexPage
      expect(find.byType(QuranIndexPage), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'الأجزاء'));
      await pumpScreen(tester);

      // Juz 1 and Juz 2 should be displayed
      expect(find.text('الجزء 1'), findsOneWidget);

      quranCubit.close();
    });

    testWidgets('16. Latest bookmark entry opens the saved position directly', (
      tester,
    ) async {
      final quranCubit = QuranCubit(
        repository: globalQuranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();
      await quranCubit.toggleAyahBookmark(262, label: 'آية الكرسي');

      await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
      await pumpScreen(tester);

      await tester.tap(find.text('آخر علامة'));
      await pumpScreen(tester);

      expect(find.byType(QuranReaderPage), findsOneWidget);
      expect(quranCubit.state.currentPage, 42);

      quranCubit.close();
    });

    testWidgets(
      '17. In QuranIndexPage, searching for Surahs filters list and opens reader',
      (tester) async {
        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
        await pumpScreen(tester);

        // Open index
        await tester.tap(find.text('فتح المصحف'));
        await pumpScreen(tester);

        // Enter search query
        final searchField = find.byType(TextField);
        expect(searchField, findsOneWidget);
        await tester.enterText(searchField, 'الكهف');
        await pumpScreen(tester);

        // Verify Kahf is shown, and Fatihah is filtered out
        expect(find.textContaining('الكَهۡفِ'), findsOneWidget);
        expect(find.textContaining('فَاتِحَة'), findsNothing);

        // Tap Al-Kahf
        await tester.tap(find.textContaining('الكَهۡفِ'));
        await pumpScreen(tester);

        // Verify reader opened at Surah 18 (page 293)
        expect(find.byType(QuranReaderPage), findsOneWidget);
        expect(quranCubit.state.currentPage, 293);

        quranCubit.close();
      },
    );

    testWidgets(
      '18. In QuranIndexPage, continuation banner resumes Last Read directly into reader',
      (tester) async {
        // Set persisted last read at page 107 (Surah Al-Ma'idah, Ayah 3, Global 672)
        await storage.writeMap('quran', {
          'currentPage': 107,
          'lastRead': {'s': 5, 'a': 3, 'g': 672},
        });

        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
        await pumpScreen(tester);

        // Open index
        await tester.tap(find.text('فتح المصحف'));
        await pumpScreen(tester);

        // Check continuation banner inside index
        final indexBanner = find.descendant(
          of: find.byType(QuranIndexPage),
          matching: find.text('متابعة آخر قراءة'),
        );
        expect(indexBanner, findsOneWidget);
        expect(find.textContaining('صفحة 107'), findsWidgets);

        // Tap 'استئناف' in continuation banner
        final resumeAction = find.descendant(
          of: find.byType(QuranIndexPage),
          matching: find.text('استئناف'),
        );
        await tester.tap(resumeAction);
        await pumpScreen(tester);

        // Reader is opened at page 107
        expect(find.byType(QuranReaderPage), findsOneWidget);
        expect(quranCubit.state.currentPage, 107);

        quranCubit.close();
      },
    );

    testWidgets(
      '19. Tapping header bookmark icon navigates to the latest bookmark',
      (tester) async {
        final quranCubit = QuranCubit(
          repository: globalQuranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();
        // Add multiple bookmarks to test that the LATEST one is chosen
        await quranCubit.toggleAyahBookmark(1, label: 'الفاتحة');
        await quranCubit.toggleAyahBookmark(262, label: 'آية الكرسي');

        await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
        await pumpScreen(tester);

        // Find the header bookmark icon button
        final bmHeaderBtn = find.byTooltip('آخر علامة مرجعية');
        expect(bmHeaderBtn, findsOneWidget);

        // Tap the header bookmark button
        await tester.tap(bmHeaderBtn);
        await pumpScreen(tester);

        // Verify that QuranReaderPage opened at the latest bookmark (page 42, ayah 255)
        expect(find.byType(QuranReaderPage), findsOneWidget);
        expect(quranCubit.state.currentPage, 42);
        expect(quranCubit.state.lastRead?.global, 262);

        quranCubit.close();
      },
    );

    testWidgets('20. Empty bookmark entry opens the bookmarks destination', (
      tester,
    ) async {
      final quranCubit = QuranCubit(
        repository: globalQuranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();

      await tester.pumpWidget(buildTestApp(quranCubit: quranCubit));
      await pumpScreen(tester);

      // Find the header bookmark icon button
      final bmHeaderBtn = find.byTooltip('آخر علامة مرجعية');
      expect(bmHeaderBtn, findsOneWidget);

      // Tap the header bookmark button
      await tester.tap(bmHeaderBtn);
      await pumpScreen(tester);

      expect(find.byType(QuranIndexPage), findsOneWidget);
      expect(find.widgetWithText(Tab, 'العلامات'), findsOneWidget);

      quranCubit.close();
    });
  });
}
