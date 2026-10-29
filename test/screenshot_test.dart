import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';
import 'package:mishkat_app/features/adhkar/presentation/pages/adhkar_page.dart';
import 'package:mishkat_app/features/home/presentation/cubit/home_cubit.dart';
import 'package:mishkat_app/features/home/presentation/pages/home_page.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';
import 'package:mishkat_app/features/khatma/presentation/pages/khatma_page.dart';
import 'package:mishkat_app/features/library/data/repositories/library_repository.dart';
import 'package:mishkat_app/features/library/presentation/cubit/library_cubit.dart';
import 'package:mishkat_app/features/library/presentation/pages/library_page.dart';
import 'package:mishkat_app/features/qibla/presentation/cubit/qibla_cubit.dart';
import 'package:mishkat_app/features/qibla/presentation/pages/qibla_page.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_state.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_audio_player_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_index_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_memorization_page.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_oral_recitation_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_search_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/oral_recitation_info_sheet.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/shell/presentation/pages/app_shell.dart';
import 'package:mishkat_app/features/settings/presentation/pages/settings_page.dart';
import 'package:mishkat_app/features/shell/presentation/cubit/shell_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/pages/tasbih_page.dart';

class FakeLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> _data = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) {
    final value = _data[key];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
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
    _data[key] = value;
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _data[key] = value;
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

class FakeQuranAudioService implements QuranAudioService {
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

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
  Duration? get duration => null;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  bool get isPlaying => false;

  @override
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

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

Future<void> _loadFonts() async {
  final fontFile = File(
    '/Users/muhammedbashuaib/Developer/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (fontFile.existsSync()) {
    final fontData = fontFile.readAsBytesSync();
    final fontLoader = FontLoader('MaterialIcons');
    fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
    await fontLoader.load();
  }

  final cairoFiles = [
    'assets/fonts/Cairo-Regular.ttf',
    'assets/fonts/Cairo-SemiBold.ttf',
    'assets/fonts/Cairo-Bold.ttf',
    'assets/fonts/Cairo-Light.ttf',
    'assets/fonts/Cairo-Black.ttf',
  ];
  final cairoLoader = FontLoader('Cairo');
  for (final path in cairoFiles) {
    final file = File(path);
    if (file.existsSync()) {
      cairoLoader.addFont(
        Future.value(ByteData.view(file.readAsBytesSync().buffer)),
      );
    }
  }
  await cairoLoader.load();

  final arabicFile = File('/System/Library/Fonts/SFArabic.ttf');
  if (arabicFile.existsSync()) {
    final fontData = arabicFile.readAsBytesSync();
    final fontLoader = FontLoader('SF Arabic');
    fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
    await fontLoader.load();
  }

  final arialFile = File('/System/Library/Fonts/Supplemental/Arial.ttf');
  if (arialFile.existsSync()) {
    final fontData = arialFile.readAsBytesSync();
    final fontLoader = FontLoader('Arial');
    fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
    await fontLoader.load();
  }
}

late QuranRepository globalQuranRepo;
late AdhkarRepository globalAdhkarRepo;
late LibraryRepository globalLibraryRepo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    print('setUpAll: Loading fonts and preloading repositories...');
    await _loadFonts();
    globalQuranRepo = QuranRepository();
    globalAdhkarRepo = AdhkarRepository();
    globalLibraryRepo = LibraryRepository();

    await globalQuranRepo.load();
    await globalAdhkarRepo.load();
    await globalLibraryRepo.loadCatalog();
    print('setUpAll: All assets preloaded.');

