import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/adhkar/data/models/adhkar_models.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';
import 'package:mishkat_app/features/adhkar/presentation/pages/adhkar_page.dart';
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
      expect(morning.items, hasLength(23));
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
