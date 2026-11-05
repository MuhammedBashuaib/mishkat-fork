import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_state.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_recitation_text.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/oral_recitation_mushaf.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/oral_recitation_word_page.dart';

class _DeferredLayoutBundle extends CachingAssetBundle {
  Completer<String> pending = Completer<String>();

  @override
  Future<String> loadString(String key, {bool cache = true}) => pending.future;

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MushafLayoutRepository repository;
  late QuranRepository quranRepository;
  late QuranData quran;
  late String layoutJson;

  setUpAll(() async {
    layoutJson = await rootBundle.loadString('assets/data/mushaf-layout.json');
    repository = MushafLayoutRepository()..loadFromJsonString(layoutJson);
    quranRepository = QuranRepository();
    quran = await quranRepository.load();
    await OralRecitationMushaf.preloadCanonicalText();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf'))).load();
    await (FontLoader(
      'QpcHafs',
    )..addFont(rootBundle.load('assets/fonts/UthmanicHafs_V22.ttf'))).load();
  });

  QuranOralRecitationState session({
    List<int> globals = const [1, 2],
    int? current,
    String id = 'mushaf-test',
    OralRecitationMode mode = OralRecitationMode.hidden,
    Set<int> revealed = const {},
    Set<int> visible = const {},
  }) {
    final words = <AuthoritativeWord>[];
    for (final global in globals) {
      final ayah = repository.getAyah(global)!;
      final text = quran.chapter(ayah.surah).ayahs[ayah.ayah - 1];
      for (final word in text.split(RegExp(r'\s+'))) {
        if (!QuranRecitationText.hasArabicLetter(word)) continue;
        words.add(
          AuthoritativeWord(
            globalAyah: global,
            surah: ayah.surah,
            ayahInSurah: ayah.ayah,
            wordIndex: words.length,
            uthmaniText: word,
            normalizedText: QuranRecitationText.normalize(word),
          ),
        );
      }
    }
    return QuranOralRecitationState(
      sessionId: id,
      mode: mode,
      lifecycle: OralRecitationLifecycle.ready,
      currentGlobalAyah: current ?? globals.first,
      revealedGlobals: revealed,
      visibleWordIndices: visible,
      targetWords: words,
    );
  }

