import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

import 'quran_home_hub_test.dart'
    show
        FakeLocationService,
        FakeNotificationService,
        InMemoryLocalStorage,
        TestQuranAudioService;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = QuranRepository();
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

  test(
    'automatic progress cannot skip unread pages, including after reload',
    () async {
      final storage = InMemoryLocalStorage();
      var cubit = KhatmaCubit(storage);
      await cubit.create(name: 'ختمتي', durationDays: 30, startPage: 1);
      final id = cubit.state.active!.id;
      await cubit.recordReadingPosition(
        planId: id,
        currentPage: 2,
        completedThrough: 1,
        requireContiguousProgress: true,
      );
      await cubit.recordReadingPosition(planId: id, currentPage: 10);
      await cubit.close();
      cubit = KhatmaCubit(storage);
      addTearDown(cubit.close);
      await cubit.recordReadingPosition(
        planId: id,
        currentPage: 11,
        completedThrough: 10,
        requireContiguousProgress: true,
      );
      expect(cubit.state.active!.progressPage, 1);
      expect(cubit.state.active!.lastReadPage, 11);
      await cubit.recordReadingPosition(planId: id, currentPage: 2);
      await cubit.recordReadingPosition(
        planId: id,
        currentPage: 3,
        completedThrough: 2,
        requireContiguousProgress: true,
      );
      expect(cubit.state.active!.progressPage, 2);
      await cubit.recordReadingPosition(
        planId: id,
        currentPage: 2,
        completedThrough: 1,
        requireContiguousProgress: true,
      );
      expect(cubit.state.active!.progressPage, 2);
      await cubit.completeToday();
      expect(
        cubit.state.active!.progressPage,
        21,
        reason: 'Explicit completion still confirms the entire portion.',
      );
    },
  );

  test('reset prevents a pending create from restoring the old plan', () async {
    final storage = _DelayedStorage();
    final cubit = KhatmaCubit(storage);
    addTearDown(cubit.close);
    final creating = cubit.create(
      name: 'pending',
      durationDays: 30,
      startPage: 1,
    );
    cubit.resetLocalData();
    storage.release.complete();
    await creating;
    expect(cubit.state.plans, isEmpty);
    expect(cubit.state.activeId, isNull);
  });

  test(
    'reset invalidation suppresses a calendar refresh after a pending write',
    () async {
      final storage = _GatedStorage();
      await storage.writeMap('settings', {'notificationsEnabled': true});
      final notifications = _RecordingNotifications();
      final cubit = KhatmaCubit(storage, notifications: notifications);
      addTearDown(cubit.close);
      await cubit.create(name: 'ختمتي', durationDays: 30, startPage: 1);
      expect(notifications.refreshes, 1);
      storage.gate = Completer<void>();
      final mutation = cubit.togglePause();
      cubit.invalidatePendingOperations();
      storage.gate!.complete();
      await mutation;
      expect(
        notifications.refreshes,
        1,
        reason:
            'A late persistence completion must not requeue cancelled alarms.',
      );

      storage.gate = null;
      cubit.load();
      await cubit.togglePause();
      expect(
        notifications.refreshes,
        2,
        reason: 'Reloading after a failed reset restores normal scheduling.',
      );
    },
  );

  testWidgets(
    'reader jumps never complete crossed pages; returning resumes contiguous progress',
    (tester) async {
      final storage = InMemoryLocalStorage();
      final khatma = KhatmaCubit(storage);
      await khatma.create(
        name: 'اختبار القراءة',
        durationDays: 30,
        startPage: 1,
      );
      final id = khatma.state.active!.id;
      await khatma.recordProgress(1);
      final quran = QuranCubit(
        repository: repository,
        storage: storage,
        audio: TestQuranAudioService(),
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quran.load();
      await quran.openPage(2);
      final settings = SettingsCubit(
        storage: storage,
        locationService: FakeLocationService(),
        notifications: FakeNotificationService(),
      );
      await settings.load();
      addTearDown(() async {
        await quran.close();
        await khatma.close();
        await settings.close();
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: quran),
            BlocProvider.value(value: khatma),
            BlocProvider.value(value: settings),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: QuranReaderPage(
              khatmaPlanId: id,
              khatmaPlanName: 'اختبار القراءة',
              khatmaStartPage: 2,
              khatmaTargetPage: 21,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exercise the actual direct-jump field, including frame-by-frame checks
      // across the interval previously used to animate intermediate pages.
      await tester.tap(find.text('صفحة 2'));
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'انتقال مباشر إلى صفحة',
      );
      await tester.enterText(input, '10');
      await tester.tap(
        find.descendant(of: input, matching: find.byType(IconButton)),
      );
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(khatma.state.active!.progressPage, 1);
      }
      await tester.pumpAndSettle();
      expect(quran.state.currentPage, 10);
      await tester.tap(find.byTooltip('الصفحة التالية'));
      await tester.pumpAndSettle();
      expect(quran.state.currentPage, 11);
      expect(khatma.state.active!.progressPage, 1);

      await quran.openPage(2);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('الصفحة التالية'));
      await tester.pumpAndSettle();
      expect(khatma.state.active!.progressPage, 2);
      await tester.tap(find.byTooltip('الصفحة السابقة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('الصفحة التالية'));
      await tester.pumpAndSettle();
      expect(khatma.state.active!.progressPage, 2);
      await tester.tap(find.byTooltip('الصفحة التالية'));
      await tester.pumpAndSettle();
      expect(khatma.state.active!.progressPage, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}

class _DelayedStorage extends InMemoryLocalStorage {
  final release = Completer<void>();

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    await release.future;
    await super.writeMap(key, value);
  }
}

class _GatedStorage extends InMemoryLocalStorage {
  Completer<void>? gate;

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    await super.writeMap(key, value);
    await gate?.future;
  }
}

class _RecordingNotifications extends LocalNotificationService {
  int refreshes = 0;

  @override
  Future<void> scheduleAll(List<ScheduledAppNotification> notifications) async {
    refreshes++;
  }
}
