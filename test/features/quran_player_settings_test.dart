import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/quran_audio_station.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_state.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_audio_player_page.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/quran_mini_player.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/quran_player_settings_sheet.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

class _SilentAudio implements QuranAudioService {
  @override
  Stream<PlayerState> get playerState => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Duration get currentPosition => Duration.zero;
  @override
  Duration? get duration => const Duration(minutes: 5);
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryStorage extends LocalStorageService {
  final _values = <String, Map<String, dynamic>>{};

  @override
  Map<String, dynamic> readMap(String key) => _values[key] ?? {};

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _values[key] = Map.of(value);
  }
}

class _PlayerCubit extends QuranCubit {
  _PlayerCubit()
    : super(
        repository: QuranRepository(),
        storage: _MemoryStorage(),
        audio: _SilentAudio(),
        reciter: 'ar.alafasy',
        fontSize: 32,
      );

  int? requestedSurah;
  int ayahRequests = 0;
  int wordToggleCalls = 0;

  void showState(QuranState next) => emit(next);

  @override
  Future<void> playSurah(int surah) async {
    requestedSurah = surah;
    emit(
      state.copyWith(audioSurah: surah, audioStatus: QuranAudioStatus.playing),
    );
  }

  @override
  Future<void> playAyah(
    int globalAyah, {
    bool continuous = true,
    bool? autoScroll,
    QuranPlaybackOrigin origin = QuranPlaybackOrigin.general,
  }) async {
    ayahRequests++;
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async =>
      emit(state.copyWith(playbackSpeed: speed));

  @override
  Future<void> toggleWordAudio() async {
    wordToggleCalls++;
    emit(state.copyWith(audioStatus: QuranAudioStatus.paused));
  }
}

final _data = QuranData(
  chapters: const [
    QuranChapter(
      number: 1,
      name: 'الفاتحة',
      englishName: 'Al-Fatihah',
      revelationType: 'مكية',
      page: 1,
      ayahs: ['بسم الله'],
      globalStart: 1,
    ),
  ],
  juz: const [],
  pages: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_QURAN_PLAYER');
  late _PlayerCubit cubit;
  late SettingsCubit settings;

  setUpAll(() async {
    final cairo = FontLoader('Cairo');
    for (final weight in ['Regular', 'SemiBold', 'Bold', 'Black']) {
      cairo.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await cairo.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() {
    cubit = _PlayerCubit();
    settings = SettingsCubit(
      storage: _MemoryStorage(),
      locationService: LocationService(),
      notifications: LocalNotificationService(),
    );
    cubit.showState(
      QuranState(
        status: QuranStatus.ready,
        data: _data,
        audioStatus: QuranAudioStatus.playing,
        audioSurah: 1,
      ),
    );
  });

  tearDown(() async {
    await cubit.close();
    await settings.close();
  });

  Widget host(Widget child, {bool dark = false}) => MultiBlocProvider(
    providers: [
      BlocProvider<QuranCubit>.value(value: cubit),
      BlocProvider<SettingsCubit>.value(value: settings),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    ),
  );

  Future<void> saveCapture(
    WidgetTester tester,
    GlobalKey key,
    String filename,
  ) async {
    if (!capture) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('screenshots/quran_player');
      await directory.create(recursive: true);
      await File('${directory.path}/$filename.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final scenario in [
    (size: const Size(390, 844), dark: false),
    (size: const Size(320, 700), dark: false),
    (size: const Size(640, 320), dark: false),
    (size: const Size(390, 844), dark: true),
    (size: const Size(320, 700), dark: true),
  ]) {
    final size = scenario.size;
    testWidgets(
      'player settings scroll without overflow at ${size.width}x${size.height} (${scenario.dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: host(
              const Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  QuranMiniPlayer(
                    playbackOrigin: QuranPlaybackOrigin.audioPlayer,
                  ),
                ],
              ),
              dark: scenario.dark,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final suffix =
            '${size.width.toInt()}x${size.height.toInt()}'
            '${scenario.dark ? '_dark' : ''}';
        await saveCapture(tester, boundary, 'mini_$suffix');
        await tester.tap(find.byKey(const Key('quran-player-settings')));
        await tester.pumpAndSettle();
        await saveCapture(tester, boundary, 'settings_$suffix');
        await tester.scrollUntilVisible(
          find.byKey(const Key('sleep-timer-10')),
          120,
          scrollable: find.descendant(
            of: find.byType(QuranPlayerSettingsSheet),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.byKey(const Key('sleep-timer-10')));
        await tester.pump();
        await saveCapture(tester, boundary, 'timer_$suffix');
        expect(cubit.state.sleepTimerRemaining, const Duration(minutes: 10));
        expect(find.text('إعدادات المشغّل').hitTestable(), findsOneWidget);
        expect(find.byTooltip('إغلاق الإعدادات').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        cubit.setSleepTimer(null);
      },
    );
  }

  testWidgets(
    'custom timer stays usable with keyboard on a narrow dark screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: host(
            const Align(
              alignment: Alignment.bottomCenter,
              child: QuranMiniPlayer(
                playbackOrigin: QuranPlaybackOrigin.audioPlayer,
              ),
            ),
            dark: true,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('quran-player-settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('مدة مخصصة'));
      await tester.tap(find.text('مدة مخصصة'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('sleep-timer-custom-minutes'));
      await tester.ensureVisible(input);
      await tester.enterText(input, '١٧');
      await tester.ensureVisible(find.text('بدء المؤقت'));
      await tester.pumpAndSettle();
      await saveCapture(tester, boundary, 'custom_keyboard_320x700_dark');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('بدء المؤقت'));
      await tester.pumpAndSettle();
      expect(cubit.state.sleepTimerRemaining, const Duration(minutes: 17));
      expect(tester.takeException(), isNull);
      cubit.setSleepTimer(null);
    },
  );

  testWidgets(
    'word mini controls retain word playback rather than starting the page',
    (tester) async {
      cubit.showState(
        cubit.state.copyWith(
          audioSurah: null,
          audioGlobalAyah: 1,
          audioWordIndex: 2,
        ),
      );
      await tester.pumpWidget(
        host(const QuranMiniPlayer(playbackOrigin: QuranPlaybackOrigin.mushaf)),
      );
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(cubit.wordToggleCalls, 1);
      expect(cubit.ayahRequests, 0);
      expect(find.text('نطق الكلمات التعليمي · Quran.com'), findsOneWidget);
      cubit.showState(
        cubit.state.copyWith(audioStatus: QuranAudioStatus.failure),
      );
      await tester.pump();
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pump();
      expect(cubit.wordToggleCalls, 2);
      expect(cubit.ayahRequests, 0);
    },
  );

  testWidgets(
    'continuous surah mini player opens settings on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          const Align(
            alignment: Alignment.bottomCenter,
            child: QuranMiniPlayer(
              playbackOrigin: QuranPlaybackOrigin.audioPlayer,
            ),
          ),
        ),
      );
      expect(find.text('سورة الفاتحة · تلاوة متصلة'), findsOneWidget);
      expect(find.byTooltip('السورة التالية'), findsOneWidget);
      expect(find.byTooltip('الآية التالية'), findsNothing);
      await tester.tap(find.byKey(const Key('quran-player-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('listening-mode-repeat')));
      await tester.pump();
      expect(cubit.state.listeningMode, QuranListeningMode.repeat);
      await tester.scrollUntilVisible(
        find.byKey(const Key('sleep-timer-10')),
        180,
        scrollable: find.descendant(
          of: find.byType(QuranPlayerSettingsSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const Key('sleep-timer-10')));
      await tester.pump();
      expect(cubit.state.sleepTimerRemaining, const Duration(minutes: 10));
      expect(find.text('متبقٍ 10:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      cubit.setSleepTimer(null);
    },
  );

  testWidgets('radio settings offer timer without surah or speed controls', (
    tester,
  ) async {
    cubit.showState(
      cubit.state.copyWith(
        audioSurah: null,
        activeStation: QuranAudioStation.defaultCatalog.firstWhere(
          (station) => station.isAudioPlayable,
        ),
      ),
    );
    await tester.pumpWidget(host(QuranPlayerSettingsSheet(cubit: cubit)));
    expect(find.text('عند انتهاء السورة'), findsNothing);
    expect(find.text('سرعة التلاوة'), findsNothing);
    await tester.tap(find.byKey(const Key('sleep-timer-10')));
    await tester.pump();
    expect(find.byKey(const Key('sleep-timer-countdown')), findsOneWidget);
    await tester.tap(find.text('إلغاء المؤقت'));
    await tester.pump();
    expect(cubit.state.sleepTimerRemaining, isNull);
  });

  testWidgets('custom sleep duration accepts Arabic digits and rejects zero', (
    tester,
  ) async {
    cubit.showState(
      cubit.state.copyWith(
        audioSurah: null,
        activeStation: QuranAudioStation.defaultCatalog.firstWhere(
          (station) => station.isAudioPlayable,
        ),
      ),
    );
    await tester.pumpWidget(host(QuranPlayerSettingsSheet(cubit: cubit)));
    await tester.tap(find.text('مدة مخصصة'));
    await tester.pump();
    final input = find.byKey(const Key('sleep-timer-custom-minutes'));
    await tester.enterText(input, '٠');
    await tester.ensureVisible(find.text('بدء المؤقت'));
    await tester.tap(find.text('بدء المؤقت'));
    await tester.pump();
    expect(find.text('أدخل مدة من دقيقة إلى ٧٢٠ دقيقة'), findsOneWidget);
    await tester.enterText(input, '١٧');
    await tester.tap(find.text('بدء المؤقت'));
    await tester.pump();
    expect(cubit.state.sleepTimerRemaining, const Duration(minutes: 17));
    expect(find.text('متبقٍ 17:00'), findsOneWidget);
    cubit.setSleepTimer(null);
  });

  testWidgets(
    'surah picker requests one full recording without changing reader position',
    (tester) async {
      cubit.showState(
        cubit.state.copyWith(
          audioStatus: QuranAudioStatus.idle,
          audioSurah: null,
          currentPage: 35,
        ),
      );
      await tester.pumpWidget(host(const QuranAudioPlayerPage()));
      await tester.tap(find.text('اختيار سورة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('سورة الفاتحة'));
      await tester.pumpAndSettle();
      expect(cubit.requestedSurah, 1);
      expect(cubit.ayahRequests, 0);
      expect(cubit.state.currentPage, 35);
      expect(tester.takeException(), isNull);
    },
  );
}
