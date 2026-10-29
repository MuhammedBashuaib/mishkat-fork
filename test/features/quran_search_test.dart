import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_search_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_search_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/tafsir_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_search_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_search_state.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_reference_parser.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_search_highlighter.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_search_normalizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranData quranData;
  late MushafLayoutRepository layoutRepo;
  late TafsirRepository tafsirRepo;
  late Directory tempDir;
  late LocalStorageService storage;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('quran_search_test_');
    storage = LocalStorageService(directory: tempDir);
    await storage.init();

    // Load actual Quran data from project assets
    final quranFile = File('assets/data/quran.json');
    final manifestFile = File('assets/data/hafs-kfqc-manifest.json');
    final layoutFile = File('assets/data/mushaf-layout.json');
    final tafsirFile = File('assets/data/tafsir-muyassar.json');

    final quranJson =
        jsonDecode(await quranFile.readAsString()) as Map<String, dynamic>;
    final manifestJson =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;

    quranData = QuranData(
      chapters: (quranJson['surahs'] as List)
          .map(
            (item) =>
                QuranChapter.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      juz: (quranJson['juz'] as List)
          .map(
            (item) => JuzStart.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      pages: (manifestJson['pages'] as List)
          .map(
            (item) =>
                MushafPageInfo.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
    );

    layoutRepo = MushafLayoutRepository();
    layoutRepo.loadFromJsonString(await layoutFile.readAsString());

    tafsirRepo = TafsirRepository();
    tafsirRepo.loadFromJsonString(await tafsirFile.readAsString());
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('A. Arabic Search Normalizer Tests', () {
    test('Strips diacritics, tatweel, and unifies orthography', () {
      expect(QuranSearchNormalizer.normalize('بِسۡمِ ٱللَّهِ'), 'بسم الله');
      expect(
        QuranSearchNormalizer.normalize('الرَّحۡمَٰنِ الرَّحِيمِ'),
        'الرحمن الرحيم',
      );
      expect(QuranSearchNormalizer.normalize('أَإِآٱ'), 'اااا');
      expect(QuranSearchNormalizer.normalize('مُؤۡمِنُونَ'), 'مومنون');
      expect(QuranSearchNormalizer.normalize('شَيْءٌ'), 'شيء');
      expect(QuranSearchNormalizer.normalize('هُدًى'), 'هدي');
      expect(QuranSearchNormalizer.normalize('رَحْمَةٌ'), 'رحمه');
      expect(QuranSearchNormalizer.normalize('كـــــتاب'), 'كتاب');
    });

    test('Converts Eastern Arabic numerals to ASCII digits', () {
      expect(QuranSearchNormalizer.convertArabicDigits('٢:٢٥٥'), '2:255');
      expect(
        QuranSearchNormalizer.convertArabicDigits('البقرة ٢٥٥'),
        'البقرة 255',
      );
      expect(QuranSearchNormalizer.convertArabicDigits('صفحة ٦٠٤'), 'صفحة 604');
    });

    test('Maintains character index map from normalized to original', () {
      const orig = 'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ';
      final mapped = QuranSearchNormalizer.normalizeWithMap(orig);
      expect(mapped.normalized, 'بسم الله الرحمن الرحيم');
      expect(mapped.indexMap.length, mapped.normalized.length);

      final ranges = QuranSearchNormalizer.findMatchRanges(
        originalText: orig,
        normalizedQuery: 'الرحمن',
        precomputedNormalized: mapped.normalized,
        precomputedIndexMap: mapped.indexMap,
      );

      expect(ranges.length, 1);
      final slice = orig.substring(ranges.first.start, ranges.first.end);
      expect(slice, contains('ٱلرَّحۡمَٰنِ'));
    });
  });

  group('B. Quran Reference Parser Tests', () {
    test('Parses numeric Surah:Ayah formats (2:255, 2/255, 2 255, 2-255)', () {
      final ref1 = QuranReferenceParser.parse('2:255', quranData);
      expect(ref1, isNotNull);
      expect(ref1!.type, QuranReferenceType.ayah);
      expect(ref1.surah, 2);
      expect(ref1.ayah, 255);
      expect(ref1.page, 42);
      expect(ref1.globalAyah, 262);

      final ref2 = QuranReferenceParser.parse('2/255', quranData);
      expect(ref2?.globalAyah, 262);

      final ref3 = QuranReferenceParser.parse('2 255', quranData);
      expect(ref3?.globalAyah, 262);

      final ref4 = QuranReferenceParser.parse('2-255', quranData);
      expect(ref4?.globalAyah, 262);

      final refArabic = QuranReferenceParser.parse('٢:٢٥٥', quranData);
      expect(refArabic?.globalAyah, 262);
    });

    test('Parses Surah name + Ayah format ("البقرة 255", "سورة الكهف 10")', () {
      final ref1 = QuranReferenceParser.parse('البقرة 255', quranData);
      expect(ref1, isNotNull);
      expect(ref1!.surah, 2);
      expect(ref1.ayah, 255);

      final ref2 = QuranReferenceParser.parse('سورة الكهف 10', quranData);
      expect(ref2, isNotNull);
      expect(ref2!.surah, 18);
      expect(ref2.ayah, 10);
      expect(ref2.page, 294);
    });

    test('Parses explicit page references ("ص 255", "صفحة 604")', () {
      final ref1 = QuranReferenceParser.parse('ص 255', quranData);
      expect(ref1, isNotNull);
      expect(ref1!.type, QuranReferenceType.page);
      expect(ref1.page, 255);

      final ref2 = QuranReferenceParser.parse('صفحة 604', quranData);
      expect(ref2, isNotNull);
      expect(ref2!.page, 604);
    });

    test('Parses explicit global Ayah references ("#255", "g6236")', () {
      final ref1 = QuranReferenceParser.parse('#255', quranData);
      expect(ref1, isNotNull);
      expect(ref1!.type, QuranReferenceType.globalAyah);
      expect(ref1.globalAyah, 255);

      final ref2 = QuranReferenceParser.parse('g6236', quranData);
      expect(ref2?.globalAyah, 6236);
      expect(ref2?.surah, 114);
      expect(ref2?.ayah, 6);
    });

    test('Parses standalone single number within page range (1..604)', () {
      final ref = QuranReferenceParser.parse('255', quranData);
      expect(ref, isNotNull);
      expect(ref!.type, QuranReferenceType.page);
      expect(ref.page, 255);
    });

    test('Parses direct Surah name ("الفاتحة", "سورة يس")', () {
      final ref1 = QuranReferenceParser.parse('الفاتحة', quranData);
      expect(ref1, isNotNull);
      expect(ref1!.type, QuranReferenceType.surah);
      expect(ref1.surah, 1);
      expect(ref1.page, 1);

      final ref2 = QuranReferenceParser.parse('سورة يس', quranData);
      expect(ref2, isNotNull);
      expect(ref2!.surah, 36);
      expect(ref2.page, 440);
    });

    test('Returns null for invalid or out-of-bounds references', () {
      expect(QuranReferenceParser.parse('115:1', quranData), isNull);
      expect(QuranReferenceParser.parse('2:300', quranData), isNull);
      expect(QuranReferenceParser.parse('ص 605', quranData), isNull);
      expect(QuranReferenceParser.parse('غير موجود 55', quranData), isNull);
    });
  });

  group('C. Quran Search Repository & Index Tests', () {
    late QuranSearchRepository repository;

    setUp(() {
      repository = QuranSearchRepository(storage: storage);
    });

    test('Initializes in-memory index for all 6,236 Ayahs', () {
      expect(repository.isInitialized, isFalse);
      repository.initialize(quranData);
      expect(repository.isInitialized, isTrue);
    });

    test('Finds exact and partial matches with high speed', () {
      final results = repository.search(data: quranData, query: 'الحمد');
      expect(results.matchedAyahs.isNotEmpty, isTrue);
      expect(results.matchedAyahs.first.surah, 1); // Al-Fatihah
      expect(results.matchedAyahs.first.ayah, 2);

      final phraseResults = repository.search(
        data: quranData,
        query: 'الحمد لله رب العالمين',
      );
      expect(phraseResults.matchedAyahs.length, 6);
      expect(phraseResults.matchedAyahs.first.globalAyah, 2);
    });

    test('Matches Surahs when searching by name or number', () {
      final surahResults = repository.search(data: quranData, query: 'البقرة');
      expect(surahResults.matchedSurahs.isNotEmpty, isTrue);
      expect(surahResults.matchedSurahs.first.number, 2);

      final numResults = repository.search(data: quranData, query: '18');
      expect(
        numResults.matchedSurahs.any((s) => s.number == 18),
        isTrue,
      ); // Al-Kahf
    });

    test('Respects search filter modes (All, Ayahs, Surahs)', () {
      final ayahsOnly = repository.search(
        data: quranData,
        query: 'البقرة',
        filter: QuranSearchFilter.ayahs,
      );
      expect(ayahsOnly.matchedSurahs, isEmpty);

      final surahsOnly = repository.search(
        data: quranData,
        query: 'البقرة',
        filter: QuranSearchFilter.surahs,
      );
      expect(surahsOnly.matchedAyahs, isEmpty);
      expect(surahsOnly.matchedSurahs.isNotEmpty, isTrue);
    });

    test(
      'Recent searches persistence (add, deduplicate, remove, clear)',
      () async {
        await repository.clearRecentSearches();
        expect(repository.getRecentSearches(), isEmpty);

        await repository.addRecentSearch('2:255');
        await repository.addRecentSearch('الكهف');
        await repository.addRecentSearch(
          '2:255',
        ); // duplicate should move to top

        final recent = repository.getRecentSearches();
        expect(recent.length, 2);
        expect(recent.first, '2:255');
        expect(recent[1], 'الكهف');

        await repository.removeRecentSearch('الكهف');
        expect(repository.getRecentSearches(), ['2:255']);

        await repository.clearRecentSearches();
        expect(repository.getRecentSearches(), isEmpty);
      },
    );
  });

  group('D. Quran Search Cubit Tests', () {
    late QuranSearchRepository repository;
    late QuranSearchCubit cubit;

    setUp(() {
      repository = QuranSearchRepository(storage: storage);
      cubit = QuranSearchCubit(
        quranData: quranData,
        searchRepository: repository,
        debounceDuration: Duration.zero, // immediate for unit testing
      );
    });

    tearDown(() async {
      await cubit.close();
    });

    test('Initial state is empty with search history loaded', () {
      expect(cubit.state.status, QuranSearchStatus.initial);
      expect(cubit.state.query, '');
      expect(cubit.state.results.isEmpty, isTrue);
    });

    test('Immediate query transitions to success with results', () async {
      cubit.onQueryChanged('الحمد', immediate: true);
      expect(cubit.state.status, QuranSearchStatus.success);
      expect(cubit.state.results.matchedAyahs.isNotEmpty, isTrue);
    });

    test('Empty query resets state to initial', () {
      cubit.onQueryChanged('الحمد', immediate: true);
      expect(cubit.state.status, QuranSearchStatus.success);

      cubit.onQueryChanged('', immediate: true);
      expect(cubit.state.status, QuranSearchStatus.initial);
      expect(cubit.state.query, '');
    });

    test('Unmatched query transitions to empty status', () {
      cubit.onQueryChanged('كلمةغيرموجودةابدا', immediate: true);
      expect(cubit.state.status, QuranSearchStatus.empty);
      expect(cubit.state.results.isEmpty, isTrue);
    });

    test('Changing filter triggers re-search with new filter', () {
      cubit.onQueryChanged('البقرة', immediate: true);
      expect(cubit.state.results.matchedSurahs.isNotEmpty, isTrue);

      cubit.setFilter(QuranSearchFilter.ayahs);
      expect(cubit.state.results.matchedSurahs, isEmpty);
    });
  });

  group('E. Match Highlighter Tests', () {
    test('Merges contiguous and overlapping ranges', () {
      final ranges = [
        const TextMatchRange(start: 0, end: 5),
        const TextMatchRange(start: 4, end: 8),
        const TextMatchRange(start: 12, end: 15),
      ];

      final merged = QuranSearchHighlighter.mergeRanges(ranges);
      expect(merged.length, 2);
      expect(merged[0], const TextMatchRange(start: 0, end: 8));
      expect(merged[1], const TextMatchRange(start: 12, end: 15));
    });
  });

  group('F. Full Quran 6,236 Ayah & 114 Surah Deep Navigation Validation', () {
    test('All 6,236 Ayahs resolve deterministically to Mushaf page and layout bounds', () {
      for (var g = 1; g <= 6236; g++) {
        final point = quranData.pointForGlobal(g);
        final page = quranData.pageForGlobal(g);
        final bounds = layoutRepo.getAyah(g);

        expect(point.global, g);
        expect(page, inInclusiveRange(1, 604));
        expect(bounds, isNotNull, reason: 'Ayah $g must have layout bounds');
        expect(
          bounds!.page,
          page,
          reason: 'Page for Ayah $g must match manifest',
        );
        expect(bounds.surah, point.surah);
        expect(bounds.ayah, point.ayah);
      }
    });

    test(
      'All 6,236 Ayahs have valid Tafsir entries accessible from search',
      () {
        for (var g = 1; g <= 6236; g++) {
          final entry = tafsirRepo.getTafsir(g);
          expect(
            entry,
            isNotNull,
            reason: 'Tafsir entry for global Ayah $g must exist',
          );
          expect(entry!.text.isNotEmpty, isTrue);
        }
      },
    );

    test('All 114 Surahs can be parsed by name and resolve to correct initial page', () {
      for (final ch in quranData.chapters) {
        final parsed = QuranReferenceParser.parse(ch.name, quranData);
        expect(parsed, isNotNull, reason: 'Surah ${ch.name} must be parseable');
        expect(parsed!.type, QuranReferenceType.surah);
        expect(parsed.surah, ch.number);
        expect(parsed.page, ch.page);
      }
    });
  });
}
