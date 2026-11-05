import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_index_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

import 'quran_bookmarks_test.dart'
    show DummyAudioService, InMemoryLocalStorageService;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_QURAN_INDEX_JUMP');
  final repository = QuranRepository();
  late InMemoryLocalStorageService storage;
  late QuranCubit quran;
  late SettingsCubit settings;

  setUpAll(() async {
    await repository.load();
    await MushafLayoutRepository.instance.load();
    final cairo = FontLoader('Cairo');
    for (final weight in ['Regular', 'SemiBold', 'Bold', 'Black']) {
      cairo.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await cairo.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() async {
    storage = InMemoryLocalStorageService();
    quran = QuranCubit(
      repository: repository,
      storage: storage,
      audio: DummyAudioService(),
      reciter: 'ar.alafasy',
      fontSize: 32,
    );
    settings = SettingsCubit(
      storage: storage,
      locationService: LocationService(),
      notifications: LocalNotificationService(),
    );
    await quran.load();
    await settings.load();
    await quran.openPage(107);
  });

  tearDown(() async {
    await quran.close();
    await settings.close();
  });

  Future<void> mountIndex(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool dark = false,
    GlobalKey? boundaryKey,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: RepositoryProvider<LocalStorageService>.value(
          value: storage,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<QuranCubit>.value(value: quran),
              BlocProvider<SettingsCubit>.value(value: settings),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: const QuranIndexPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openJump(WidgetTester tester) async {
    await tester.tap(find.text('الانتقال إلى صفحة'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  }

  Future<void> saveCapture(
    WidgetTester tester,
    GlobalKey boundaryKey,
    String name,
  ) async {
    if (!capture) return;
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/mishkat-quran-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final scenario in [
    (input: '42', page: 42, keyboard: false),
    (input: ' ٦٠٤ ', page: 604, keyboard: true),
    (input: '۱', page: 1, keyboard: false),
  ]) {
    testWidgets(
      'jump opens and persists exact page ${scenario.page} from ${scenario.input}',
      (tester) async {
        await mountIndex(tester);
        await openJump(tester);
        await tester.enterText(find.byType(TextFormField), scenario.input);
        if (scenario.keyboard) {
          await tester.testTextInput.receiveAction(TextInputAction.go);
        } else {
          await tester.tap(find.text('انتقال'));
        }
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(QuranReaderPage), findsOneWidget);
        expect(quran.state.currentPage, scenario.page);
        expect(
          find.textContaining('صفحة ${scenario.page} من 604'),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is MushafPage &&
                widget.isCurrent &&
                widget.page == scenario.page,
          ),
          findsOneWidget,
        );
        final persisted = storage.readMap('quran');
        expect(persisted['currentPage'], scenario.page);
        expect(
          persisted['lastRead'],
          quran.state.data!.page(scenario.page).first.toJson(),
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('العودة إلى الفهرس'));
        await tester.pumpAndSettle();
        expect(find.byType(QuranIndexPage), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(quran.state.currentPage, scenario.page);
      },
    );
  }

  testWidgets('invalid page numbers keep the dialog and reading position', (
    tester,
  ) async {
    await mountIndex(tester);
    final before = storage.readMap('quran');
    await openJump(tester);
    for (final input in [
      '',
      '0',
      '٠',
      '-1',
      '605',
      '٦٠٥',
      '99999999999999999999',
      '1.5',
      '٤٢٫٥',
      '+42',
      '4 2',
      'abc',
    ]) {
      await tester.enterText(find.byType(TextFormField), input);
      await tester.tap(find.text('انتقال'));
      await tester.pumpAndSettle();
      expect(
        find.text('أدخل رقم صفحة من ١ إلى ٦٠٤'),
        findsOneWidget,
        reason: input,
      );
      expect(find.byType(AlertDialog), findsOneWidget, reason: input);
      expect(find.byType(QuranReaderPage), findsNothing, reason: input);
      expect(quran.state.currentPage, 107, reason: input);
      expect(storage.readMap('quran'), before, reason: input);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel preserves the surah filter and reading position', (
    tester,
  ) async {
    await mountIndex(tester);
    await tester.enterText(find.byType(TextField), 'الكهف');
    await tester.pumpAndSettle();
    final before = storage.readMap('quran');
    await openJump(tester);
    await tester.enterText(find.byType(TextFormField), '300');
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(QuranReaderPage), findsNothing);
    expect(find.text('سورة الكهف'), findsOneWidget);
    expect(find.text('سورة الفاتحة'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'الكهف',
    );
    expect(quran.state.currentPage, 107);
    expect(storage.readMap('quran'), before);
  });

  testWidgets('jump is available from all index tabs', (tester) async {
    await mountIndex(tester);
    for (final tab in ['السور', 'الأجزاء', 'العلامات']) {
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pumpAndSettle();
      await openJump(tester);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.byType(QuranReaderPage), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('index search keeps focus and filter as the keyboard changes', (
    tester,
  ) async {
    await mountIndex(tester, size: const Size(320, 568));
    final search = find.byType(TextField);
    await tester.enterText(search, 'الكهف');
    await tester.pumpAndSettle();
    final focus = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(focus.hasFocus, isTrue);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(tester.widget<TextField>(search).controller!.text, 'الكهف');
    expect(find.text('سورة الكهف'), findsOneWidget);
    expect(find.text('سورة الفاتحة'), findsNothing);
    expect(tester.takeException(), isNull);

    tester.testTextInput.enterText('البق');
    await tester.pumpAndSettle();
    expect(find.text('سورة البقرة'), findsOneWidget);
    expect(find.text('سورة الكهف'), findsNothing);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(tester.widget<TextField>(search).controller!.text, 'البق');
    tester.testTextInput.enterText('البقرة');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, 'البقرة');
    expect(find.text('سورة البقرة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'page jump fits 320px with keyboard (${dark ? 'dark' : 'light'})',
      (tester) async {
        final boundary = GlobalKey();
        final theme = dark ? 'dark' : 'light';
        await mountIndex(
          tester,
          size: const Size(320, 568),
          dark: dark,
          boundaryKey: boundary,
        );
        expect(tester.takeException(), isNull);
        await saveCapture(tester, boundary, 'index-$theme');
        await openJump(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), '605');
        await tester.tap(find.text('انتقال'));
        await tester.pumpAndSettle();
        expect(find.text('أدخل رقم صفحة من ١ إلى ٦٠٤'), findsOneWidget);
        expect(find.text('انتقال').hitTestable(), findsOneWidget);
        expect(find.text('إلغاء').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await saveCapture(tester, boundary, 'page-jump-$theme');
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }
}
