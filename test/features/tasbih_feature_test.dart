import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/pages/tasbih_page.dart';

void main() {
  testWidgets('bundles the offline completion chime', (tester) async {
    final sound = await rootBundle.load('assets/audio/tasbih_complete.wav');
    expect(sound.lengthInBytes, greaterThan(1000));
  });

  test(
    'persists the active session and safely migrates the old total',
    () async {
      final storage = _MemoryStorage()..put('tasbihTotal', 7);
      final now = DateTime(2026, 10, 29, 9);
      final cubit = TasbihCubit(storage, now: () => now);

      expect(cubit.state.total, 7);
      await cubit.increment();
      await cubit.increment();
      await cubit.setTarget(100);

      final restored = TasbihCubit(storage, now: () => now);
      expect(restored.state.count, 2);
      expect(restored.state.todayTotal, 2);
      expect(restored.state.total, 9);
      expect(restored.state.target, 100);

      await cubit.close();
      await restored.close();
    },
  );

  test(
    'starts a fresh daily total while preserving the current session',
    () async {
      final storage = _MemoryStorage();
      var now = DateTime(2026, 10, 29, 23, 59);
      final cubit = TasbihCubit(storage, now: () => now);
      await cubit.increment();
      await cubit.increment();
      await cubit.close();

      now = DateTime(2026, 10, 30, 0, 1);
      final nextDay = TasbihCubit(storage, now: () => now);
      expect(nextDay.state.count, 2);
      expect(nextDay.state.todayTotal, 0);
      expect(nextDay.state.total, 2);

      await nextDay.increment();
      expect(nextDay.state.count, 3);
      expect(nextDay.state.todayTotal, 1);
      expect(nextDay.state.total, 3);
      await nextDay.close();
    },
  );

  test(
    'changing dhikr resets only the session and undo corrects totals',
    () async {
      final storage = _MemoryStorage();
      final cubit = TasbihCubit(storage, now: () => DateTime(2026, 10, 29));
      await cubit.increment();
      await cubit.increment();
      await cubit.undo();

      expect(cubit.state.count, 1);
      expect(cubit.state.todayTotal, 1);
      expect(cubit.state.total, 1);

      await cubit.selectDhikr('tahlil');
      expect(cubit.state.count, 0);
      expect(cubit.state.dhikr.text, 'لا إله إلا الله');
      expect(cubit.state.target, 100);
      expect(cubit.state.total, 1);
      await cubit.close();
    },
  );

  test('persists a custom dhikr and completion sound preference', () async {
    final storage = _MemoryStorage();
    final now = DateTime(2026, 10, 29);
    final cubit = TasbihCubit(storage, now: () => now);

    await cubit.increment();
    await cubit.setCustomDhikr('  سبحانك اللهم وبحمدك  ', target: 7);
    await cubit.toggleCompletionSound();

    expect(cubit.state.count, 0);
    expect(cubit.state.dhikr.text, 'سبحانك اللهم وبحمدك');
    expect(cubit.state.target, 7);
    expect(cubit.state.completionSoundEnabled, isFalse);

    final restored = TasbihCubit(storage, now: () => now);
    expect(restored.state.dhikr.text, 'سبحانك اللهم وبحمدك');
    expect(restored.state.target, 7);
    expect(restored.state.completionSoundEnabled, isFalse);

    await cubit.close();
    await restored.close();
  });

  testWidgets('tasbih page fits a small screen and increments from the dial', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = TasbihCubit(
      _MemoryStorage(),
      now: () => DateTime(2026, 10, 29),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          home: const TasbihPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('المسبحة'), findsOneWidget);
    expect(find.text('سبحان الله'), findsNWidgets(2));
    expect(find.text('اضغط للتسبيح'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('اضغط للتسبيح'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(cubit.state.count, 1);
    expect(cubit.state.todayTotal, 1);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('مخصص'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'عدد التسبيحات'),
      '12',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(cubit.state.target, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion sound fires once and undo stays in the app bar', (
    tester,
  ) async {
    final cubit = TasbihCubit(
      _MemoryStorage(),
      now: () => DateTime(2026, 10, 29),
    );
    await cubit.setTarget(2);
    addTearDown(cubit.close);
    var completionSounds = 0;

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          home: TasbihPage(onCompletionSound: () => completionSounds++),
        ),
      ),
    );

    expect(find.byTooltip('تراجع عن آخر ضغطة'), findsOneWidget);
    expect(find.text('تراجع عن آخر ضغطة'), findsNothing);

    await tester.tap(find.text('اضغط للتسبيح'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(completionSounds, 0);

    await tester.tap(find.text('اضغط للتسبيح'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(completionSounds, 1);

    await tester.tap(find.text('اضغط للتسبيح'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(completionSounds, 1);

    await tester.tap(find.byTooltip('تراجع عن آخر ضغطة'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(cubit.state.count, 2);
  });

  testWidgets('sound and vibration can be changed from tasbih settings', (
    tester,
  ) async {
    final cubit = TasbihCubit(
      _MemoryStorage(),
      now: () => DateTime(2026, 10, 29),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          home: const TasbihPage(onCompletionSound: _noOp),
        ),
      ),
    );

    await tester.tap(find.byTooltip('إعدادات المسبحة'));
    await tester.pumpAndSettle();
    expect(find.text('صوت عند إتمام الهدف'), findsOneWidget);
    expect(find.text('الاهتزاز مع العد'), findsOneWidget);
    expect(find.text('بدء جلسة جديدة'), findsOneWidget);

    await tester.tap(find.text('صوت عند إتمام الهدف'));
    await tester.pump();
    await tester.tap(find.text('الاهتزاز مع العد'));
    await tester.pump();

    expect(cubit.state.completionSoundEnabled, isFalse);
    expect(cubit.state.hapticsEnabled, isFalse);
  });

  testWidgets('adds and activates a custom dhikr from the selector', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = TasbihCubit(
      _MemoryStorage(),
      now: () => DateTime(2026, 10, 29),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          home: const TasbihPage(),
        ),
      ),
    );

    await tester.tap(find.text('الذكر الحالي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة ذكر مخصص'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'نص الذكر'),
      'أستغفر الله العظيم',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'أو اكتب هدفًا مخصصًا'),
      '25',
    );
    await tester.tap(find.text('إضافة واستخدام الذكر'));
    await tester.pumpAndSettle();

    expect(cubit.state.dhikr.text, 'أستغفر الله العظيم');
    expect(cubit.state.target, 25);
    expect(find.text('أستغفر الله العظيم'), findsNWidgets(2));
  });
}

void _noOp() {}

class _MemoryStorage implements LocalStorageService {
  final _data = <String, dynamic>{};

  void put(String key, Object value) => _data[key] = value;

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
    _data[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _data[key] = List<dynamic>.from(value);
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
