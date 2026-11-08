import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/app_data_reset_service.dart';
import 'package:mishkat_app/core/services/home_widget_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/reminder_navigation.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';
import 'package:mishkat_app/features/home/presentation/cubit/home_cubit.dart';
import 'package:mishkat_app/features/home/presentation/pages/friday_dua_reminder_page.dart';
import 'package:mishkat_app/features/home/presentation/pages/home_page.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';
import 'package:mishkat_app/features/library/data/repositories/library_repository.dart';
import 'package:mishkat_app/features/library/presentation/cubit/library_cubit.dart';
import 'package:mishkat_app/features/qibla/presentation/cubit/qibla_cubit.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/shell/presentation/cubit/shell_cubit.dart';
import 'package:mishkat_app/features/shell/presentation/pages/app_shell.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/pages/tasbih_page.dart';

import 'home_my_duas_test.dart'
    show
        FakeAdhkarRepository,
        FakeLocalStorageService,
        FakeLocationService,
        FakeNotificationService,
        FakeQuranAudioService;

class _GatedQuranRepository extends QuranRepository {
  final gate = Completer<QuranData>();
  int loadCalls = 0;

  @override
  Future<QuranData> load() {
    loadCalls++;
    return gate.future;
  }
}

class _ResetState extends ChangeNotifier implements AppDataResetService {
  @override
  bool isResetting = false;
  @override
  int generation = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedReadingStorage extends FakeLocalStorageService {
  Completer<void>? readingWriteGate;
  Completer<void>? readingWriteStarted;

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) {
    final writing = super.writeMap(key, value);
    final gate = readingWriteGate;
    if (key != 'quran' || gate == null) return writing;
    return writing.then((_) {
      readingWriteStarted?.complete();
      return gate.future;
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = QuranRepository();
  late _GatedReadingStorage storage;
  late SettingsCubit settings;
  late HomeCubit home;
  late AdhkarCubit adhkar;
  late QuranCubit quran;
  late FakeQuranAudioService audio;
  late TasbihCubit tasbih;
  late KhatmaCubit khatma;
  late LibraryCubit library;
  late QiblaCubit qibla;
  late ShellCubit shell;
  late DateTime now;

  setUpAll(() async {
    await repository.load();
    await MushafLayoutRepository.instance.load();
  });

  setUp(() async {
    notificationTapPayload.value = null;
    homeWidgetLaunchUri.value = null;
    storage = _GatedReadingStorage();
    await storage.writeMap(
      'settings',
      const AppSettings(onboardingSeen: true).toJson(),
    );
    settings = SettingsCubit(
      storage: storage,
      locationService: FakeLocationService(),
      notifications: FakeNotificationService(),
    );
    await settings.load();
    now = DateTime(2026, 11, 6, 9);
    home = HomeCubit(settings.state.settings, now: () => now);
    adhkar = AdhkarCubit(FakeAdhkarRepository(), storage);
    await adhkar.load();
    audio = FakeQuranAudioService();
    quran = QuranCubit(
      repository: repository,
      storage: storage,
      audio: audio,
      reciter: 'ar.alafasy',
      fontSize: 32,
    );
    await quran.load();
    tasbih = TasbihCubit(storage);
    khatma = KhatmaCubit(storage);
    library = LibraryCubit(LibraryRepository(), storage);
    await library.load();
    qibla = QiblaCubit();
    shell = ShellCubit();
  });

  tearDown(() async {
    notificationTapPayload.value = null;
    homeWidgetLaunchUri.value = null;
    await home.close();
    await settings.close();
    await adhkar.close();
    await quran.close();
    await audio.dispose();
    await tasbih.close();
    await khatma.close();
    await library.close();
    await qibla.close();
    await shell.close();
  });

  Future<void> openHome(
    WidgetTester tester, {
    bool dark = false,
    bool withShell = false,
    bool settle = true,
    double width = 390,
    AppDataResetService? resetService,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          if (resetService != null)
            RepositoryProvider<AppDataResetService>.value(value: resetService),
          BlocProvider.value(value: settings),
          BlocProvider.value(value: home),
          BlocProvider.value(value: adhkar),
          BlocProvider.value(value: quran),
          BlocProvider.value(value: tasbih),
          BlocProvider.value(value: khatma),
          BlocProvider.value(value: library),
          BlocProvider.value(value: qibla),
          BlocProvider.value(value: shell),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: withShell ? const AppShell() : const HomePage(),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  Future<_GatedQuranRepository> prepareColdQuran(WidgetTester tester) async {
    // The setup cubit's subscriptions belong to the real async zone. Dispose
    // there before creating a fresh gated cubit in the widget-test zone.
    await tester.runAsync(() async {
      await quran.close();
      audio = FakeQuranAudioService();
    });
    final gated = _GatedQuranRepository();
    quran = QuranCubit(
      repository: gated,
      storage: storage,
      audio: audio,
      reciter: 'ar.alafasy',
      fontSize: 32,
    );
    return gated;
  }

  testWidgets(
    'Kahf shortcut appears throughout Friday and changes at midnight',
    (tester) async {
      now = DateTime(2026, 11, 5, 23, 59);
      await tester.runAsync(home.close);
      // Exercise the real periodic refresh with a timer owned by FakeAsync.
      home = HomeCubit(settings.state.settings, now: () => now);
      await openHome(tester);
      expect(find.byKey(const ValueKey('friday-kahf-button')), findsNothing);

      for (final time in [
        DateTime(2026, 11, 6),
        DateTime(2026, 11, 6, 9),
        DateTime(2026, 11, 6, 12),
        DateTime(2026, 11, 6, 18),
        DateTime(2026, 11, 6, 23, 59, 59),
      ]) {
        now = time;
        await tester.pump(const Duration(seconds: 15));
        await tester.pumpAndSettle();
        expect(home.state.now, time);
        expect(find.text('اقرأ سورة الكهف'), findsOneWidget, reason: '$time');
      }

      now = DateTime(2026, 11, 7);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('friday-kahf-button')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(home.close);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('Friday CTA opens the first ayah of Kahf, dark=$dark', (
      tester,
    ) async {
      await quran.openPage(500);
      await openHome(tester, dark: dark, width: 320);
      final button = find.byKey(const ValueKey('friday-kahf-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final data = quran.state.data!;
      final firstAyah = data.globalFor(18, 1);
      expect(quran.state.currentPage, data.pageForGlobal(firstAyah));
      expect(quran.state.lastRead?.surah, 18);
      expect(quran.state.lastRead?.ayah, 1);
      expect(
        tester
            .widget<QuranReaderPage>(find.byType(QuranReaderPage))
            .initialGlobalAyah,
        firstAyah,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final fromLaunch in [true, false]) {
    testWidgets(
      'Kahf notification routes through AppShell, launch=$fromLaunch',
      (tester) async {
        await quran.openPage(500);
        if (fromLaunch) notificationTapPayload.value = 'quran:kahf';
        await openHome(tester, withShell: true);
        if (!fromLaunch) notificationTapPayload.value = 'quran:kahf';
        await tester.pumpAndSettle();
        final firstAyah = quran.state.data!.globalFor(18, 1);
        expect(find.byType(QuranReaderPage), findsOneWidget);
        expect(quran.state.lastRead?.global, firstAyah);
        expect(notificationTapPayload.value, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('cold Kahf notification waits for the existing Quran load', (
    tester,
  ) async {
    await storage.writeMap('quran', {'currentPage': 500});
    final gated = await prepareColdQuran(tester);
    final initialLoad = quran.load();
    notificationTapPayload.value = 'quran:kahf';
    await openHome(tester, withShell: true, settle: false);
    expect(gated.loadCalls, 1);
    expect(find.byType(QuranReaderPage), findsNothing);

    final data = await repository.load();
    gated.gate.complete(data);
    await initialLoad;
    await tester.pumpAndSettle();
    expect(gated.loadCalls, 1);
    expect(quran.state.currentPage, data.pageForGlobal(data.globalFor(18, 1)));
    expect(quran.state.lastRead?.surah, 18);
    expect(quran.state.lastRead?.ayah, 1);
    expect(find.byType(QuranReaderPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed cold Quran load shows a useful Kahf message', (
    tester,
  ) async {
    final gated = await prepareColdQuran(tester);
    final initialLoad = quran.load();
    notificationTapPayload.value = 'quran:kahf';
    await openHome(tester, withShell: true, settle: false);
    gated.gate.completeError(StateError('Quran assets unavailable'));
    await initialLoad;
    await tester.pumpAndSettle();
    expect(gated.loadCalls, 1);
    expect(find.byType(QuranReaderPage), findsNothing);
    expect(
      find.text('تعذّر فتح سورة الكهف الآن. حاول مجددًا.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final resetAlreadyCompleted in [false, true]) {
    testWidgets(
      'pending Kahf notification cannot restore reading data after reset, completed=$resetAlreadyCompleted',
      (tester) async {
        final data = await repository.load();
        await storage.writeMap('quran', {'currentPage': 500});
        final gated = await prepareColdQuran(tester);
        final initialLoad = quran.load();
        final reset = _ResetState();
        addTearDown(reset.dispose);
        notificationTapPayload.value = 'quran:kahf';
        await openHome(
          tester,
          withShell: true,
          settle: false,
          resetService: reset,
        );
        expect(gated.loadCalls, 1);
        expect(find.byType(QuranReaderPage), findsNothing);

        // Keep the original caller mounted to exercise the reset guard itself,
        // rather than relying on a later root-widget replacement to cancel it.
        reset.isResetting = true;
        quran.invalidatePendingOperations();
        await storage.clear();
        quran.resetLocalData(reciter: 'ar.alafasy', fontSize: 32);
        final reload = quran.load();
        if (resetAlreadyCompleted) {
          reset.generation++;
          reset.isResetting = false;
        }
        gated.gate.complete(data);
        await initialLoad;
        await reload;
        await tester.pumpAndSettle();

        expect(find.byType(QuranReaderPage), findsNothing);
        expect(quran.state.currentPage, 1);
        expect(quran.state.lastRead, isNull);
        expect(
          storage.readMap('quran'),
          isEmpty,
          reason:
              'The cancelled notification must not write the Kahf position.',
        );
        expect(notificationTapPayload.value, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Kahf wait does not navigate after the caller is unmounted', (
    tester,
  ) async {
    final gated = await prepareColdQuran(tester);
    final initialLoad = quran.load();
    await openHome(tester);
    final navigation = ReminderNavigation.open(
      tester.element(find.byType(HomePage)),
      'quran:kahf',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    gated.gate.complete(await repository.load());
    await initialLoad;
    await navigation;
    expect(gated.loadCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending wird widget cannot open its old plan after reset completes',
    (tester) async {
      await khatma.create(name: 'ختمتي', durationDays: 30, startPage: 1);
      await khatma.recordProgress(1);
      await quran.openPage(500);
      final reset = _ResetState();
      addTearDown(reset.dispose);
      await openHome(tester, withShell: true, resetService: reset);

      storage.readingWriteGate = Completer<void>();
      storage.readingWriteStarted = Completer<void>();
      homeWidgetLaunchUri.value = Uri.parse('mishkat://wird');
      await tester.pump();
      await storage.readingWriteStarted!.future;
      expect(quran.state.currentPage, 2);
      expect(find.byType(QuranReaderPage), findsNothing);

      reset.isResetting = true;
      await storage.clear();
      quran.resetLocalData(reciter: 'ar.alafasy', fontSize: 32);
      khatma.resetLocalData();
      reset.generation++;
      reset.isResetting = false;
      storage.readingWriteGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(QuranReaderPage), findsNothing);
      expect(quran.state.currentPage, 1);
      expect(quran.state.lastRead, isNull);
      expect(storage.readMap('quran'), isEmpty);
      expect(homeWidgetLaunchUri.value, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Friday dua and salawat notifications open relevant content', (
    tester,
  ) async {
    await openHome(tester, withShell: true);
    notificationTapPayload.value = 'friday:dua';
    await tester.pumpAndSettle();
    expect(find.byType(FridayDuaReminderPage), findsOneWidget);
    expect(find.text('ساعة تُرجى فيها الإجابة'), findsOneWidget);

    notificationTapPayload.value = 'tasbih:salawat';
    await tester.pumpAndSettle();
    expect(find.byType(FridayDuaReminderPage), findsNothing);
    expect(find.byType(TasbihPage), findsOneWidget);
    expect(tasbih.state.dhikrId, 'salawat');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unknown Friday destinations do not open unrelated content', (
    tester,
  ) async {
    await openHome(tester);
    final context = tester.element(find.byType(HomePage));
    await ReminderNavigation.open(context, 'quran:invalid');
    await ReminderNavigation.open(context, 'friday:invalid');
    await tester.pumpAndSettle();
    expect(find.byType(QuranReaderPage), findsNothing);
    expect(find.byType(FridayDuaReminderPage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
