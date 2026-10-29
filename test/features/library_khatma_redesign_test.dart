import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/khatma/data/models/khatma_plan.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';
import 'package:mishkat_app/features/khatma/presentation/pages/khatma_page.dart';
import 'package:mishkat_app/features/library/data/models/library_models.dart';
import 'package:mishkat_app/features/library/data/repositories/library_repository.dart';
import 'package:mishkat_app/features/library/presentation/cubit/library_cubit.dart';
import 'package:mishkat_app/features/library/presentation/pages/library_page.dart';
import 'package:mishkat_app/features/library/presentation/pages/library_reader_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryRepository repository;
  late List<LibraryBook> catalog;

  setUpAll(() async {
    repository = LibraryRepository();
    catalog = await repository.loadCatalog();
  });

  test('catalog includes complete core Islamic books and tafsir', () async {
    expect(catalog, hasLength(8));
    expect(
      catalog.map((book) => book.title),
      containsAll([
        'صحيح البخاري',
        'صحيح مسلم',
        'رياض الصالحين',
        'الأربعون النووية',
        'بلوغ المرام',
        'الشمائل المحمدية',
        'حصن المسلم',
        'التفسير الميسر',
      ]),
    );

    final bukhari = catalog.singleWhere((book) => book.id == 'bukhari');
    final hisn = catalog.singleWhere((book) => book.id == 'hisn');
    final nawawi = catalog.singleWhere((book) => book.id == 'nawawi40');
    final tafsir = catalog.singleWhere((book) => book.id == 'tafsir-muyassar');
    expect(await repository.loadBook(bukhari), hasLength(7252));
    expect(await repository.loadBook(hisn), hasLength(268));
    expect(await repository.loadBook(nawawi), hasLength(42));
    final tafsirEntries = await repository.loadBook(tafsir);
    expect(tafsirEntries, hasLength(6236));
    expect(tafsirEntries.first.chapter, contains('فَاتِحَة'));
  });

  test('reading position and bookmarks survive a cubit reload', () async {
    final storage = _MemoryStorage();
    final first = LibraryCubit(repository, storage);
    await first.load();
    final nawawi = first.state.books.singleWhere(
      (book) => book.id == 'nawawi40',
    );
    await first.openBook(nawawi);
    await first.saveReadingPosition(nawawi.id, first.state.entries[5].id);
    await first.toggleBookmark(nawawi.id, first.state.entries[5].id);
    await first.close();

    final restored = LibraryCubit(repository, storage);
    await restored.load();
    await restored.openBook(nawawi);
    expect(restored.readingIndexFor(nawawi.id), 5);
    expect(
      restored.isBookmarked(nawawi.id, restored.state.entries[5].id),
      isTrue,
    );
    await restored.close();
  });

  test('creates, advances, pauses and resumes a khatma plan', () async {
    final cubit = KhatmaCubit(_MemoryStorage());
    await cubit.create(
      name: 'ختمة شهر',
      durationDays: 30,
      startPage: 1,
      reminderPrayer: 'fajr',
    );
    expect(cubit.state.active?.dailyPages, 21);
    expect(
      cubit.state.active?.targetDate
          .difference(cubit.state.active!.startDate)
          .inDays,
      29,
    );

    await cubit.completeToday();
    expect(cubit.state.active?.progressPage, 21);
    await cubit.togglePause();
    expect(cubit.state.active?.status, KhatmaStatus.paused);
    await cubit.togglePause();
    expect(cubit.state.active?.status, KhatmaStatus.active);
    await cubit.close();
  });

  test('khatma reading position and live progress survive a reload', () async {
    final storage = _MemoryStorage();
    final first = KhatmaCubit(storage);
    await first.create(name: 'ختمتي التفاعلية', durationDays: 30, startPage: 1);
    final planId = first.state.active!.id;

    await first.recordReadingPosition(planId: planId, currentPage: 1);
    await first.recordReadingPosition(
      planId: planId,
      currentPage: 2,
      completedThrough: 1,
    );

    expect(first.state.active?.progressPage, 1);
    expect(first.state.active?.completedPages, 1);
    expect(first.state.active?.lastReadPage, 2);
    expect(first.state.active?.resumePage, 2);
    expect(first.state.active?.todayEnd, 21);
    await first.close();

    final restored = KhatmaCubit(storage);
    expect(restored.state.active?.progressPage, 1);
    expect(restored.state.active?.lastReadPage, 2);
    expect(restored.state.active?.resumePage, 2);
    expect(restored.state.active?.todayEnd, 21);

    // Opening an arbitrary page saves the position without falsely counting
    // skipped pages as completed.
    await restored.recordReadingPosition(planId: planId, currentPage: 10);
    expect(restored.state.active?.progressPage, 1);
    expect(restored.state.active?.lastReadPage, 10);

    await restored.recordReadingPosition(
      planId: planId,
      currentPage: 21,
      completedThrough: 21,
    );
    expect(restored.state.active?.nextPage, 22);
    expect(restored.state.active?.todayEnd, 42);
    await restored.close();
  });

  testWidgets('library overview remains usable on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = LibraryCubit(_PreparedRepository(catalog), _MemoryStorage());
    await cubit.load();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          home: const Scaffold(body: LibraryPage()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('المكتبة الإسلامية'), findsOneWidget);
    expect(find.textContaining('8 كتب'), findsOneWidget);
    expect(find.text('صحيح البخاري'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hisn al-Muslim opens from the library into the reader', (
    tester,
  ) async {
    final cubit = LibraryCubit(repository, _MemoryStorage());
    await cubit.load();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          home: const Scaffold(body: LibraryPage()),
        ),
      ),
    );
    await tester.pump();

    final hisnTitle = find.text('حصن المسلم');
    await tester.scrollUntilVisible(
      hisnTitle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(hisnTitle);
    await tester.pumpAndSettle();

    expect(find.byType(LibraryReaderPage), findsOneWidget);
    expect(find.text('ذكر 1 من 268'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('khatma onboarding and plan builder fit a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = KhatmaCubit(_MemoryStorage());
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          home: const Scaffold(body: KhatmaPage()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ابدأ رحلة ختمة جديدة'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pump();
    await tester.tap(find.text('إنشاء خطة مخصصة'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('أنشئ خطة ختمتك'), findsOneWidget);
    expect(find.textContaining('وردك:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PreparedRepository extends LibraryRepository {
  _PreparedRepository(this.books);
  final List<LibraryBook> books;

  @override
  Future<List<LibraryBook>> loadCatalog() => SynchronousFuture(books);
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
    _data[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _data[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();
}