  Widget harness(
    QuranOralRecitationState state, {
    MushafLayoutRepository? layout,
    bool dark = false,
    double textScale = 1,
    bool useSharedCanonical = false,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark(1) : AppTheme.light(1),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: OralRecitationMushaf(
            state: state,
            layoutRepository: layout ?? repository,
            quranRepository: useSharedCanonical ? null : quranRepository,
          ),
        ),
      ),
    ),
  );

  OralRecitationWordsPainter painter(WidgetTester tester, int page) {
    final finder = find.descendant(
      of: find.byKey(Key('oral-mushaf-page-$page')),
      matching: find.byKey(const Key('oral-word-page-paint')),
    );
    return tester.widget<CustomPaint>(finder).painter!
        as OralRecitationWordsPainter;
  }

  Set<int> visible(WidgetTester tester, int page) => {
    for (final word in painter(tester, page).words)
      if (word.visible && word.targetIndex != null) word.targetIndex!,
  };

  testWidgets(
    'shared decoded canonical data survives asset cache resets and remounts',
    (tester) async {
      rootBundle.clear();
      await tester.pumpWidget(harness(session(), useSharedCanonical: true));
      await tester.pumpAndSettle();
      expect(find.byType(OralRecitationWordPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      rootBundle.clear();
      await tester.pumpWidget(
        harness(session(id: 'reopened'), useSharedCanonical: true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OralRecitationWordPage), findsOneWidget);
      expect(visible(tester, 1), isEmpty);
    },
  );

  testWidgets('cold page never flashes text and failed layout can retry', (
    tester,
  ) async {
    final bundle = _DeferredLayoutBundle();
    final cold = MushafLayoutRepository(bundle: bundle);
    await tester.pumpWidget(harness(session(), layout: cold));
    expect(find.byType(OralRecitationWordPage), findsNothing);
    expect(find.byKey(const Key('oral-mushaf-loading')), findsOneWidget);
    bundle.pending.completeError(StateError('layout unavailable'));
    await tester.pump();
    expect(find.byType(OralRecitationWordPage), findsNothing);
    expect(find.text('تعذّر تجهيز صفحة المصحف'), findsOneWidget);
    bundle.pending = Completer<String>();
    await tester.tap(find.byKey(const Key('oral-mushaf-retry')));
    await tester.pump();
    bundle.pending.complete(layoutJson);
    await tester.pumpAndSettle();
    expect(visible(tester, 1), isEmpty);
  });

  testWidgets('hidden page retains word positions without leaking semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final state = session(current: 2);
    await tester.pumpWidget(harness(state));
    await tester.pumpAndSettle();
    final before = painter(tester, 1).words;
    expect(before.every((word) => !word.visible), isTrue);
    final semanticsWidget = tester.widget<Semantics>(
      find.byKey(const Key('oral-word-page-semantics')),
    );
    expect(
      semanticsWidget.properties.label,
      'صفحة ١ من المصحف، موضع التسميع الآية ٢',
    );
    await tester.pumpWidget(
      harness(state.copyWith(visibleWordIndices: {0, 1})),
    );
    await tester.pumpAndSettle();
    expect(visible(tester, 1), {0, 1});
    final after = painter(tester, 1).words;
    expect(
      [for (final word in after) word.boxes],
      [for (final word in before) word.boxes],
    );
    final updated = tester
        .widget<Semantics>(find.byKey(const Key('oral-word-page-semantics')))
        .properties
        .label!;
    expect(updated, contains(state.targetWords[0].uthmaniText));
    expect(updated, isNot(contains(state.targetWords[2].uthmaniText)));
    semantics.dispose();
  });

  testWidgets(
    'mistake shows canonical word in red and leaves following words hidden',
    (tester) async {
      final global = quran.globalFor(2, 113);
      final base = session(globals: [global, global + 1], current: global);
      final wrongIndex = base.targetWords.indexWhere(
        (word) => QuranRecitationText.sameWord(word.uthmaniText, 'يختلفون'),
      );
      expect(wrongIndex, greaterThan(0));
      final shown = {for (var i = 0; i <= wrongIndex; i++) i};
      final state = base.copyWith(
        visibleWordIndices: shown,
        mistakeWordIndices: {wrongIndex},
        unresolvedMistakeWordIndices: {wrongIndex},
        liveTranscript: 'مختلفين',
      );
      await tester.pumpWidget(harness(state));
      await tester.pumpAndSettle();
      final page = repository.pageForAyah(global)!;
      final drawing = painter(tester, page);
      final wrong = drawing.words.singleWhere(
        (word) => word.targetIndex == wrongIndex,
      );
      expect(wrong.visible, isTrue);
      expect(wrong.mistake, isTrue);
      expect(wrong.unresolved, isTrue);
      expect(wrong.text, base.targetWords[wrongIndex].uthmaniText);
      expect(drawing.canonicalText, isNot(contains('مختلفين')));
      expect(
        drawing.words
            .where((word) => (word.targetIndex ?? -1) > wrongIndex)
            .every((word) => !word.visible),
        isTrue,
      );
      await tester.pumpWidget(
        harness(state.copyWith(unresolvedMistakeWordIndices: {})),
      );
      await tester.pumpAndSettle();
      final corrected = painter(
        tester,
        page,
      ).words.singleWhere((word) => word.targetIndex == wrongIndex);
      expect(corrected.mistake, isTrue);
      expect(corrected.unresolved, isFalse);
      expect(corrected.boxes, wrong.boxes);
    },
  );

  testWidgets('visibility follows word evidence and explicit assistance only', (
    tester,
  ) async {
    final base = session();
    await tester.pumpWidget(
      harness(
        base.copyWith(
          completedGlobalAyahs: {1},
          previewCompletedGlobalAyahs: {2},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(visible(tester, 1), isEmpty);
    await tester.pumpWidget(
      harness(base.copyWith(mode: OralRecitationMode.firstWord)),
    );
    await tester.pumpAndSettle();
    expect(visible(tester, 1), {0, 4});
    await tester.pumpWidget(harness(base.copyWith(hintedWordIndices: {2})));
    await tester.pumpAndSettle();
    expect(visible(tester, 1), {2});
    await tester.pumpWidget(harness(base.copyWith(revealedGlobals: {1, 3})));
    await tester.pumpAndSettle();
    expect(visible(tester, 1), {0, 1, 2, 3});
    await tester.pumpWidget(
      harness(base.copyWith(mode: OralRecitationMode.reading)),
    );
    await tester.pumpAndSettle();
    expect(visible(tester, 1), {
      for (var i = 0; i < base.targetWords.length; i++) i,
    });
    expect(
      painter(tester, 1).words
          .where((word) => word.targetIndex == null)
          .every((word) => !word.visible),
      isTrue,
    );
  });

  testWidgets('original pause marks survive canonical page shaping', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(session(globals: [9], mode: OralRecitationMode.reading)),
    );
    await tester.pumpAndSettle();
    final drawing = painter(tester, 2);
    expect(drawing.canonicalText, contains('ۛ'));
    expect(drawing.canonicalText, contains(quran.chapter(2).ayahs[1]));
  });

  testWidgets('printed lines preserve shared ayahs and split verse locations', (
    tester,
  ) async {
    await tester.pumpWidget(harness(session(globals: [1, 2, 3, 4, 5, 6, 7])));
    await tester.pumpAndSettle();
    final drawing = painter(tester, 1);
    expect(drawing.lineCount, 8);
    expect(
      drawing.words
          .where((word) => word.globalAyah == 3 || word.globalAyah == 4)
          .expand((word) => word.lineNumbers)
          .toSet(),
      {4},
      reason: 'The printed page shares a line between ayahs 3 and 4.',
    );
    expect(
      drawing.words
          .where((word) => word.globalAyah == 6)
          .expand((word) => word.lineNumbers)
          .toSet(),
      {5, 6},
      reason: 'A verse may continue onto another printed line.',
    );
    expect(drawing.words.every((word) => !word.visible), isTrue);
  });

  testWidgets('two printed parts reveal and correct as one canonical word', (
    tester,
  ) async {
    final global = quran.globalFor(2, 181);
    final base = session(globals: [global]);
    final index = base.targetWords.indexWhere(
      (word) => QuranRecitationText.normalize(word.uthmaniText) == 'بعدما',
    );
    expect(index, 2);
    await tester.pumpWidget(
      harness(
        base.copyWith(
          visibleWordIndices: {index},
          mistakeWordIndices: {index},
          unresolvedMistakeWordIndices: {index},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final page = repository.pageForAyah(global)!;
    final drawing = painter(tester, page);
    final word = drawing.words.singleWhere((word) => word.targetIndex == index);
    expect(word.text, base.targetWords[index].uthmaniText);
    expect(word.boxes.length, 2);
    expect(word.lineNumbers.length, 2);
    expect(word.visible, isTrue);
    expect(word.mistake, isTrue);
    expect(word.unresolved, isTrue);
    expect(visible(tester, page), {index});
    final label = tester
        .widget<Semantics>(find.byKey(const Key('oral-word-page-semantics')))
        .properties
        .label!;
    expect(RegExp(RegExp.escape(word.text)).allMatches(label).length, 1);
  });

  testWidgets('RTL browsing is local and follows a new current Ayah', (
    tester,
  ) async {
    final state = session(globals: [8, 13, 24], current: 13);
    await tester.pumpWidget(harness(state));
    await tester.pumpAndSettle();
    expect(find.text('صفحة ٣ من ٦٠٤'), findsOneWidget);
    await tester.tap(find.byKey(const Key('oral-mushaf-next')));
    await tester.pumpAndSettle();
    expect(find.text('صفحة ٤ من ٦٠٤'), findsOneWidget);
    expect(find.byKey(const Key('oral-mushaf-return')), findsOneWidget);
    await tester.pumpWidget(harness(state.copyWith(audioLevel: .5)));
    await tester.pumpAndSettle();
    expect(find.text('صفحة ٤ من ٦٠٤'), findsOneWidget);
    await tester.tap(find.byKey(const Key('oral-mushaf-return')));
    await tester.pumpAndSettle();
    expect(find.text('صفحة ٣ من ٦٠٤'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(650, 0));
    await tester.pumpAndSettle();
    expect(find.text('صفحة ٤ من ٦٠٤'), findsOneWidget);
    await tester.pumpWidget(harness(state.copyWith(currentGlobalAyah: 8)));
    await tester.pumpAndSettle();
    expect(find.text('صفحة ٢ من ٦٠٤'), findsOneWidget);
    expect(state.currentGlobalAyah, 13);
    await tester.pumpWidget(harness(state.copyWith(sessionId: 'fresh')));
    await tester.pumpAndSettle();
    expect(find.text('صفحة ٣ من ٦٠٤'), findsOneWidget);
  });

  testWidgets(
    'explicit reveal and word hint open their page without advancing reading',
    (tester) async {
      final base = session(globals: [8, 13], current: 8, visible: {0});
      await tester.pumpWidget(harness(base));
      await tester.pumpAndSettle();
      expect(find.text('صفحة ٢ من ٦٠٤'), findsOneWidget);
      await tester.pumpWidget(harness(base.copyWith(revealedGlobals: {13})));
      await tester.pumpAndSettle();
      expect(find.text('صفحة ٣ من ٦٠٤'), findsOneWidget);
      expect(base.currentGlobalAyah, 8);
      expect(base.committedTargetIndex, 0);
      await tester.pumpWidget(harness(base));
      await tester.pumpAndSettle();
      expect(find.text('صفحة ٣ من ٦٠٤'), findsOneWidget);
      await tester.tap(find.byKey(const Key('oral-mushaf-return')));
      await tester.pumpAndSettle();
      final hinted = base.targetWords.indexWhere(
        (word) => word.globalAyah == 13,
      );
      await tester.pumpWidget(
        harness(base.copyWith(hintedWordIndices: {hinted})),
      );
      await tester.pumpAndSettle();
      expect(find.text('صفحة ٣ من ٦٠٤'), findsOneWidget);
      expect(visible(tester, 3), {hinted});
    },
  );

  testWidgets('audio updates preserve zoom and a new session resets it', (
    tester,
  ) async {
    final state = session();
    await tester.pumpWidget(harness(state));
    await tester.pumpAndSettle();
    var viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
    viewer.onInteractionUpdate!(ScaleUpdateDetails(scale: 2));
    await tester.pump();
    await tester.pumpWidget(harness(state.copyWith(audioLevel: .8)));
    await tester.pump();
    viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 2);
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    await tester.pumpWidget(harness(state.copyWith(sessionId: 'fresh')));
    await tester.pumpAndSettle();
    viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
  });

  testWidgets(
    'vertical follow ignores raw partial cursor and follows stable revealed words',
    (tester) async {
      tester.view.physicalSize = const Size(390, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final page = repository.getPageGeometry(3)!;
      final base = session(
        globals: page.ayahs.map((a) => a.globalAyah).toList(),
        visible: {0, 1},
      );
      await tester.pumpWidget(harness(base));
      await tester.pumpAndSettle();
      final scrollFinder = find.descendant(
        of: find.byKey(const Key('oral-mushaf-page-3')),
        matching: find.byType(SingleChildScrollView),
      );
      final controller = tester
          .widget<SingleChildScrollView>(scrollFinder)
          .controller!;
      expect(controller.position.maxScrollExtent, greaterThan(100));
      controller.jumpTo(100);
      await tester.pump();
      final before = painter(tester, 3).words;
      await tester.pumpWidget(
        harness(
          base.copyWith(
            currentWordIndex: base.targetWords.length - 1,
            audioLevel: .8,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, 100);
      expect(identical(painter(tester, 3).words, before), isTrue);
      await tester.pumpWidget(
        harness(
          base.copyWith(
            visibleWordIndices: {
              for (var i = 0; i < base.targetWords.length; i++) i,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(100));
    },
  );

  testWidgets(
    'short landscape viewport follows the complete visible recitation line',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(640, 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = session(globals: [1, 2], visible: {0, 1, 2, 3});
      await tester.pumpWidget(harness(state));
      await tester.pumpAndSettle();
      final originalFontSize = painter(tester, 1).fontSize;
      // A correction panel can reduce the viewport while the same stable
      // recitation words remain visible.
      tester.view.physicalSize = const Size(640, 130);
      await tester.pumpAndSettle();
      final scrollFinder = find.descendant(
        of: find.byKey(const Key('oral-mushaf-page-1')),
        matching: find.byType(SingleChildScrollView),
      );
      final controller = tester
          .widget<SingleChildScrollView>(scrollFinder)
          .controller!;
      final drawing = painter(tester, 1);
      expect(drawing.fontSize, originalFontSize);
      expect(drawing.lineCount, 8);
      expect(controller.position.viewportDimension, 82);
      for (final word in drawing.words.where((word) => word.visible)) {
        for (final box in word.boxes) {
          expect(box.top - controller.offset, greaterThanOrEqualTo(-.001));
          expect(
            box.bottom - controller.offset,
            lessThanOrEqualTo(controller.position.viewportDimension + .001),
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone page uses its width and keeps type stable when viewport height changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = session();
      await tester.pumpWidget(harness(state));
      await tester.pumpAndSettle();
      final page = find.byKey(const Key('oral-mushaf-page-1'));
      final originalWidth = tester.getSize(page).width;
      expect(tester.getRect(page).left, greaterThanOrEqualTo(0));
      expect(originalWidth, greaterThanOrEqualTo(390 * .9));
      final before = painter(tester, 1);
      expect(before.fontSize, greaterThan(17));
      expect(before.lineCount, 8);
      for (final key in ['oral-mushaf-previous', 'oral-mushaf-next']) {
        expect(tester.getSize(find.byKey(Key(key))), const Size(48, 48));
      }

      tester.view.physicalSize = const Size(390, 480);
      await tester.pumpAndSettle();
      expect(tester.getSize(page).width, originalWidth);
      expect(painter(tester, 1).fontSize, before.fontSize);
      expect(
        [for (final word in painter(tester, 1).words) word.boxes],
        [for (final word in before.words) word.boxes],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dense pages scroll with readable type on compact and landscape sizes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [const Size(320, 440), const Size(844, 390)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final page = repository.getPageGeometry(3)!;
        final state = session(
          globals: page.ayahs.map((a) => a.globalAyah).toList(),
          mode: OralRecitationMode.reading,
        );
        await tester.pumpWidget(harness(state, dark: true, textScale: 1.6));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final drawing = painter(tester, 3);
        // QPC's metrics differ from Amiri; retain a readable base size on the
        // narrow phone while preserving all fifteen printed line breaks.
        expect(drawing.fontSize, greaterThanOrEqualTo(16));
        expect(drawing.lineCount, 15);
        expect(drawing.words.expand((word) => word.lineNumbers).toSet(), {
          for (var line = 1; line <= 15; line++) line,
        });
        expect(drawing.words.every((word) => word.visible), isTrue);
        expect(drawing.words.every((word) => word.boxes.isNotEmpty), isTrue);
        final pageRect = tester.getRect(
          find.byKey(const Key('oral-mushaf-page-3')),
        );
        expect(pageRect.left, greaterThanOrEqualTo(0));
        expect(pageRect.bottom, lessThanOrEqualTo(size.height));
      }
    },
  );
}
