import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/mushaf_interaction_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_coordinate_mapper.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/ayah_action_sheet.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_interaction_layer.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

import 'quran_audio_sync_test.dart' show ControllableQuranAudioService;
import 'quran_home_hub_test.dart'
    show FakeLocationService, FakeNotificationService, InMemoryLocalStorage;

class _ReaderAudio extends ControllableQuranAudioService {
  ({int surah, int ayah, int word})? lastWord;

  Future<void> playWord({
    required int surah,
    required int ayah,
    required int word,
  }) async {
    lastWord = (surah: surah, ayah: ayah, word: word);
    emitState(PlayerState(true, ProcessingState.ready));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = QuranRepository();
  final layout = MushafLayoutRepository.instance;
  late _ReaderAudio audio;
  late QuranCubit quran;
  late SettingsCubit settings;

  setUpAll(() async {
    await repository.load();
    await layout.load();
    final cairo = FontLoader('Cairo');
    for (final weight in ['Regular', 'SemiBold', 'Bold', 'Black']) {
      cairo.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await cairo.load();
    await (FontLoader(
      'AmiriQuran',
    )..addFont(rootBundle.load('assets/fonts/AmiriQuran-Regular.ttf'))).load();
  });

  setUp(() async {
    final storage = InMemoryLocalStorage();
    audio = _ReaderAudio();
    quran = QuranCubit(
      repository: repository,
      storage: storage,
      audio: audio,
      reciter: 'ar.alafasy',
      fontSize: 32,
    );
    settings = SettingsCubit(
      storage: storage,
      locationService: FakeLocationService(),
      notifications: FakeNotificationService(),
    );
    await settings.load();
    await quran.load();
  });

  tearDown(() async {
    await quran.close();
    await settings.close();
  });

  Future<void> openReader(WidgetTester tester, {int page = 50}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await quran.openPage(page);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: quran),
          BlocProvider.value(value: settings),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const QuranReaderPage(),
                  ),
                ),
                child: const Text('افتح المصحف'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح المصحف'));
    await tester.pumpAndSettle();
  }

  Finder currentTouchLayer() => find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is MushafPage && widget.isCurrent,
    ),
    matching: find.byType(MushafInteractionLayer),
  );

  Offset positionFor(WidgetTester tester, int globalAyah) {
    final bounds = layout.getAyah(globalAyah)!;
    final layer = currentTouchLayer();
    final local = const MushafCoordinateMapper(contentPadding: EdgeInsets.zero)
        .viewBoxToLocal(
          viewBoxCoordinate: bounds.samplePoint,
          contentSize: tester.getSize(layer),
          viewBox: layout.getPageGeometry(bounds.page)!.viewBox,
        );
    return tester.getTopLeft(layer) + local;
  }

  testWidgets(
    'reader starts current page then honors a tapped ayah and continues',
    (tester) async {
      await openReader(tester);
      final first = quran.state.data!.page(50).first.global;
      await tester.tap(find.byKey(const ValueKey('reader-play-toggle')));
      await tester.pump();
      expect(audio.lastGlobalAyah, first);
      await quran.stopAudio();
      await tester.pump();
      expect(quran.state.audioStatus.name, 'idle');
      await tester.pump(const Duration(milliseconds: 400));

      final selected = first + 3;
      await tester.tapAt(positionFor(tester, selected));
      await tester.pump(const Duration(milliseconds: 350));
      final interaction = tester
          .element(currentTouchLayer())
          .read<MushafInteractionCubit>();
      expect(interaction.state.selectedAyah?.globalAyah, selected);
      expect(
        audio.playAyahCalls,
        1,
        reason: 'Tap highlights without starting audio',
      );
      await tester.tap(find.byKey(const ValueKey('reader-play-toggle')));
      await tester.pump();
      expect(audio.lastGlobalAyah, selected);
      expect(quran.isContinuous, isTrue);
      audio.emitState(PlayerState(true, ProcessingState.completed));
      await tester.pump();
      expect(audio.lastGlobalAyah, selected + 1);
      // Pausing after advancing keeps the current Ayah instead of rewinding.
      await tester.tap(find.byKey(const ValueKey('reader-play-toggle')));
      await tester.pump();
      expect(audio.paused, isTrue);
      expect(audio.lastGlobalAyah, selected + 1);
      // Tapping the same highlighted Ayah again is a new explicit start.
      await tester.tapAt(positionFor(tester, selected));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(const ValueKey('reader-play-toggle')));
      await tester.pump();
      expect(audio.lastGlobalAyah, selected);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page navigation clears selected start and uses new page beginning',
    (tester) async {
      await openReader(tester);
      final selected = quran.state.data!.page(50).first.global + 2;
      await tester.tapAt(positionFor(tester, selected));
      await tester.pump(const Duration(milliseconds: 350));
      expect(quran.state.readerSelectedAyah, selected);
      await tester.tap(find.byTooltip('الصفحة التالية'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reader-play-toggle')));
      await tester.pump();
      expect(audio.lastGlobalAyah, quran.state.data!.page(51).first.global);
    },
  );

  testWidgets(
    'long press plays only ayah and educational word selection ignores pause marks',
    (tester) async {
      await openReader(tester, page: 2);
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      await tester.longPressAt(
        positionFor(tester, 9),
      ); // 2:2 has two isolated pause signs.
      await tester.pumpAndSettle();
      expect(find.byType(AyahActionSheet), findsOneWidget);
      await tester.ensureVisible(find.text('تشغيل هذه الآية فقط'));
      await tester.tap(find.text('تشغيل هذه الآية فقط'));
      await tester.pump();
      expect(audio.lastGlobalAyah, 9);
      expect(quran.isContinuous, isFalse);
      audio.emitState(PlayerState(true, ProcessingState.completed));
      await tester.pump();
      expect(audio.playAyahCalls, 1);

      await tester.ensureVisible(find.text('استماع إلى كلمة'));
      await tester.tap(find.text('استماع إلى كلمة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ChoiceChip), findsNWidgets(7));
      final fifth = find.byKey(const ValueKey('ayah-word-5'));
      expect(
        find.descendant(of: fifth, matching: find.textContaining('فِيهِ')),
        findsOneWidget,
      );
      await tester.ensureVisible(fifth);
      await tester.tap(fifth);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('ayah-play-word')));
      await tester.tap(find.byKey(const ValueKey('ayah-play-word')));
      await tester.pump();
      expect(audio.lastWord, (surah: 2, ayah: 2, word: 5));
      expect(quran.state.audioWordIndex, 5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'leaving reader stops its audio before exit animation completes',
    (tester) async {
      await openReader(tester);
      await tester.tap(find.byKey(const ValueKey('reader-play-toggle')));
      await tester.pump();
      expect(audio.isPlaying, isTrue);
      await tester.tap(find.byTooltip('العودة إلى الفهرس'));
      await tester.pump();
      expect(audio.stopped, isTrue);
      expect(audio.isPlaying, isFalse);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('leaving reader preserves playback owned by audio player', (
    tester,
  ) async {
    await openReader(tester);
    await quran.playAyah(
      1,
      autoScroll: false,
      origin: QuranPlaybackOrigin.audioPlayer,
    );
    await tester.pump();
    await tester.tap(find.byTooltip('العودة إلى الفهرس'));
    await tester.pumpAndSettle();
    expect(audio.stopped, isFalse);
    expect(audio.isPlaying, isTrue);
  });
}