    final outDir = Directory('screenshots');
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
  });

  testWidgets('Generate all 11 screenshots', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Screenshot tests run without device sensors or native audio players.
    messenger.setMockMethodCallHandler(
      const MethodChannel('hemanthraj/flutter_compass'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['wifi'],
    );

    print('Starting screenshot generation...');
    final storage = FakeLocalStorageService();
    await storage.init();

    const initialSettings = AppSettings(
      city: 'المكلا، حضرموت',
      latitude: 14.5425,
      longitude: 49.1242,
      onboardingSeen: true,
      method: 'MWL',
      notificationsEnabled: false,
      keepAwake: false,
    );

    final settingsCubit = SettingsCubit(
      storage: storage,
      locationService: FakeLocationService(),
      notifications: FakeNotificationService(),
    );
    await storage.writeMap('settings', initialSettings.toJson());
    await settingsCubit.load();

    final khatmaCubit = KhatmaCubit(storage);
    await khatmaCubit.create(
      name: 'ختمة النور',
      durationDays: 30,
      startPage: 1,
    );

    final quranCubit = QuranCubit(
      repository: globalQuranRepo,
      storage: storage,
      audio: FakeQuranAudioService(),
      reciter: 'alafasy',
      fontSize: 22.0,
    );
    await quranCubit.load();

    final adhkarCubit = AdhkarCubit(globalAdhkarRepo, storage);
    await adhkarCubit.load();

    final libraryCubit = LibraryCubit(globalLibraryRepo, storage);
    await libraryCubit.load();

    final tasbihCubit = TasbihCubit(storage);

    final qiblaCubit = QiblaCubit();
    qiblaCubit.setLocation(14.5425, 49.1242);

    final memorizationCubit = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: storage),
    );
    await memorizationCubit.load();

    print('All cubits initialized successfully!');

    final shellCubit = ShellCubit();

    Widget buildTestApp({
      required Widget screen,
      bool isDark = false,
      Size size = const Size(390, 844),
    }) {
      final baseTheme = isDark ? AppTheme.dark(1.0) : AppTheme.light(1.0);
      return RepositoryProvider<QuranRepository>.value(
        value: globalQuranRepo,
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: settingsCubit),
            BlocProvider.value(value: shellCubit),
            BlocProvider(
              create: (_) => HomeCubit(settingsCubit.state.settings),
            ),
            BlocProvider.value(value: quranCubit),
            BlocProvider.value(value: memorizationCubit),
            BlocProvider.value(value: adhkarCubit),
            BlocProvider.value(value: qiblaCubit),
            BlocProvider.value(value: tasbihCubit),
            BlocProvider.value(value: khatmaCubit),
            BlocProvider.value(value: libraryCubit),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: baseTheme,
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  padding: const EdgeInsets.only(top: 47, bottom: 34),
                  devicePixelRatio: 2.0,
                ),
                child: child!,
              ),
            ),
            home: screen is AppShell ? screen : Scaffold(body: screen),
          ),
        ),
      );
    }

    Future<void> captureScreen({
      required String filename,
      required Widget screen,
      bool isDark = false,
      Size size = const Size(390, 844),
    }) async {
      print('Capturing $filename...');
      final key = GlobalKey();
      tester.view.physicalSize = Size(size.width * 2, size.height * 2);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: buildTestApp(screen: screen, isDark: isDark, size: size),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final pngBytes = byteData!.buffer.asUint8List();

        final file = File('screenshots/$filename');
        file.writeAsBytesSync(pngBytes);
        print('Saved $filename (${pngBytes.length} bytes)');
      });

      final exception = tester.takeException();
      if (exception != null) {
        print('OVERFLOW IN SCREEN: $filename -> $exception');
      }
    }

    // 1. Home — Light (Normal phone 390x844)
    await captureScreen(
      filename: '01_home_light.png',
      screen: const HomePage(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 1b. App Shell with Premium Bottom Navigation (390x844)
    await captureScreen(
      filename: '01b_shell_with_bottom_nav.png',
      screen: const AppShell(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 2. Home — Dark (Normal phone 390x844)
    await captureScreen(
      filename: '02_home_dark.png',
      screen: const HomePage(),
      isDark: true,
      size: const Size(390, 844),
    );

    // 3. Home — Small phone (Compact phone 320x640)
    await captureScreen(
      filename: '03_home_small.png',
      screen: const HomePage(),
      isDark: false,
      size: const Size(320, 640),
    );

    // 4. Home — Large phone (Large phone 430x932)
    await captureScreen(
      filename: '04_home_large.png',
      screen: const HomePage(),
      isDark: false,
      size: const Size(430, 932),
    );

    // 5. Quran Hub — Light (390x844)
    await captureScreen(
      filename: '05_quran.png',
      screen: const QuranPage(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 5b. Quran Hub Full View (390x1080)
    await captureScreen(
      filename: '05b_quran_hub_full.png',
      screen: const QuranPage(),
      isDark: false,
      size: const Size(390, 1080),
    );

    // 5c. Quran Hub — Dark (390x844)
    await captureScreen(
      filename: '05_quran_hub_dark.png',
      screen: const QuranPage(),
      isDark: true,
      size: const Size(390, 844),
    );

    // 5d. Quran Hub — Narrow screen (320x640)
    await captureScreen(
      filename: '05_quran_hub_narrow_320.png',
      screen: const QuranPage(),
      isDark: false,
      size: const Size(320, 640),
    );

    // 5e. Quran Index — Surahs tab (390x844)
    await captureScreen(
      filename: '05c_quran_index_surahs.png',
      screen: const QuranIndexPage(initialMode: QuranIndexMode.surahs),
      isDark: false,
      size: const Size(390, 844),
    );

    // 5f. Quran Index — Juz tab (390x844)
    await captureScreen(
      filename: '05d_quran_index_juz.png',
      screen: const QuranIndexPage(initialMode: QuranIndexMode.juz),
      isDark: false,
      size: const Size(390, 844),
    );

    // 5g. Quran Index — Bookmarks tab (390x844)
    await captureScreen(
      filename: '05e_quran_index_bookmarks.png',
      screen: const QuranIndexPage(initialMode: QuranIndexMode.bookmarks),
      isDark: false,
      size: const Size(390, 844),
    );

    // 5h. Quran Search Page (390x844)
    await captureScreen(
      filename: '05f_quran_search_page.png',
      screen: const QuranSearchPage(initialQuery: 'الكهف'),
      isDark: false,
      size: const Size(390, 844),
    );

    // 5i. Quran Audio Player Page (390x844)
    await captureScreen(
      filename: '05g_quran_audio_player.png',
      screen: const QuranAudioPlayerPage(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 5j. Quran Memorization Page (390x844)
    await captureScreen(
      filename: '05h_quran_memorization.png',
      screen: const QuranMemorizationPage(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 6. Adhkar (390x844)
    await captureScreen(
      filename: '06_adhkar.png',
      screen: const AdhkarPage(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 7. Qibla (390x844)
    await captureScreen(
      filename: '07_qibla.png',
      screen: const QiblaPage(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 7b. App Shell with Active Qibla Tab (390x844)
    shellCubit.select(2);
    await captureScreen(
      filename: '07b_shell_qibla_active.png',
      screen: const AppShell(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 7c. Qibla — Narrow screen (320x640)
    await captureScreen(
      filename: '07c_qibla_narrow_320.png',
      screen: const QiblaPage(),
      isDark: false,
      size: const Size(320, 640),
    );

    // 7d. Qibla — Dark mode (390x844)
    await captureScreen(
      filename: '07d_qibla_dark.png',
      screen: const QiblaPage(),
      isDark: true,
      size: const Size(390, 844),
    );

    // 7e. Qibla — Aligned celebration (facing Kaaba)
    final qiblaBearing = qiblaCubit.state.bearing ?? 309.0;
    qiblaCubit.setHeadingForTesting(qiblaBearing, accuracy: 5.0);
    await captureScreen(
      filename: '07e_qibla_aligned.png',
      screen: const QiblaPage(),
      isDark: false,
      size: const Size(390, 844),
    );
    // Reset heading for other screens
    qiblaCubit.setHeadingForTesting(null);
    shellCubit.select(0);

    // 8. Tasbih (390x844)
    await captureScreen(
      filename: '08_tasbih.png',
      screen: TasbihPage(onCompletionSound: () {}),
      isDark: false,
      size: const Size(390, 844),
    );

    // 9. Khatma (390x844)
    await captureScreen(
      filename: '09_khatma.png',
      screen: const KhatmaPage(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 10. Library (390x844)
    await captureScreen(
      filename: '10_library.png',
      screen: const LibraryPage(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 11. Settings (390x844)
    await captureScreen(
      filename: '11_settings.png',
      screen: const SettingsPage(),
      isDark: false,
      size: const Size(390, 844),
    );

    // 12. Bottom Sheet / Dialog Modal (390x844)
    await captureScreen(
      filename: '12_bottom_sheet_modal.png',
      screen: const Scaffold(
        backgroundColor: Colors.black54,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: OralRecitationInfoSheet(),
          ),
        ),
      ),
      isDark: false,
      size: const Size(390, 844),
    );

    // 13. Oral Recitation Active Listening Session (390x844)
    final mockSpeechForScreenshots = MockSpeechRecognitionService();
    final activeOralCubit = QuranOralRecitationCubit(
      speechService: mockSpeechForScreenshots,
      quranRepository: globalQuranRepo,
      memorizationCubit: memorizationCubit,
    );
    await activeOralCubit.prepareSession(
      surahNumber: 1,
      startGlobalAyah: 1,
      endGlobalAyah: 4,
    );
    await activeOralCubit.startRecitation();
    mockSpeechForScreenshots.emitTranscript(
      'بسم الله الرحمن الرحيم الحمد لله رب العالمين',
    );
    await tester.pump(const Duration(milliseconds: 50));

    await captureScreen(
      filename: '13_oral_recitation_session.png',
      screen: QuranOralRecitationPage(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 4,
        cubit: activeOralCubit,
      ),
      isDark: false,
      size: const Size(390, 844),
    );

    // 14. Oral Recitation Completed Session Summary (390x844)
    await activeOralCubit.finishSession();
    await tester.pump(const Duration(milliseconds: 50));

    await captureScreen(
      filename: '14_oral_recitation_completed.png',
      screen: QuranOralRecitationPage(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 4,
        cubit: activeOralCubit,
      ),
      isDark: false,
      size: const Size(390, 844),
    );

    await activeOralCubit.close();

    // 15. Oral Recitation Permission Gate (Initial Prompt)
    final gateSpeech = MockSpeechRecognitionService(initialPermission: false);
    final gateCubit = QuranOralRecitationCubit(
      speechService: gateSpeech,
      quranRepository: globalQuranRepo,
      memorizationCubit: memorizationCubit,
    );
    await gateCubit.prepareSession(
      surahNumber: 1,
      startGlobalAyah: 1,
      endGlobalAyah: 4,
    );
    await tester.pump(const Duration(milliseconds: 50));

    await captureScreen(
      filename: '15_oral_recitation_permission_gate.png',
      screen: QuranOralRecitationPage(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 4,
        cubit: gateCubit,
      ),
      isDark: false,
      size: const Size(390, 844),
    );

    // 16. Oral Recitation Permission Permanently Denied
    await gateCubit.openAppSettings();
    await tester.pump(const Duration(milliseconds: 50));

    await captureScreen(
      filename: '16_oral_recitation_permission_denied.png',
      screen: QuranOralRecitationPage(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 4,
        cubit: gateCubit,
      ),
      isDark: false,
      size: const Size(390, 844),
    );

    await gateCubit.close();

    // Tear down clean
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    print('All screenshots captured and saved successfully.');
  });
}
