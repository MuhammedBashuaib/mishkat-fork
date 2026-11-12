import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mishkat_app/core/theme/app_colors.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/mushaf_interaction_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_coordinate_mapper.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/ayah_action_sheet.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_interaction_layer.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_state.dart';

import 'quran_home_hub_test.dart'
    show
        FakeLocationService,
        FakeNotificationService,
        InMemoryLocalStorage,
        TestQuranAudioService;

// Add --dart-define=CAPTURE_MUSHAF_READER=true to inspect the real SVG artwork.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const captureEnabled = bool.fromEnvironment('CAPTURE_MUSHAF_READER');
  const captureDirectory = String.fromEnvironment(
    'CAPTURE_MUSHAF_READER_DIRECTORY',
    defaultValue: 'screenshots',
  );
  final repository = QuranRepository();
  final layoutRepository = MushafLayoutRepository.instance;
  late InMemoryLocalStorage storage;
  late TestQuranAudioService audio;
  late SettingsCubit settings;
  late QuranCubit quran;
  final windowCalls = <MethodCall>[];
  const windowChannel = MethodChannel('com.dakomn.mishkatapp/reader_window');

  setUpAll(() async {
    await repository.load();
    await layoutRepository.load();
    final cairo = FontLoader('Cairo');
    for (final weight in ['Regular', 'SemiBold', 'Bold', 'Black']) {
      cairo.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await cairo.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    if (captureEnabled) {
      await Directory(captureDirectory).create(recursive: true);
    }
  });

  setUp(() async {
    windowCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
          windowCalls.add(call);
          return null;
        });
    storage = InMemoryLocalStorage();
    audio = TestQuranAudioService();
    settings = SettingsCubit(
      storage: storage,
      locationService: FakeLocationService(),
      notifications: FakeNotificationService(),
    );
    await settings.load();
    quran = QuranCubit(
      repository: repository,
      storage: storage,
      audio: audio,
      reciter: 'ar.alafasy',
      fontSize: 32,
    );
    await quran.load();
  });

  tearDown(() async {
    await quran.close();
    await settings.close();
    await audio.dispose();
  });

  Future<GlobalKey> openReader(
    WidgetTester tester, {
    int page = 562,
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await settings.setTheme(
      dark ? AppThemePreference.dark : AppThemePreference.light,
    );
    await quran.openPage(page);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: quran),
          BlocProvider.value(value: settings),
        ],
        child: RepaintBoundary(
          key: boundaryKey,
          child: BlocBuilder<SettingsCubit, SettingsState>(
            builder: (context, state) => MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: AppTheme.light(state.settings.uiFontScale),
              darkTheme: AppTheme.dark(state.settings.uiFontScale),
              themeMode: state.settings.themeMode,
              builder: (context, child) {
                final media = MediaQuery.of(context);
                final landscape = media.size.width > media.size.height;
                return MediaQuery(
                  data: media.copyWith(
                    padding: landscape
                        ? const EdgeInsets.fromLTRB(44, 0, 20, 18)
                        : const EdgeInsets.only(top: 44, bottom: 24),
                  ),
                  child: child!,
                );
              },
              home: const QuranReaderPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return boundaryKey;
  }

  Finder currentPage() => find.byWidgetPredicate(
    (widget) => widget is MushafPage && widget.isCurrent,
  );

  InteractiveViewer viewer(WidgetTester tester) =>
      tester.widget<InteractiveViewer>(
        find.descendant(
          of: currentPage(),
          matching: find.byType(InteractiveViewer),
        ),
      );

  void expectReaderBrightness(WidgetTester tester, Brightness brightness) {
    expect(Theme.of(tester.element(currentPage())).brightness, brightness);
    final artwork = tester.widget<SvgPicture>(
      find.descendant(of: currentPage(), matching: find.byType(SvgPicture)),
    );
    expect(
      artwork.colorFilter,
      brightness == Brightness.dark
          ? const ColorFilter.mode(MushafThemeColors.darkInk, BlendMode.srcIn)
          : null,
    );
  }

  void expectReaderControlsBrightness(
    WidgetTester tester,
    Brightness brightness,
  ) {
    for (final control in [
      find.byType(Scaffold),
      find.byType(AppBar),
      find.byTooltip('تكبير المصحف'),
      find.byKey(const ValueKey('mushaf-theme-toggle')),
      find.byKey(const ValueKey('reader-play-toggle')),
    ]) {
      expect(Theme.of(tester.element(control)).brightness, brightness);
    }
    final colors = brightness == Brightness.dark
        ? MishkatColors.dark
        : MishkatColors.light;
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      colors.surfaceMuted,
    );
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
      colors.surface,
    );
  }

  void expectPaperThemeIcon(WidgetTester tester, IconData icon) {
    final toggle = tester.widget<IconButton>(
      find.byKey(const ValueKey('mushaf-theme-toggle')),
    );
    expect((toggle.icon as Icon).icon, icon);
  }

  Future<void> enterFullscreen(WidgetTester tester) async {
    await tester.tap(find.byTooltip('ملء الشاشة'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('حجم الصفحة'), findsNothing);
    expect(find.byTooltip('تكبير المصحف'), findsNothing);
    expect(find.byTooltip('تصغير المصحف'), findsNothing);
    expect(find.byTooltip('إنهاء ملء الشاشة').hitTestable(), findsOneWidget);
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundaryKey,
    String name,
  ) async {
    if (!captureEnabled) return;
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$captureDirectory/mushaf_fullscreen_$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  test('fullscreen preserves original glyph proportions and opening-page offsets', () {
    const mapper = MushafCoordinateMapper(contentPadding: EdgeInsets.zero);
    const size = Size(360, 760);
    for (final viewBox in [
      const Rect.fromLTWH(0, 0, 345, 550),
      const Rect.fromLTWH(-53.3109, -198.4777, 345, 550),
    ]) {
      final destination = mapper.getSvgDestinationRect(
        contentSize: size,
        viewBox: viewBox,
      );
      expect(destination.width, size.width);
      expect(
        destination.width / viewBox.width,
        closeTo(destination.height / viewBox.height, .000001),
        reason:
            'The calligraphy must have the same horizontal and vertical scale',
      );
      for (final source in [
        viewBox.topLeft,
        viewBox.center,
        viewBox.bottomRight,
      ]) {
        final local = mapper.viewBoxToLocal(
          viewBoxCoordinate: source,
          contentSize: size,
          viewBox: viewBox,
        );
        final restored = mapper.localToViewBox(
          localPosition: local,
          contentSize: size,
          viewBox: viewBox,
        )!;
        expect(restored.dx, closeTo(source.dx, .001));
        expect(restored.dy, closeTo(source.dy, .001));
      }
    }
  });

  testWidgets(
    'Mushaf defaults to light and toggles independently without losing reading state',
    (tester) async {
      quran.setFontSize(48);
      await settings.setQuranFont(48);
      final boundary = await openReader(tester, dark: true);
      expectReaderBrightness(tester, Brightness.light);
      expectReaderControlsBrightness(tester, Brightness.dark);
      expectPaperThemeIcon(tester, Icons.dark_mode_rounded);
      expect(
        Theme.of(tester.element(find.byType(QuranReaderPage))).brightness,
        Brightness.dark,
      );
      expect(settings.state.settings.mushafTheme, MushafThemePreference.light);
      expect(find.byTooltip('تفعيل الوضع الداكن للمصحف'), findsOneWidget);

      final interaction = tester
          .element(currentPage())
          .read<MushafInteractionCubit>();
      final ayah = layoutRepository.getPageGeometry(562)!.ayahs.first;
      interaction.selectAyah(ayah);
      await tester.pumpAndSettle();
      final transform = viewer(tester).transformationController!;
      final matrix = transform.value.clone();
      await capture(tester, boundary, 'toolbar_light_in_dark_app');

      await tester.tap(find.byKey(const ValueKey('mushaf-theme-toggle')));
      await tester.pumpAndSettle();
      expectReaderBrightness(tester, Brightness.dark);
      expectReaderControlsBrightness(tester, Brightness.dark);
      expectPaperThemeIcon(tester, Icons.light_mode_rounded);
      expect(find.byTooltip('تفعيل الوضع الفاتح للمصحف'), findsOneWidget);
      expect(settings.state.settings.theme, AppThemePreference.dark);
      expect(settings.state.settings.mushafTheme, MushafThemePreference.dark);
      expect(storage.readMap('settings')['mushafTheme'], 'dark');
      expect(quran.state.currentPage, 562);
      expect(quran.state.fontSize, 48);
      expect(viewer(tester).transformationController, same(transform));
      expect(transform.value, matrix);
      expect(interaction.state.selectedAyah, ayah);

      await settings.setTheme(AppThemePreference.light);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(QuranReaderPage))).brightness,
        Brightness.light,
      );
      expectReaderBrightness(tester, Brightness.dark);
      expectReaderControlsBrightness(tester, Brightness.light);
      expectPaperThemeIcon(tester, Icons.light_mode_rounded);
      await capture(tester, boundary, 'toolbar_dark_in_light_app');

      await tester.tap(find.byKey(const ValueKey('mushaf-theme-toggle')));
      await tester.pumpAndSettle();
      expectReaderBrightness(tester, Brightness.light);
      expectReaderControlsBrightness(tester, Brightness.light);
      expectPaperThemeIcon(tester, Icons.dark_mode_rounded);
      expect(settings.state.settings.theme, AppThemePreference.light);
      expect(settings.state.settings.mushafTheme, MushafThemePreference.light);
      expect(quran.state.currentPage, 562);
      expect(viewer(tester).transformationController, same(transform));
      expect(transform.value, matrix);
      expect(interaction.state.selectedAyah, ayah);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reader sheets use the app theme when paper appearance differs', (
    tester,
  ) async {
    for (final appDark in [true, false]) {
      await settings.setMushafTheme(
        appDark ? MushafThemePreference.light : MushafThemePreference.dark,
      );
      await openReader(tester, dark: appDark);
      final appBrightness = appDark ? Brightness.dark : Brightness.light;
      final paperBrightness = appDark ? Brightness.light : Brightness.dark;
      expectReaderBrightness(tester, paperBrightness);
      expectReaderControlsBrightness(tester, appBrightness);

      await tester.tap(find.text('صفحة 562'));
      await tester.pumpAndSettle();
      expect(find.text('خيارات القراءة'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text('خيارات القراءة'))).brightness,
        appBrightness,
      );
      await tester.tap(find.text('تم'));
      await tester.pumpAndSettle();

      final interaction = tester
          .element(currentPage())
          .read<MushafInteractionCubit>();
      interaction.selectAyah(
        layoutRepository.getPageGeometry(562)!.ayahs.first,
      );
      interaction.setActionSheetOpen(true);
      await tester.pumpAndSettle();
      expect(find.byType(AyahActionSheet), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(AyahActionSheet))).brightness,
        appBrightness,
      );
      Navigator.of(tester.element(find.byType(AyahActionSheet))).pop();
      await tester.pumpAndSettle();
      expectReaderBrightness(tester, paperBrightness);
      expectReaderControlsBrightness(tester, appBrightness);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Mushaf appearance survives fullscreen and reopening', (
    tester,
  ) async {
    await openReader(tester);
    await tester.tap(find.byKey(const ValueKey('mushaf-theme-toggle')));
    await tester.pumpAndSettle();
    await enterFullscreen(tester);
    expectReaderBrightness(tester, Brightness.dark);
    await tester.tap(find.byTooltip('إنهاء ملء الشاشة').hitTestable());
    await tester.pumpAndSettle();
    expectReaderBrightness(tester, Brightness.dark);
    expectReaderControlsBrightness(tester, Brightness.light);
    await tester.pumpWidget(const SizedBox.shrink());

    await settings.load();
    await openReader(tester);
    expectReaderBrightness(tester, Brightness.dark);
    expectReaderControlsBrightness(tester, Brightness.light);
    expect(settings.state.settings.theme, AppThemePreference.light);
    expect(find.byTooltip('تفعيل الوضع الفاتح للمصحف'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('theme and zoom controls remain usable on a 320 pixel screen', (
    tester,
  ) async {
    final boundary = await openReader(tester, dark: true);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final toggle = find.byKey(const ValueKey('mushaf-theme-toggle'));
    final zoom = find.byTooltip('تكبير المصحف');
    final toggleRect = tester.getRect(toggle);
    final zoomRect = tester.getRect(zoom);
    expect(toggleRect.overlaps(zoomRect), isFalse);
    expect(toggleRect.center.dy, closeTo(zoomRect.center.dy, 1));
    expect(
      (Offset.zero & const Size(320, 568)).contains(toggleRect.topLeft),
      isTrue,
    );
    expect(
      (Offset.zero & const Size(320, 568)).contains(toggleRect.bottomRight),
      isTrue,
    );
    await capture(tester, boundary, 'toolbar_narrow_320_light');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expectReaderBrightness(tester, Brightness.dark);
    await tester.tap(zoom);
    await tester.pumpAndSettle();
    expect(quran.state.fontSize, greaterThan(32));
    expect(tester.takeException(), isNull);
    await capture(tester, boundary, 'toolbar_narrow_320_dark');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reader toolbar fits with the largest saved font sizes', (
    tester,
  ) async {
    await settings.setUiFontScale(1.25);
    await settings.setQuranFont(60);
    quran.setFontSize(60);
    await openReader(tester);
    for (final width in [320.0, 340.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('188%'), findsOneWidget);
      final toggle = find.byKey(const ValueKey('mushaf-theme-toggle'));
      expect(tester.getSize(toggle), const Size(48, 48));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (name, size, dark, page) in [
    ('light_390', const Size(390, 844), false, 562),
    ('dark_390', const Size(390, 844), true, 562),
    ('narrow_320', const Size(320, 568), false, 562),
    ('landscape', const Size(844, 390), false, 562),
    ('short_landscape', const Size(568, 320), false, 562),
    ('opening_page', const Size(390, 844), false, 1),
  ]) {
    testWidgets(
      'fullscreen fills screen with a quiet folio at the bottom: $name',
      (tester) async {
        await settings.setMushafTheme(
          dark ? MushafThemePreference.dark : MushafThemePreference.light,
        );
        final boundary = await openReader(tester, dark: dark, page: page);
        await enterFullscreen(tester);
        expectReaderBrightness(
          tester,
          dark ? Brightness.dark : Brightness.light,
        );
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();

        final sheet = tester.getRect(
          find.byKey(ValueKey('mushaf-paper-$page')),
        );
        final body = tester.getRect(
          find.byKey(ValueKey('mushaf-paper-body-$page')),
        );
        final number = tester.getRect(
          find.byKey(ValueKey('mushaf-page-number-$page')),
        );
        final exit = tester.getRect(
          find.byTooltip('إنهاء ملء الشاشة').hitTestable(),
        );
        final landscape = size.width > size.height;
        final safeBounds = landscape
            ? Rect.fromLTRB(44, 0, size.width - 20, size.height - 18)
            : Rect.fromLTRB(0, 44, size.width, size.height - 24);
        // The paper fills the screen; the artwork and folio respect the cutout.
        expect(sheet, Offset.zero & size);
        expect(safeBounds.inflate(.1).contains(body.topLeft), isTrue);
        expect(safeBounds.inflate(.1).contains(body.bottomRight), isTrue);
        expect(number.top, greaterThanOrEqualTo(body.bottom));
        expect(number.bottom, lessThanOrEqualTo(sheet.bottom));
        expect(number.center.dx, closeTo(safeBounds.center.dx, 1));
        expect(safeBounds.bottom - number.bottom, inInclusiveRange(6, 14));
        final folio = tester.widget<Text>(
          find.byKey(ValueKey('mushaf-page-number-$page')),
        );
        expect(folio.style!.fontSize, lessThanOrEqualTo(11));
        final artwork = tester.widget<SvgPicture>(
          find.descendant(of: currentPage(), matching: find.byType(SvgPicture)),
        );
        expect(artwork.fit, BoxFit.contain);
        final layer = find.descendant(
          of: currentPage(),
          matching: find.byType(MushafInteractionLayer),
        );
        final mapper = tester.widget<MushafInteractionLayer>(layer).mapper;
        final viewBox = layoutRepository.getPageGeometry(page)!.viewBox;
        final destination = mapper.getSvgDestinationRect(
          contentSize: tester.getSize(layer),
          viewBox: viewBox,
        );
        expect(
          destination.width / viewBox.width,
          closeTo(destination.height / viewBox.height, .000001),
          reason:
              'Text, ayah markers and touch geometry must remain undistorted',
        );
        expect(windowCalls.last.method, 'setFullscreen');
        expect(windowCalls.last.arguments, true);
        expect(exit.overlaps(body), isFalse);
        expect(exit.overlaps(number), isFalse);
        expect(
          viewer(tester).transformationController!.value.getMaxScaleOnAxis(),
          closeTo(1, .001),
        );
        expect(tester.takeException(), isNull);
        await capture(tester, boundary, name);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'fullscreen fits a zoomed page and exits with saved zoom intact',
    (tester) async {
      quran.setFontSize(48);
      await settings.setQuranFont(48);
      await openReader(tester);
      expect(
        viewer(tester).transformationController!.value.getMaxScaleOnAxis(),
        closeTo(1.5, .001),
      );
      await enterFullscreen(tester);
      expect(quran.state.fontSize, 48);
      expect(
        viewer(tester).transformationController!.value.getMaxScaleOnAxis(),
        closeTo(1, .001),
      );

      // Model the transform produced by a pinch, then use the actual reset gesture.
      viewer(tester).transformationController!.value = Matrix4.diagonal3Values(
        1.5,
        1.5,
        1,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      final center = tester.getCenter(currentPage());
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(
        viewer(tester).transformationController!.value.getMaxScaleOnAxis(),
        closeTo(1, .001),
      );
      expect(quran.state.fontSize, 48);
      expect(settings.state.settings.quranFont, 48);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(windowCalls.last.arguments, false);
      expect(find.byType(QuranReaderPage), findsOneWidget);
      expect(
        viewer(tester).transformationController!.value.getMaxScaleOnAxis(),
        closeTo(1.5, .001),
      );
      await enterFullscreen(tester);
      await tester.tap(find.byTooltip('إنهاء ملء الشاشة').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(quran.state.currentPage, 562);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'fullscreen prepares adjacent pages and reuses them during RTL swipes',
    (tester) async {
      await openReader(tester);
      final savedReadingPosition = storage.readMap('quran');
      await enterFullscreen(tester);

      Finder page(int number) =>
          find.byKey(ValueKey('mushaf-page-$number'), skipOffstage: false);
      final viewport = tester.getRect(find.byType(PageView));
      expect(
        tester
            .widgetList<MushafPage>(
              find.byType(MushafPage, skipOffstage: false),
            )
            .map((widget) => widget.page),
        orderedEquals([561, 562, 563]),
      );
      // The neighboring pages have completed layout before the first drag,
      // but do not replace the user's saved reading position.
      for (final neighbor in [561, 563]) {
        final bounds = tester.getRect(page(neighbor));
        expect(bounds.size, tester.getSize(currentPage()));
        expect(bounds.overlaps(viewport), isFalse);
      }
      expect(quran.state.currentPage, 562);
      expect(storage.readMap('quran'), savedReadingPosition);

      final preparedPage = tester.state(page(563));
      final preparedViewer = tester.widget<InteractiveViewer>(
        find.descendant(
          of: page(563),
          matching: find.byType(InteractiveViewer, skipOffstage: false),
          skipOffstage: false,
        ),
      );
      final preparedTransform = preparedViewer.transformationController;

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(
        const Offset(130, 0),
        timeStamp: const Duration(milliseconds: 200),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(
        const Offset(-110, 0),
        timeStamp: const Duration(milliseconds: 600),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up(timeStamp: const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(quran.state.currentPage, 562);
      expect(storage.readMap('quran'), savedReadingPosition);
      expect(tester.state(page(563)), same(preparedPage));

      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(quran.state.currentPage, 563);
      expect(tester.state(currentPage()), same(preparedPage));
      expect(viewer(tester).transformationController, same(preparedTransform));

      for (final destination in [564, 563, 562, 561, 562]) {
        final forward = destination > quran.state.currentPage;
        await tester.fling(
          find.byType(PageView),
          Offset(forward ? 250 : -250, 0),
          600,
        );
        await tester.pumpAndSettle();
        expect(quran.state.currentPage, destination);
        expect(storage.readMap('quran')['currentPage'], destination);
        expect(
          tester
              .widgetList<MushafPage>(
                find.byType(MushafPage, skipOffstage: false),
              )
              .map((widget) => widget.page),
          orderedEquals([destination - 1, destination, destination + 1]),
          reason: 'Preloading stays bounded as the reader moves both ways',
        );
        expect(
          find.byKey(ValueKey('mushaf-page-number-$destination')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('fullscreen preloading respects the first and last page', (
    tester,
  ) async {
    await openReader(tester, page: 1);
    await enterFullscreen(tester);
    for (final boundary in [1, 604]) {
      await quran.openPage(boundary);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<MushafPage>(
              find.byType(MushafPage, skipOffstage: false),
            )
            .map((widget) => widget.page),
        orderedEquals(boundary == 1 ? [1, 2] : [603, 604]),
      );
      await tester.fling(
        find.byType(PageView),
        Offset(boundary == 1 ? -300 : 300, 0),
        600,
      );
      await tester.pumpAndSettle();
      expect(quran.state.currentPage, boundary);
      expect(storage.readMap('quran')['currentPage'], boundary);
      expect(
        find.byKey(ValueKey('mushaf-page-number-$boundary')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fullscreen keeps ayah selection and RTL page swipes working', (
    tester,
  ) async {
    await openReader(tester);
    await enterFullscreen(tester);

    final layer = find.descendant(
      of: currentPage(),
      matching: find.byType(MushafInteractionLayer),
    );
    final geometry = layoutRepository.getPageGeometry(562)!;
    final ayah = geometry.ayahs.first;
    final point = tester
        .widget<MushafInteractionLayer>(layer)
        .mapper
        .viewBoxToLocal(
          viewBoxCoordinate: ayah.segments.first.samplePoint,
          contentSize: tester.getSize(layer),
          viewBox: geometry.viewBox,
        );
    await tester.tapAt(tester.getTopLeft(layer) + point);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final interaction = tester.element(layer).read<MushafInteractionCubit>();
    expect(interaction.state.selectedAyah?.globalAyah, ayah.globalAyah);

    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(quran.state.currentPage, 563);
    expect(
      find.byKey(const ValueKey('mushaf-page-number-563')),
      findsOneWidget,
    );
    expect(interaction.state.selectedAyah, isNull);

    await quran.openPage(604);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(quran.state.currentPage, 604);
    expect(
      find.byKey(const ValueKey('mushaf-page-number-604')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
