import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/mushaf_layout_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/mushaf_interaction_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_coordinate_mapper.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/ayah_action_sheet.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_interaction_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MushafLayoutRepository layoutRepo;
  late QuranRepository quranRepo;
  late QuranData quranData;
  const mapper = MushafCoordinateMapper();

  setUpAll(() async {
    layoutRepo = MushafLayoutRepository();
    await layoutRepo.load();
    quranRepo = QuranRepository();
    quranData = await quranRepo.load();
  });

  group('MushafCoordinateMapper - Unit Tests', () {
    test(
      'Standard page viewBox (345x550) destination rect maintains aspect ratio',
      () {
        const viewBox = Rect.fromLTWH(0, 0, 345, 550);
        const contentSize = Size(400, 800);
        final destRect = mapper.getSvgDestinationRect(
          contentSize: contentSize,
          viewBox: viewBox,
        );

        // Available size = 400 - 16 = 384, 800 - 16 = 784
        // Aspect ratio: 345 / 550 = 0.62727
        // 384 / 0.62727 = 612.174 < 784 => Width constrained
        expect(destRect.width, closeTo(384.0, 1e-2));
        expect(destRect.height, closeTo(384.0 * (550 / 345), 1e-2));
        // Centered vertically inside [8, 8, 384, 784]
        expect(destRect.left, 8.0);
        expect(destRect.top, greaterThan(8.0));
      },
    );

    test(
      'Ornamental page viewBox (Pages 1-2: offset origin) preserves dimensions',
      () {
        const viewBox = Rect.fromLTWH(-53.3109, -198.4777, 345, 550);
        const contentSize = Size(360, 700);
        final destRect = mapper.getSvgDestinationRect(
          contentSize: contentSize,
          viewBox: viewBox,
        );

        expect(destRect.width, greaterThan(0));
        expect(destRect.height, greaterThan(0));
        expect(destRect.width / destRect.height, closeTo(345 / 550, 1e-3));
      },
    );

    test('Round-trip coordinate transformation: viewBox -> local -> viewBox is exact', () {
      const viewBox = Rect.fromLTWH(0, 0, 345, 550);
      const contentSize = Size(390, 844);

      // Test multiple points across the SVG
      final testPoints = [
        const Offset(10.0, 20.0),
        const Offset(172.5, 275.0),
        const Offset(330.0, 520.0),
      ];

      for (final pt in testPoints) {
        final local = mapper.viewBoxToLocal(
          viewBoxCoordinate: pt,
          contentSize: contentSize,
          viewBox: viewBox,
        );
        final roundTrip = mapper.localToViewBox(
          localPosition: local,
          contentSize: contentSize,
          viewBox: viewBox,
        );
        expect(roundTrip, isNotNull);
        expect(roundTrip!.dx, closeTo(pt.dx, 1e-2));
        expect(roundTrip.dy, closeTo(pt.dy, 1e-2));
      }
    });

    test(
      'Round-trip coordinate transformation on Page 1 offset viewBox is exact',
      () {
        const viewBox = Rect.fromLTWH(-53.3109, -198.4777, 345, 550);
        const contentSize = Size(430, 932);

        final testPoints = [
          const Offset(0.0, 0.0),
          const Offset(-40.0, -180.0),
          const Offset(100.0, 50.0),
          const Offset(250.0, 300.0),
        ];

        for (final pt in testPoints) {
          final local = mapper.viewBoxToLocal(
            viewBoxCoordinate: pt,
            contentSize: contentSize,
            viewBox: viewBox,
          );
          final roundTrip = mapper.localToViewBox(
            localPosition: local,
            contentSize: contentSize,
            viewBox: viewBox,
          );
          expect(roundTrip, isNotNull);
          expect(roundTrip!.dx, closeTo(pt.dx, 1e-2));
          expect(roundTrip.dy, closeTo(pt.dy, 1e-2));
        }
      },
    );

    test('Taps in empty letterbox margins return null (no false hits)', () {
      const viewBox = Rect.fromLTWH(0, 0, 345, 550);
      // Tall phone: heavy vertical letterboxing
      const contentSize = Size(360, 900);
      final destRect = mapper.getSvgDestinationRect(
        contentSize: contentSize,
        viewBox: viewBox,
      );

      // Tap way above the rendered SVG
      final topMarginTap = Offset(destRect.center.dx, destRect.top - 20);
      final topResult = mapper.localToViewBox(
        localPosition: topMarginTap,
        contentSize: contentSize,
        viewBox: viewBox,
      );
      expect(topResult, isNull);

      // Tap way below the rendered SVG
      final bottomMarginTap = Offset(destRect.center.dx, destRect.bottom + 20);
      final bottomResult = mapper.localToViewBox(
        localPosition: bottomMarginTap,
        contentSize: contentSize,
        viewBox: viewBox,
      );
      expect(bottomResult, isNull);
    });
  });

  group('MushafInteractionCubit - Lifecycle & Selection', () {
    late MushafInteractionCubit cubit;

    setUp(() {
      cubit = MushafInteractionCubit(layoutRepository: layoutRepo);
    });

    tearDown(() {
      cubit.close();
    });

    test('initial state has no selection', () {
      expect(cubit.state.hasSelection, isFalse);
      expect(cubit.state.selectedAyah, isNull);
      expect(cubit.state.selectedPage, isNull);
      expect(cubit.state.isActionSheetOpen, isFalse);
      expect(cubit.state.playingAyah, isNull);
    });

    test('selectAyah updates state accurately', () {
      final ayah = layoutRepo.getAyah(1)!;
      cubit.selectAyah(ayah);

      expect(cubit.state.hasSelection, isTrue);
      expect(cubit.state.selectedAyah, ayah);
      expect(cubit.state.selectedPage, 1);
      expect(cubit.state.isActionSheetOpen, isFalse);
    });

    test('selectAyahByGlobal resolves geometry and selects', () {
      cubit.selectAyahByGlobal(8); // 2:1 on page 2

      expect(cubit.state.hasSelection, isTrue);
      expect(cubit.state.selectedAyah!.globalAyah, 8);
      expect(cubit.state.selectedPage, 2);
    });

    test('selectAyah with openActionSheet opens action sheet flag', () {
      final ayah = layoutRepo.getAyah(255)!;
      cubit.selectAyah(ayah, openActionSheet: true);

      expect(cubit.state.isActionSheetOpen, isTrue);
      expect(cubit.state.selectedAyah!.globalAyah, 255);
    });

    test('clearSelection clears selection and resets action sheet', () {
      final ayah = layoutRepo.getAyah(1)!;
      cubit.selectAyah(ayah, openActionSheet: true);
      cubit.clearSelection();

      expect(cubit.state.hasSelection, isFalse);
      expect(cubit.state.selectedAyah, isNull);
      expect(cubit.state.isActionSheetOpen, isFalse);
    });

    test(
      'onPageChanged clears selection when navigating to different page',
      () {
        final ayah = layoutRepo.getAyah(1)!; // page 1
        cubit.selectAyah(ayah);

        // Navigate to page 1: selection preserved
        cubit.onPageChanged(1);
        expect(cubit.state.hasSelection, isTrue);

        // Navigate to page 2: selection cleared
        cubit.onPageChanged(2);
        expect(cubit.state.hasSelection, isFalse);
      },
    );

    test('setPlayingAyah manages playing state separately from selection (Q5 foundation)', () {
      final ayah1 = layoutRepo.getAyah(1)!;
      cubit.selectAyah(ayah1);
      cubit.setPlayingAyah(2);

      expect(cubit.state.selectedAyah!.globalAyah, 1);
      expect(cubit.state.playingAyah, 2);

      cubit.setPlayingAyah(null);
      expect(cubit.state.playingAyah, isNull);
      expect(cubit.state.selectedAyah!.globalAyah, 1);
    });
  });

  group('MushafInteractionLayer - Widget & Hit-Testing Interactions', () {
    testWidgets('Tap on Ayah selects it via MushafInteractionCubit', (
      tester,
    ) async {
      final cubit = MushafInteractionCubit(layoutRepository: layoutRepo);
      const contentSize = Size(360, 600);
      final pageGeom = layoutRepo.getPageGeometry(3)!;
      final ayah13 = layoutRepo.getAyah(13)!; // 2:6 on page 3

      // Convert Ayah 13 samplePoint to local widget coordinate
      final localTouchPoint = mapper.viewBoxToLocal(
        viewBoxCoordinate: ayah13.samplePoint,
        contentSize: contentSize,
        viewBox: pageGeom.viewBox,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: SizedBox(
                width: contentSize.width,
                height: contentSize.height,
                child: MushafInteractionLayer(
                  page: 3,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      // Tap on the Ayah 13 location
      await tester.tapAt(localTouchPoint);
      await tester.pumpAndSettle();

      expect(cubit.state.hasSelection, isTrue);
      expect(cubit.state.selectedAyah!.globalAyah, 13);
      expect(cubit.state.isActionSheetOpen, isFalse);

      cubit.close();
    });

    testWidgets('Tap on empty area clears selection', (tester) async {
      final cubit = MushafInteractionCubit(layoutRepository: layoutRepo);
      const contentSize = Size(360, 600);
      final pageGeom = layoutRepo.getPageGeometry(3)!;
      final ayah13 = layoutRepo.getAyah(13)!;
      cubit.selectAyah(ayah13);

      final destRect = mapper.getSvgDestinationRect(
        contentSize: contentSize,
        viewBox: pageGeom.viewBox,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: SizedBox(
                width: contentSize.width,
                height: contentSize.height,
                child: MushafInteractionLayer(
                  page: 3,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      // Tap in empty top letterbox margin (destRect.top is ~25.8)
      await tester.tapAt(Offset(destRect.center.dx, destRect.top - 12));
      await tester.pumpAndSettle();

      expect(cubit.state.hasSelection, isFalse);

      cubit.close();
    });

    testWidgets('Long press on Ayah selects it and requests Action Sheet', (
      tester,
    ) async {
      final cubit = MushafInteractionCubit(layoutRepository: layoutRepo);
      const contentSize = Size(360, 600);
      final pageGeom = layoutRepo.getPageGeometry(3)!;
      final ayah14 = layoutRepo.getAyah(14)!;

      final localTouchPoint = mapper.viewBoxToLocal(
        viewBoxCoordinate: ayah14.samplePoint,
        contentSize: contentSize,
        viewBox: pageGeom.viewBox,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: SizedBox(
                width: contentSize.width,
                height: contentSize.height,
                child: MushafInteractionLayer(
                  page: 3,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      // Long press on Ayah 14 location
      await tester.longPressAt(localTouchPoint);
      await tester.pumpAndSettle();

      expect(cubit.state.hasSelection, isTrue);
      expect(cubit.state.selectedAyah!.globalAyah, 14);
      expect(cubit.state.isActionSheetOpen, isTrue);

      cubit.close();
    });

    testWidgets('Long press on empty area does NOT open Action Sheet', (
      tester,
    ) async {
      final cubit = MushafInteractionCubit(layoutRepository: layoutRepo);
      const contentSize = Size(360, 600);
      final pageGeom = layoutRepo.getPageGeometry(3)!;
      final destRect = mapper.getSvgDestinationRect(
        contentSize: contentSize,
        viewBox: pageGeom.viewBox,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: SizedBox(
                width: contentSize.width,
                height: contentSize.height,
                child: MushafInteractionLayer(
                  page: 3,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      // Long press in empty margin
      await tester.longPressAt(Offset(destRect.center.dx, destRect.top - 12));
      await tester.pumpAndSettle();

      expect(cubit.state.isActionSheetOpen, isFalse);
      expect(cubit.state.hasSelection, isFalse);

      cubit.close();
    });

    testWidgets('Double tap triggers onDoubleTap callback (zoom reset)', (
      tester,
    ) async {
      final cubit = MushafInteractionCubit(layoutRepository: layoutRepo);
      var doubleTapCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: SizedBox(
                width: 360,
                height: 600,
                child: MushafInteractionLayer(
                  page: 3,
                  onDoubleTap: () => doubleTapCalled = true,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tapAt(const Offset(180, 300));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(180, 300));
      await tester.pumpAndSettle();

      expect(doubleTapCalled, isTrue);

      cubit.close();
    });
  });

  group('AyahActionSheet - UI & Actions', () {
    testWidgets('renders Surah, Ayah number, Arabic text, and action buttons', (
      tester,
    ) async {
      final ayah1 = layoutRepo.getAyah(1)!; // 1:1 Al-Fatihah
      final storage = LocalStorageService();
      final audioService = QuranAudioService();
      final quranCubit = QuranCubit(
        repository: quranRepo,
        storage: storage,
        audio: audioService,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: quranCubit,
              child: AyahActionSheet(ayah: ayah1, quranData: quranData),
            ),
          ),
        ),
      );

      // Verify Context
      expect(find.text('سورة ${quranData.chapter(1).name}'), findsOneWidget);
      expect(find.textContaining('الآية 1'), findsOneWidget);
      expect(find.textContaining('صفحة 1'), findsOneWidget);

      // Verify Arabic text
      expect(
        find.text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ'),
        findsOneWidget,
      );

      // Verify Actions
      expect(find.text('تشغيل التلاوة'), findsOneWidget);
      expect(find.text('نسخ'), findsOneWidget);
      expect(find.text('التفسير'), findsOneWidget);
      expect(find.text('حفظ'), findsOneWidget);
      expect(
        find.byIcon(Icons.bookmark_border_rounded),
        findsOneWidget,
      ); // Live bookmark action in Q7
    });
  });

  group('Special Geometry Validation (Pages 1 & 2)', () {
    test('Page 1 polygon Ayahs transform cleanly to local paths', () {
      const contentSize = Size(360, 600);
      final p1 = layoutRepo.getPageGeometry(1)!;
      final ayah4 = layoutRepo.getAyah(4)!;

      final polySegment = ayah4.segments.firstWhere(
        (s) => s is AyahPolygonSegment,
      ) as AyahPolygonSegment;
      final localPath = mapper.viewBoxPathToLocal(
        points: polySegment.points,
        contentSize: contentSize,
        viewBox: p1.viewBox,
      );

      expect(localPath, isNotNull);
      final bounds = localPath.getBounds();
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
    });

    test('Page 2 polygon Ayahs transform cleanly to local paths', () {
      const contentSize = Size(400, 750);
      final p2 = layoutRepo.getPageGeometry(2)!;
      final ayah9 = layoutRepo.getAyah(9)!;

      final polySegment = ayah9.segments.firstWhere(
        (s) => s is AyahPolygonSegment,
      ) as AyahPolygonSegment;
      final localPath = mapper.viewBoxPathToLocal(
        points: polySegment.points,
        contentSize: contentSize,
        viewBox: p2.viewBox,
      );

      final bounds = localPath.getBounds();
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
    });
  });

  group('Full 6,236 Ayah Regression Through Coordinate Mapping', () {
    test('every single Ayah (1..6236) round-trips through coordinate mapping into hit-testing', () {
      const contentSize = Size(390, 800);

      for (var g = 1; g <= 6236; g++) {
        final ayah = layoutRepo.getAyah(g)!;
        final pageGeom = layoutRepo.getPageGeometry(ayah.page)!;

        // 1. Convert native viewBox samplePoint to rendered local coordinate
        final localPoint = mapper.viewBoxToLocal(
          viewBoxCoordinate: ayah.samplePoint,
          contentSize: contentSize,
          viewBox: pageGeom.viewBox,
        );

        // 2. Map back from rendered local coordinate to native viewBox coordinate
        final viewBoxCoord = mapper.localToViewBox(
          localPosition: localPoint,
          contentSize: contentSize,
          viewBox: pageGeom.viewBox,
        );

        expect(
          viewBoxCoord,
          isNotNull,
          reason: 'Failed localToViewBox for Ayah $g',
        );

        // 3. Hit-test against pre-computed geometry
        final hit = pageGeom.findAyahAt(viewBoxCoord!);
        expect(
          hit,
          isNotNull,
          reason: 'Hit test returned null for Ayah $g on page ${ayah.page}',
        );
        expect(
          hit!.globalAyah,
          g,
          reason:
              'Hit test returned wrong Ayah ${hit.globalAyah} instead of $g',
        );
      }
    });
  });

  group('Responsive Widths & Theme Validation', () {
    final testWidths = [320.0, 360.0, 390.0, 430.0, 768.0, 1024.0];

    for (final width in testWidths) {
      test('Destination rect is valid and non-overflowing at width $width', () {
        final contentSize = Size(width, 700);
        const viewBox = Rect.fromLTWH(0, 0, 345, 550);
        final dest = mapper.getSvgDestinationRect(
          contentSize: contentSize,
          viewBox: viewBox,
        );

        expect(dest.left, greaterThanOrEqualTo(8.0));
        expect(dest.right, lessThanOrEqualTo(width - 8.0 + 1e-4));
        expect(dest.top, greaterThanOrEqualTo(8.0));
        expect(dest.bottom, lessThanOrEqualTo(700.0 - 8.0 + 1e-4));
      });
    }
  });
}
