import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';
import 'package:mishkat_app/features/adhkar/presentation/pages/adhkar_reader_page.dart';
import 'package:mishkat_app/features/adhkar/presentation/pages/my_duas_page.dart';

final _repository = AdhkarRepository();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _repository.load();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'creates independent duas and adds cards only inside the chosen dua ($dark)',
      (tester) async {
        final cubit = await _cubit();
        final siblingId = await cubit.saveCustom(
          title: 'دعاء الرزق',
          text: 'اللهم ارزقني',
          count: 2,
        );
        await cubit.increment(siblingId, 0);
        await cubit.increment(1, 0);
        final bundledCategories = cubit.state.categories;
        await _pumpList(tester, cubit, dark: dark, scale: 1.3);

        await tester.tap(find.byTooltip('إضافة دعاء جديد'));
        await tester.pumpAndSettle();
        await _enter(tester, 'عنوان الدعاء (اختياري)', 'دعاء الوالدين');
        await _enter(tester, 'نص الدعاء أو الذكر *', 'اللهم اغفر لوالدي');
        await _enter(tester, 'عدد مرات التكرار', '٣');
        await _tapText(tester, 'حفظ في أدعيتي');

        expect(cubit.state.customDuas, hasLength(2));
        final duaId = cubit.state.customDuas.last.id;
        expect(cubit.state.categoryById(duaId)!.items.single.count, 3);
        await _openDua(tester, duaId);
        expect(cubit.state.selectedId, duaId);
        expect(_pageCount(tester), 1);
        expect(find.text('اللهم ارزقني'), findsNothing);

        await tester.tap(find.byTooltip('إضافة بطاقة'));
        await tester.pumpAndSettle();
        await _enter(tester, 'عنوان البطاقة (اختياري)', 'رحمة للوالدين');
        await _enter(tester, 'نص البطاقة *', 'رب ارحمهما كما ربياني صغيرا');
        await _enter(tester, 'عدد مرات التكرار', '١');
        await _tapText(tester, 'إضافة البطاقة');

        expect(cubit.state.customDuas, hasLength(2));
        expect(cubit.state.categoryById(duaId)!.items, hasLength(2));
        expect(_pageCount(tester), 2);
        for (var count = 1; count <= 3; count++) {
          await tester.tap(
            find.byKey(const ValueKey('dhikr-counter')).hitTestable(),
          );
          await _settleCompletion(tester);
          expect(cubit.countFor(duaId, 0), count);
          expect(_currentPage(tester), count == 3 ? 1 : 0);
          expect(cubit.countFor(duaId, 1), 0);
        }
        await tester.tap(
          find.byKey(const ValueKey('dhikr-counter')).hitTestable(),
        );
        await _settleCompletion(tester);
        expect(_currentPage(tester), 1);
        expect(cubit.countFor(duaId, 1), 1);
        await tester.drag(find.byType(PageView), const Offset(300, 0));
        await tester.pumpAndSettle();
        expect(_currentPage(tester), 1);
        await tester.tap(find.byTooltip('الذكر السابق'));
        await tester.pumpAndSettle();
        expect(_currentPage(tester), 0);

        expect(cubit.countFor(siblingId, 0), 1);
        expect(cubit.state.categoryById(siblingId)!.items, hasLength(1));
        expect(cubit.countFor(1, 0), 1);
        expect(cubit.state.categories, bundledCategories);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'editing and deleting cards preserves sibling duas and allows an empty dua',
    (tester) async {
      final cubit = await _cubit();
      final duaId = await cubit.saveCustom(
        title: 'دعاء الوالدين',
        text: 'اللهم اغفر لوالدي',
        count: 3,
      );
      await cubit.saveCustom(
        duaId: duaId,
        title: 'البطاقة الثانية',
        text: 'رب ارحمهما',
        count: 2,
      );
      final siblingId = await cubit.saveCustom(
        title: 'دعاء الرزق',
        text: 'اللهم ارزقني',
        count: 4,
      );
      await cubit.increment(duaId, 0);
      await cubit.increment(duaId, 1);
      await cubit.increment(siblingId, 0);
      await cubit.increment(133, 0);
      await _pumpList(tester, cubit);
      await _openDua(tester, duaId);

      await tester.tap(find.byTooltip('خيارات الذكر').hitTestable());
      await tester.pumpAndSettle();
      await _tapText(tester, 'تعديل');
      await _enter(tester, 'نص البطاقة *', 'اللهم اغفر لوالدي وارحمهما');
      await _tapText(tester, 'حفظ التعديلات');
      expect(
        cubit.state.selected!.items.first.text,
        'اللهم اغفر لوالدي وارحمهما',
      );
      expect(cubit.countFor(duaId, 0), 0);
      expect(cubit.countFor(duaId, 1), 1);

      await _deleteCard(tester, cancel: true);
      expect(cubit.state.selected!.items, hasLength(2));
      await _deleteCard(tester);
      expect(cubit.state.selected!.items.single.text, 'رب ارحمهما');
      expect(cubit.countFor(duaId, 0), 1);
      await _deleteCard(tester);
      expect(cubit.state.selected!.items, isEmpty);
      expect(find.text('بطاقات هذا الدعاء'), findsOneWidget);
      expect(find.byType(PageView), findsNothing);

      await _tapText(tester, 'إضافة بطاقة');
      await _enter(tester, 'نص البطاقة *', 'اللهم ارحم والدينا');
      await _tapText(tester, 'إضافة البطاقة');
      expect(cubit.state.selectedId, duaId);
      expect(cubit.state.selected!.items.single.text, 'اللهم ارحم والدينا');
      expect(cubit.state.customDuas, hasLength(2));
      expect(cubit.countFor(siblingId, 0), 1);
      expect(
        cubit.state.categoryById(siblingId)!.items.single.text,
        'اللهم ارزقني',
      );
      expect(cubit.countFor(133, 0), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'list renames, searches and confirms deletion of only the chosen dua',
    (tester) async {
      final cubit = await _cubit();
      final duaId = await cubit.saveCustom(
        title: 'دعاء قديم',
        text: 'اللهم اغفر لي',
        count: 3,
      );
      final siblingId = await cubit.saveCustom(
        title: 'دعاء الرزق',
        text: 'اللهم ارزقني',
        count: 2,
      );
      await cubit.increment(siblingId, 0);
      await _pumpList(tester, cubit, dark: true, scale: 1.3);

      await _openDuaOptions(tester, duaId);
      await _tapText(tester, 'تعديل العنوان');
      await _enter(tester, 'عنوان الدعاء', 'دعاء المغفرة');
      await _tapText(tester, 'حفظ');
      expect(cubit.state.categoryById(duaId)!.name, 'دعاء المغفرة');

      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'ابحث في أدعيتك',
      );
      await tester.enterText(search, 'المغفرة');
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('custom-dua-$duaId')), findsOneWidget);
      expect(find.byKey(ValueKey('custom-dua-$siblingId')), findsNothing);
      await tester.enterText(search, 'ارزقني');
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('custom-dua-$siblingId')), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();

      await _openDuaOptions(tester, duaId);
      await _tapText(tester, 'حذف الدعاء');
      expect(find.text('حذف الدعاء؟'), findsOneWidget);
      await _tapText(tester, 'إلغاء');
      expect(cubit.state.customDuas, hasLength(2));
      await _openDuaOptions(tester, duaId);
      await _tapText(tester, 'حذف الدعاء');
      await _tapText(tester, 'حذف');
      expect(cubit.state.customDuas.single.id, siblingId);
      expect(cubit.countFor(siblingId, 0), 1);
      expect(find.byKey(ValueKey('custom-dua-$duaId')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('legacy category zero opens the independent list', (
    tester,
  ) async {
    final cubit = await _cubit();
    final duaId = await cubit.saveCustom(
      title: 'دعائي',
      text: 'اللهم اغفر لي',
      count: 1,
    );
    cubit.select(0);
    await _pumpList(tester, cubit, home: const AdhkarReaderPage());
    expect(find.byType(MyDuasPage), findsOneWidget);
    expect(find.byKey(ValueKey('custom-dua-$duaId')), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    await _openDua(tester, duaId);
    expect(cubit.state.selectedId, duaId);
    expect(_pageCount(tester), 1);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.byType(MyDuasPage), findsOneWidget);
    expect(find.byKey(ValueKey('custom-dua-$duaId')), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<AdhkarCubit> _cubit() async {
  final cubit = AdhkarCubit(_repository, _MemoryStorage());
  await cubit.load();
  addTearDown(cubit.close);
  return cubit;
}

Future<void> _pumpList(
  WidgetTester tester,
  AdhkarCubit cubit, {
  bool dark = false,
  double scale = 1,
  Widget home = const MyDuasPage(),
}) async {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final field = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _openDua(WidgetTester tester, int duaId) async {
  final target = find.byKey(ValueKey('custom-dua-$duaId'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _openDuaOptions(WidgetTester tester, int duaId) async {
  final target = find.descendant(
    of: find.byKey(ValueKey('custom-dua-$duaId')),
    matching: find.byTooltip('خيارات الدعاء'),
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _deleteCard(WidgetTester tester, {bool cancel = false}) async {
  await tester.tap(find.byTooltip('خيارات الذكر').hitTestable());
  await tester.pumpAndSettle();
  await _tapText(tester, 'حذف');
  expect(find.text('حذف البطاقة؟'), findsOneWidget);
  await _tapText(tester, cancel ? 'إلغاء' : 'حذف');
}

int? _pageCount(WidgetTester tester) => tester
    .widget<PageView>(find.byType(PageView))
    .childrenDelegate
    .estimatedChildCount;

double _currentPage(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

Future<void> _settleCompletion(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

class _MemoryStorage extends LocalStorageService {
  final _maps = <String, Map<String, dynamic>>{};

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from(_maps[key] ?? const {});

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _maps[key] = value;
  }
}
