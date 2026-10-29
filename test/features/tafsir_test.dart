import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/mushaf_layout_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/models/tafsir_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/tafsir_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/tafsir_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/tafsir_state.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/ayah_action_sheet.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/tafsir_knowledge_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranRepository quranRepo;
  late QuranData quranData;
  late TafsirRepository tafsirRepo;
  late TafsirPackage tafsirPackage;

  setUpAll(() async {
    quranRepo = QuranRepository();
    quranData = await quranRepo.load();
    tafsirRepo = TafsirRepository();
    tafsirPackage = await tafsirRepo.load();
  });

  group('A. Source Metadata & Schema Tests', () {
    test('Source metadata contains all required authentic fields', () {
      final source = tafsirPackage.source;
      expect(source.id, 'arabic_moyassar');
      expect(source.name, 'التفسير الميسر');
      expect(source.language, 'ar');
      expect(source.author, contains('مجمع الملك فهد'));
      expect(source.publisher, 'مجمع الملك فهد لطباعة المصحف الشريف');
      expect(source.attribution, contains('QuranEnc.com'));
      expect(source.license, isNotEmpty);
      expect(source.version, '1.0.0');
      expect(source.sourceUrl, contains('quranenc.com'));
      expect(source.totalAyahs, 6236);
    });

    test('TafsirSource JSON serialization round-trips accurately', () {
      final source = tafsirPackage.source;
      final jsonMap = source.toJson();
      final recreated = TafsirSource.fromJson(jsonMap);
      expect(recreated, equals(source));
    });
  });

  group('B. Tafsir Repository Loading & Caching', () {
    test('Loads package and caches subsequent requests in memory', () async {
      final pkg1 = await tafsirRepo.load();
      final pkg2 = await tafsirRepo.load();
      expect(identical(pkg1, pkg2), isTrue);
    });

    test('getSources returns registered sources', () {
      final sources = tafsirRepo.getSources();
      expect(sources, isNotEmpty);
      expect(sources.first.id, 'arabic_moyassar');
    });

    test('Throws ArgumentError for unknown source ID', () async {
      expect(
        () => tafsirRepo.load(sourceId: 'non_existent_source'),
        throwsArgumentError,
      );
    });
  });

  group('C. Ayah Commentary Lookup', () {
    test(
      'Lookup global Ayah 1 (Al-Fatihah 1:1) returns authentic commentary',
      () {
        final entry = tafsirRepo.getTafsir(1);
        expect(entry, isNotNull);
        expect(entry!.sourceId, 'arabic_moyassar');
        expect(entry.globalAyah, 1);
        expect(entry.text, contains('أبتدئ قراءة القرآن باسم الله'));
      },
    );

    test(
      'Lookup global Ayah 6236 (An-Naas 114:6) returns authentic commentary',
      () {
        final entry = tafsirRepo.getTafsir(6236);
        expect(entry, isNotNull);
        expect(entry!.globalAyah, 6236);
        expect(entry.text, contains('شياطين الجن والإنس'));
      },
    );

    test(
      'Lookup Ayat al-Kursi (2:255, global 262) returns complete commentary',
      () {
        final globalKursi = quranData.globalFor(2, 255);
        expect(globalKursi, 262);
        final entry = tafsirRepo.getTafsir(globalKursi);
        expect(entry, isNotNull);
        expect(entry!.text, contains('الحيُّ'));
      },
    );
  });

  group('D. Missing & Out-of-Range Ayah Handling', () {
    test(
      'Lookup with 0, negative, or > 6236 returns null safely without crashing',
      () {
        expect(tafsirRepo.getTafsir(0), isNull);
        expect(tafsirRepo.getTafsir(-1), isNull);
        expect(tafsirRepo.getTafsir(6237), isNull);
        expect(tafsirRepo.getTafsir(99999), isNull);
      },
    );
  });

  group('E. Raw Asset Integrity & Duplicate Detection', () {
    test(
      'Asset JSON has exactly 6,236 non-empty entries with zero duplicates',
      () async {
        final raw = await rootBundle.loadString(
          'assets/data/tafsir-muyassar.json',
        );
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final rawEntries = decoded['entries'] as Map<String, dynamic>;

        expect(rawEntries.length, 6236);

        final seenKeys = <int>{};
        for (final entry in rawEntries.entries) {
          final keyInt = int.tryParse(entry.key);
          expect(keyInt, isNotNull);
          expect(keyInt! >= 1 && keyInt <= 6236, isTrue);
          expect(
            seenKeys.contains(keyInt),
            isFalse,
            reason: 'Duplicate key: $keyInt',
          );
          seenKeys.add(keyInt);

          final text = entry.value as String;
          expect(
            text.trim().isNotEmpty,
            isTrue,
            reason: 'Empty text for key: $keyInt',
          );
        }

        expect(seenKeys.length, 6236);
      },
    );
  });

  group('F. Quran Identity Alignment (All 114 Surahs)', () {
    test('Cross-validates every Surah and Ayah against quran.json', () {
      for (final chapter in quranData.chapters) {
        for (var a = 1; a <= chapter.ayahs.length; a++) {
          final global = quranData.globalFor(chapter.number, a);
          final entry = tafsirRepo.getTafsir(global);
          expect(
            entry,
            isNotNull,
            reason:
                'Missing Tafsir for Surah ${chapter.number} Ayah $a (global: $global)',
          );
          expect(entry!.globalAyah, global);
        }
      }
    });
  });

  group('G. Full 6,236 Ayah Regression', () {
    test(
      'Every single global Ayah 1..6236 resolves to a non-empty TafsirEntry',
      () {
        var resolvedCount = 0;
        for (var g = 1; g <= 6236; g++) {
          final entry = tafsirRepo.getTafsir(g);
          if (entry != null && entry.text.isNotEmpty) {
            resolvedCount++;
          }
        }
        expect(resolvedCount, 6236);
      },
    );
  });

  group('H. TafsirCubit - State Management & Lifecycle', () {
    test('Initial state is TafsirInitial', () {
      final cubit = TafsirCubit(repository: tafsirRepo);
      expect(cubit.state.status, TafsirStatus.initial);
      cubit.close();
    });

    test('loadTafsir loads entry and emits loaded state', () async {
      final cubit = TafsirCubit(repository: tafsirRepo);
      await cubit.loadTafsir(1);

      expect(cubit.state.status, TafsirStatus.loaded);
      expect(cubit.state.entry?.globalAyah, 1);
      expect(cubit.state.selectedSource?.id, 'arabic_moyassar');
      cubit.close();
    });

    test('loadTafsir emits unavailable state for non-existent Ayah', () async {
      final cubit = TafsirCubit(repository: tafsirRepo);
      await cubit.loadTafsir(99999);

      expect(cubit.state.status, TafsirStatus.unavailable);
      expect(cubit.state.entry, isNull);
      cubit.close();
    });

    test('clear resets state', () async {
      final cubit = TafsirCubit(repository: tafsirRepo);
      await cubit.loadTafsir(1);
      expect(cubit.state.status, TafsirStatus.loaded);

      cubit.clear();
      expect(cubit.state.status, TafsirStatus.initial);
      cubit.close();
    });
  });

  group('I. TafsirKnowledgeSheet - Widget Rendering', () {
    testWidgets(
      'Renders Surah context, Quran verse, commentary, and attribution',
      (tester) async {
        const ayah = AyahBounds(
          page: 1,
          surah: 1,
          ayah: 1,
          globalAyah: 1,
          bounds: Rect.zero,
          segments: [],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TafsirKnowledgeSheet(
                ayah: ayah,
                quranData: quranData,
                repository: tafsirRepo,
              ),
            ),
          ),
        );

        // Initial load in widget
        await tester.pumpAndSettle();

        // Surah context
        expect(find.textContaining(quranData.chapter(1).name), findsWidgets);
        expect(find.textContaining('الآية 1'), findsOneWidget);

        // Verse text
        expect(
          find.textContaining(quranData.chapter(1).ayahs[0]),
          findsOneWidget,
        );

        // Commentary title and attribution
        expect(find.text('التفسير الميسر'), findsOneWidget);
        expect(find.textContaining('QuranEnc.com'), findsOneWidget);

        // Commentary body
        expect(
          find.textContaining('أبتدئ قراءة القرآن باسم الله'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Renders empty state when commentary is unavailable', (
      tester,
    ) async {
      final cubit = TafsirCubit(repository: tafsirRepo);
      // Emit unavailable state
      cubit.emit(const TafsirState(status: TafsirStatus.unavailable));

      const ayah = AyahBounds(
        page: 1,
        surah: 1,
        ayah: 1,
        globalAyah: 99999,
        bounds: Rect.zero,
        segments: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: TafsirKnowledgeSheet(
                ayah: ayah,
                quranData: quranData,
                repository: tafsirRepo,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('لا يتوفر التفسير لهذه الآية حاليًا.'), findsOneWidget);
      cubit.close();
    });

    testWidgets('Renders error state with working retry button', (
      tester,
    ) async {
      final cubit = TafsirCubit(repository: tafsirRepo);
      cubit.emit(
        const TafsirState(
          status: TafsirStatus.error,
          errorMessage: 'تعذر تحميل التفسير.',
          globalAyah: 1,
        ),
      );

      const ayah = AyahBounds(
        page: 1,
        surah: 1,
        ayah: 1,
        globalAyah: 1,
        bounds: Rect.zero,
        segments: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: TafsirKnowledgeSheet(ayah: ayah, quranData: quranData),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('تعذر تحميل التفسير.'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);

      // Tap retry
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();

      // State should transition back to loaded
      expect(cubit.state.status, TafsirStatus.loaded);
      cubit.close();
    });
  });

  group('J. Theme & Directionality Validation', () {
    testWidgets('Renders cleanly in Dark Mode with RTL directionality', (
      tester,
    ) async {
      const ayah = AyahBounds(
        page: 1,
        surah: 1,
        ayah: 1,
        globalAyah: 1,
        bounds: Rect.zero,
        segments: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: TafsirKnowledgeSheet(
              ayah: ayah,
              quranData: quranData,
              repository: tafsirRepo,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final directionality = tester.widget<Directionality>(
        find
            .descendant(
              of: find.byType(TafsirKnowledgeSheet),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(directionality.textDirection, TextDirection.rtl);
      expect(find.textContaining('التفسير الميسر'), findsOneWidget);
    });

    testWidgets('Renders cleanly in Light Mode with RTL directionality', (
      tester,
    ) async {
      const ayah = AyahBounds(
        page: 1,
        surah: 1,
        ayah: 1,
        globalAyah: 1,
        bounds: Rect.zero,
        segments: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: TafsirKnowledgeSheet(
              ayah: ayah,
              quranData: quranData,
              repository: tafsirRepo,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final directionality = tester.widget<Directionality>(
        find
            .descendant(
              of: find.byType(TafsirKnowledgeSheet),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(directionality.textDirection, TextDirection.rtl);
      expect(find.textContaining('التفسير الميسر'), findsOneWidget);
    });
  });

  group('K. Responsive Width Validation (320px to 1024px)', () {
    const testWidths = [320.0, 360.0, 390.0, 430.0, 768.0, 1024.0];

    for (final width in testWidths) {
      testWidgets('Renders without overflow at width $width px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width * 2.0, 800.0 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const ayah = AyahBounds(
          page: 1,
          surah: 1,
          ayah: 1,
          globalAyah: 1,
          bounds: Rect.zero,
          segments: [],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TafsirKnowledgeSheet(
                ayah: ayah,
                quranData: quranData,
                repository: tafsirRepo,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('التفسير الميسر'), findsOneWidget);
      });
    }
  });

  group('L. Long Text Scrolling Validation', () {
    testWidgets(
      'Long commentary (Ayat al-Kursi) scrolls without error or clipping',
      (tester) async {
        tester.view.physicalSize = const Size(390 * 2.0, 600 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final globalKursi = quranData.globalFor(2, 255);
        final ayah = AyahBounds(
          page: 42,
          surah: 2,
          ayah: 255,
          globalAyah: globalKursi,
          bounds: Rect.zero,
          segments: const [],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TafsirKnowledgeSheet(
                ayah: ayah,
                quranData: quranData,
                repository: tafsirRepo,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Find scrollable
        final scrollableFinder = find.byType(SingleChildScrollView);
        expect(scrollableFinder, findsOneWidget);

        // Drag to scroll
        await tester.drag(scrollableFinder, const Offset(0, -300));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('QuranEnc.com'), findsOneWidget);
      },
    );
  });

  group('M. Action Sheet Integration', () {
    testWidgets(
      'Tapping التفسير in AyahActionSheet opens TafsirKnowledgeSheet',
      (tester) async {
        final storage = LocalStorageService();
        final audioService = QuranAudioService();
        final quranCubit = QuranCubit(
          repository: quranRepo,
          storage: storage,
          audio: audioService,
          reciter: 'ar.alafasy',
          fontSize: 32,
        );

        const ayah = AyahBounds(
          page: 1,
          surah: 1,
          ayah: 1,
          globalAyah: 1,
          bounds: Rect.zero,
          segments: [],
        );

        String? sheetResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: quranCubit,
                child: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () async {
                      sheetResult = await AyahActionSheet.show(
                        context: context,
                        ayah: ayah,
                        quranData: quranData,
                      );
                      if (sheetResult == 'tafsir' && context.mounted) {
                        await TafsirKnowledgeSheet.show(
                          context: context,
                          ayah: ayah,
                          quranData: quranData,
                          repository: tafsirRepo,
                        );
                      }
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        // Open Action Sheet
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(AyahActionSheet), findsOneWidget);
        expect(find.text('التفسير'), findsOneWidget);

        // Tap Tafsir button
        await tester.tap(find.text('التفسير'));
        await tester.pumpAndSettle();

        // Action sheet should be popped with 'tafsir' and TafsirKnowledgeSheet presented
        expect(sheetResult, 'tafsir');
        expect(find.byType(TafsirKnowledgeSheet), findsOneWidget);
        expect(
          find.textContaining('أبتدئ قراءة القرآن باسم الله'),
          findsOneWidget,
        );

        quranCubit.close();
      },
    );
  });
}
