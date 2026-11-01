import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/adhkar/data/models/adhkar_models.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';
import 'package:mishkat_app/features/adhkar/presentation/pages/adhkar_page.dart';
import 'package:mishkat_app/features/adhkar/presentation/pages/adhkar_reader_page.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<AdhkarCategory> categories;

  setUpAll(() async {
    categories = await AdhkarRepository().load();
  });

  test(
    'splits the source chapter into focused morning and evening wirds',
    () async {
      final morning = categories.singleWhere((item) => item.id == 1);
      final evening = categories.singleWhere((item) => item.id == 133);

      expect(categories, hasLength(133));
      expect(morning.name, 'أذكار الصباح');
      expect(evening.name, 'أذكار المساء');
      expect(morning.items, hasLength(22));
      expect(evening.items, hasLength(21));
      expect(
        morning.items.any((item) => item.text.contains('إذا أمسى')),
        isFalse,
      );
      expect(evening.items.any((item) => item.text.contains('[')), isFalse);
      expect(evening.items[2].text, contains('أَمْسَيْنَا'));
      expect(
        evening.items.any((item) => item.text.contains('عِلْماً نَافِعاً')),
        isFalse,
      );
      expect(
        evening.items.any(
          (item) => item.text.contains('بِكَلِمَاتِ اللَّهِ التَّامَّاتِ'),
        ),
        isTrue,
      );
    },
  );

  test('tahlil appears once with the counts available for each wird', () {
    final morning = categories.singleWhere((item) => item.id == 1);
    final evening = categories.singleWhere((item) => item.id == 133);
    expect(
      morning.items.where((item) => item.countOptions.isNotEmpty),
      hasLength(1),
    );
    expect(morning.items[17].countOptions, [1, 10, 100]);
    expect(evening.items[17].countOptions, [1, 10]);
    expect(morning.items[8].count, 7);
    expect(evening.items[8].count, 7);
    expect(morning.items[1].text, isNot(contains(r'\u06dd')));
    expect(evening.items[2].text, contains('مَا بَعْدَهَا'));
    expect(evening.items[14].text, contains('هذه الليلة'));
    expect(evening.items[14].text, isNot(contains('هَذَا الْيَوْمِ')));
  });

  test('merging cards preserves saved counts and shifts later morning progress', () async {
    final storage = _MemoryStorage();
    final today = DateTime.now();
    await storage.writeMap('adhkar', {
      'dailyDate':
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      'progress': {
        '1': {'17': 10, '18': 42, '19': 2, '22': 7},
        '133': {'18': 55},
      },
    });
    final cubit = AdhkarCubit(_PreparedRepository(categories), storage);
    await cubit.load();
    addTearDown(cubit.close);
    expect(cubit.state.progress[1]?[17], 42);
    expect(cubit.state.progress[1]?[18], 2);
    expect(cubit.state.progress[1]?[21], 7);
    expect(cubit.state.progress[133]?[18], 55);
    cubit.select(1);
    expect(cubit.state.selected!.items[17].count, 100);
    await cubit.setCountTarget(1, 17, 10);
    await cubit.increment(1, 17);
    expect(cubit.countFor(1, 17), 42);
    await cubit.setCountTarget(1, 17, 100);
    await cubit.increment(1, 17);
    expect(cubit.countFor(1, 17), 43);
    await cubit.load();
    expect(cubit.countFor(1, 17), 43);
    expect(cubit.state.selected!.items[17].count, 100);
    await cubit.resetCategory(1);
    expect(cubit.countFor(1, 17), 0);
    expect(cubit.state.progress[133]?[18], 55);
  });

  for (final (dark, scale, height) in [
    (false, 1.3, 640.0),
    (true, 1.3, 640.0),
    (false, 2.0, 568.0),
  ]) {
    testWidgets(
      'card reader supports RTL, counting and long text at 320px (${dark ? 'dark' : 'light'}, scale $scale)',
      (tester) async {
        tester.view.physicalSize = Size(320, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final cubit = AdhkarCubit(
          _PreparedRepository(categories),
          _MemoryStorage(),
        );
        await cubit.load();
        cubit.select(1);
        addTearDown(cubit.close);
        await tester.pumpWidget(
          BlocProvider.value(
            value: cubit,
            child: MaterialApp(
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: dark
                  ? AppTheme.dark(1.3)
                  : AppTheme.light(scale > 1.5 ? 1 : 1.3),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const AdhkarReaderPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<PageView>(find.byType(PageView)).controller!.page,
          0,
        );
        await tester.tap(
          find.byKey(const ValueKey('dhikr-counter')).hitTestable(),
        );
        await _settleCompletion(tester);
        expect(cubit.countFor(1, 0), 1);
        expect(_currentPage(tester), 1);
        expect(cubit.countFor(1, 1), 0);
        await tester.tap(find.byTooltip('الذكر السابق'));
        await tester.pumpAndSettle();
        expect(_currentPage(tester), 0);
        await tester.tap(find.byKey(const ValueKey('dhikr-card-0')));
        await _settleCompletion(tester);
        expect(cubit.countFor(1, 0), 1);
        expect(_currentPage(tester), 0);
        await tester.drag(find.byType(PageView), const Offset(260, 0));
        await tester.pumpAndSettle();
        expect(_currentPage(tester), 1);
        expect(cubit.countFor(1, 1), 0);
        await tester.tap(find.byTooltip('فهرس الورد'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('dhikr-index-17')),
          400,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('dhikr-index-17')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<PageView>(find.byType(PageView)).controller!.page,
          17,
        );
        expect(
          tester
              .getSize(
                find.descendant(
                  of: find.byKey(const ValueKey('dhikr-card-17')),
                  matching: find.byType(Scrollable),
                ),
              )
              .height,
          greaterThan(100),
        );
        // The text and count choices scroll; the main counter stays reachable.
        await tester.scrollUntilVisible(
          find.widgetWithText(ChoiceChip, '100'),
          160,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('dhikr-card-17')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(ChoiceChip, '100'));
        await tester.pumpAndSettle();
        expect(cubit.state.selected!.items[17].count, 100);
        expect(cubit.countFor(1, 17), 0);
        await tester.tap(
          find.byKey(const ValueKey('dhikr-counter')).hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(cubit.countFor(1, 17), 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'text, blank space and the counter each count once, then advance',
    (tester) async {
      final cubit = await _pumpReader(tester, const [
        DhikrItem(text: 'سبحان الله', count: 3),
        DhikrItem(text: 'الحمد لله', count: 2),
      ]);

      await tester.tap(find.text('سبحان الله'));
      await tester.pumpAndSettle();
      expect(cubit.countFor(50, 0), 1);
      expect(_currentPage(tester), 0);

      final card = tester.getRect(find.byKey(const ValueKey('dhikr-card-0')));
      await tester.tapAt(card.topLeft + const Offset(10, 100));
      await tester.pumpAndSettle();
      expect(cubit.countFor(50, 0), 2);
      expect(_currentPage(tester), 0);

      await tester.tap(
        find.byKey(const ValueKey('dhikr-counter')).hitTestable(),
      );
      await tester.pump();
      expect(cubit.countFor(50, 0), 3);
      // Repeated taps during the completion pause must not spill into the next card.
      await tester.tap(find.text('سبحان الله'));
      await tester.tap(find.text('سبحان الله'));
      await _settleCompletion(tester);
      expect(_currentPage(tester), 1);
      expect(cubit.countFor(50, 0), 3);
      expect(cubit.countFor(50, 1), 0);

      await tester.tap(find.byTooltip('الذكر السابق'));
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 0);
      await tester.tap(find.text('سبحان الله'));
      await _settleCompletion(tester);
      expect(cubit.countFor(50, 0), 3);
      expect(_currentPage(tester), 0);
    },
  );

  testWidgets(
    'RTL swipes preserve partial counts without counting the gesture',
    (tester) async {
      final cubit = await _pumpReader(tester, const [
        DhikrItem(text: 'سبحان الله', count: 3),
        DhikrItem(text: 'الحمد لله', count: 3),
      ]);
      await tester.tap(find.text('سبحان الله'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 1);
      expect(cubit.countFor(50, 0), 1);
      expect(cubit.countFor(50, 1), 0);

      await tester.tap(find.text('الحمد لله'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 0);
      expect(cubit.countFor(50, 0), 1);
      expect(cubit.countFor(50, 1), 1);
      await tester.tap(find.text('سبحان الله'));
      await tester.pumpAndSettle();
      expect(cubit.countFor(50, 0), 2);
    },
  );

  testWidgets(
    'long text scrolls vertically without incrementing or navigating',
    (tester) async {
      final cubit = await _pumpReader(tester, [
        DhikrItem(
          text: List.filled(60, 'سبحان الله وبحمده').join(' '),
          count: 3,
        ),
        const DhikrItem(text: 'الحمد لله', count: 3),
      ]);
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('dhikr-card-0')),
        matching: find.byType(Scrollable),
      );
      await tester.drag(scrollable, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0),
      );
      expect(cubit.countFor(50, 0), 0);
      expect(_currentPage(tester), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'copy, options and repetition choices do not count as recitation',
    (tester) async {
      final cubit = await _pumpReader(tester, const [
        DhikrItem(text: 'سبحان الله', count: 3, countOptions: [3, 10]),
      ]);
      await tester.tap(find.byTooltip('نسخ الذكر').hitTestable());
      await tester.pumpAndSettle();
      expect(cubit.countFor(50, 0), 0);
      await tester.tap(find.byTooltip('خيارات الذكر').hitTestable());
      await tester.pumpAndSettle();
      expect(cubit.countFor(50, 0), 0);
      await tester.tap(find.text('إعادة عدّ هذا الذكر'));
      await tester.pumpAndSettle();
      expect(cubit.countFor(50, 0), 0);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '10'));
      await tester.tap(find.widgetWithText(ChoiceChip, '10'));
      await tester.pumpAndSettle();
      expect(cubit.state.selected!.items.single.count, 10);
      expect(cubit.countFor(50, 0), 0);
    },
  );

  for (final swipe in [false, true]) {
    testWidgets(
      '${swipe ? 'swiping' : 'previous control'} cancels a pending automatic advance',
      (tester) async {
        final cubit = await _pumpReader(tester, const [
          DhikrItem(text: 'سبحان الله', count: 3),
          DhikrItem(text: 'الحمد لله', count: 1),
          DhikrItem(text: 'الله أكبر', count: 3),
        ]);
        await tester.tap(find.byTooltip('الذكر التالي'));
        await tester.pumpAndSettle();
        expect(_currentPage(tester), 1);
        await tester.tap(find.text('الحمد لله'));
        await tester.pump();
        expect(cubit.countFor(50, 1), 1);
        if (swipe) {
          await tester.drag(find.byType(PageView), const Offset(-300, 0));
        } else {
          await tester.tap(find.byTooltip('الذكر السابق'));
        }
        await _settleCompletion(tester);
        expect(_currentPage(tester), 0);
        expect(cubit.countFor(50, 0), 0);
        expect(cubit.countFor(50, 2), 0);
      },
    );
  }

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'the last card stays complete without wrapping (reduced motion: $reducedMotion)',
      (tester) async {
        final cubit = await _pumpReader(tester, const [
          DhikrItem(text: 'سبحان الله', count: 1),
          DhikrItem(text: 'الحمد لله', count: 1),
        ], reducedMotion: reducedMotion);
        await tester.tap(find.text('سبحان الله'));
        await _settleCompletion(tester);
        expect(_currentPage(tester), 1);
        await tester.tap(find.text('الحمد لله'));
        await _settleCompletion(tester);
        expect(_currentPage(tester), 1);
        expect(cubit.countFor(50, 1), 1);
        expect(find.text('أتممت الورد، تقبّل الله منك'), findsOneWidget);
        await tester.tap(find.text('الحمد لله'));
        await _settleCompletion(tester);
        expect(_currentPage(tester), 1);
        expect(cubit.countFor(50, 1), 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the accessible counter announces remaining repetitions and advances',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final cubit = await _pumpReader(tester, const [
          DhikrItem(text: 'سبحان الله', count: 2),
          DhikrItem(text: 'الحمد لله', count: 1),
        ]);
        final counterFinder = find.byKey(const ValueKey('dhikr-counter'));
        var counter = tester.getSemantics(counterFinder);
        expect(counter.getSemanticsData().label, 'عدّ الذكر');
        expect(counter.getSemanticsData().value, 'المتبقي 2 من 2');
        expect(
          counter.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(find.bySemanticsLabel('سبحان الله'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.byTooltip('نسخ الذكر').hitTestable())
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        counter.owner!.performAction(counter.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(cubit.countFor(50, 0), 1);
        expect(_currentPage(tester), 0);
        counter = tester.getSemantics(counterFinder);
        expect(counter.getSemanticsData().value, 'المتبقي 1 من 2');
        counter.owner!.performAction(counter.id, SemanticsAction.tap);
        await _settleCompletion(tester);
        expect(cubit.countFor(50, 0), 2);
        expect(cubit.countFor(50, 1), 0);
        expect(_currentPage(tester), 1);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('disposing the reader cancels a pending automatic transition', (
    tester,
  ) async {
    final cubit = await _pumpReader(tester, const [
      DhikrItem(text: 'سبحان الله', count: 1),
      DhikrItem(text: 'الحمد لله', count: 1),
    ]);
    await tester.tap(find.text('سبحان الله'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleCompletion(tester);
    expect(cubit.countFor(50, 0), 1);
    expect(cubit.countFor(50, 1), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows separate daily wirds and filters chapters by occasion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = _MemoryStorage();
    final cubit = AdhkarCubit(_PreparedRepository(categories), storage);
    final tasbihCubit = TasbihCubit(storage);
    await cubit.load();
    addTearDown(cubit.close);
    addTearDown(tasbihCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit),
          BlocProvider.value(value: tasbihCubit),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          home: const Scaffold(body: AdhkarPage()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('أذكار الصباح'), findsOneWidget);
    expect(find.text('أذكار المساء'), findsOneWidget);
    expect(
      find.text('133 بابًا موثوقًا، مرتّبة لتصل إلى ذكرك في لحظات.'),
      findsOneWidget,
    );
    expect(find.text('المسبحة الإلكترونية'), findsOneWidget);

    await tester.tap(find.text('المسبحة الإلكترونية'));
    await tester.pumpAndSettle();
    expect(find.text('هدف الجلسة'), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('الصلاة'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('الصلاة'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.text('دعاء الاستفتاح'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('دعاء الاستفتاح'), findsOneWidget);
    expect(find.text('أذكار النوم'), findsNothing);
  });
}

double _currentPage(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

Future<void> _settleCompletion(WidgetTester tester) async {
  // A completion pause uses a timer, which pumpAndSettle alone may not flush.
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<AdhkarCubit> _pumpReader(
  WidgetTester tester,
  List<DhikrItem> items, {
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final cubit = AdhkarCubit(
    _PreparedRepository([
      AdhkarCategory(id: 50, name: 'ورد الاختبار', items: items),
    ]),
    _MemoryStorage(),
  );
  await cubit.load();
  cubit.select(50);
  addTearDown(cubit.close);
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: const AdhkarReaderPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

class _PreparedRepository extends AdhkarRepository {
  _PreparedRepository(this.categories);
  final List<AdhkarCategory> categories;

  @override
  Future<List<AdhkarCategory>> load() => SynchronousFuture(categories);
}

class _MemoryStorage implements LocalStorageService {
  final _data = <String, dynamic>{};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from(_data[key] as Map? ?? const {});

  @override
  List<dynamic> readList(String key) =>
      List<dynamic>.from(_data[key] as List? ?? const []);

  @override
  int readInt(String key, [int fallback = 0]) =>
      (_data[key] as num?)?.toInt() ?? fallback;

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
  Future<void> clear() async => _data.clear();
}
