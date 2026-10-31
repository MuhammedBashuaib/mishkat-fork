import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/core/utils/app_formatters.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_search_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_search_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_audio_player_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_index_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_search_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_reference_parser.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_search_normalizer.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_surah_search.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

import 'quran_home_hub_test.dart'
    show
        InMemoryLocalStorage,
        TestQuranAudioService,
        FakeLocationService,
        FakeNotificationService;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final quranRepository = QuranRepository();
  final search = QuranSearchRepository();
  late QuranData data;

  setUpAll(() async {
    data = await quranRepository.load();
    final fonts = FontLoader('Cairo');
    for (final weight in ['Regular', 'SemiBold', 'Bold', 'Black']) {
      fonts.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  test('All 114 display names use standard Arabic without Quranic marks', () {
    expect(data.chapters, hasLength(114));
    expect(data.chapters.map((c) => c.name).toSet(), hasLength(114));
    for (final chapter in data.chapters) {
      expect(
        RegExp(r'^[\u0621-\u064A ]+$').hasMatch(chapter.name),
        isTrue,
        reason: '${chapter.number}: ${chapter.name}',
      );
    }
    for (final entry in {
      3: 'آل عمران',
      6: 'الأنعام',
      7: 'الأعراف',
      14: 'إبراهيم',
      34: 'سبأ',
      55: 'الرحمن',
      76: 'الإنسان',
      78: 'النبأ',
      82: 'الانفطار',
      84: 'الانشقاق',
      87: 'الأعلى',
      93: 'الضحى',
    }.entries) {
      expect(data.chapter(entry.key).name, entry.value);
    }
    expect(data.chapter(6).revelationType, 'مكية');
    expect(data.chapter(7).revelationType, 'مكية');
  });

  test('All 114 names work with prefixes, hamza variants and spacing', () {
    for (final chapter in data.chapters) {
      final simple = QuranSearchNormalizer.normalize(chapter.name);
      for (final query in [
        chapter.name,
        simple,
        'سورة ${chapter.name}',
        'سُورَةُ  $simple',
        'سوره $simple',
        'سور $simple',
        simple.replaceAll(' ', ''),
      ]) {
        final matches = search.search(data: data, query: query);
        expect(
          matches.matchedSurahs.first.number,
          chapter.number,
          reason: query,
        );
        final reference = QuranReferenceParser.parse(query, data);
        expect(reference?.surah, chapter.number, reason: query);
        expect(reference?.globalAyah, chapter.globalStart, reason: query);
      }
    }
  });

  test('سور and سورة list all surahs and preserve the active filter', () {
    for (final query in ['سور', 'سورة', 'سوره', 'السور', 'السورة', 'سُورَة']) {
      final result = search.search(
        data: data,
        query: query,
        filter: QuranSearchFilter.surahs,
      );
      expect(result.matchedSurahs, hasLength(114), reason: query);
      expect(result.matchedAyahs, isEmpty);
      expect(result.directReference, isNull);
    }
    expect(
      search
          .search(data: data, query: 'سورة', filter: QuranSearchFilter.ayahs)
          .matchedSurahs,
      isEmpty,
    );
  });

  test('Approximate names are suggestions; exact names rank first', () {
    for (final entry in {
      'االانعام': 6,
      'الفاتخحة': 1,
      'البقره': 2,
      'العمران': 3,
      'عمران': 3,
      'الاعراف': 7,
      'انعام': 6,
    }.entries) {
      expect(
        search.search(data: data, query: entry.key).matchedSurahs.first.number,
        entry.value,
        reason: entry.key,
      );
    }
    expect(QuranReferenceParser.parse('االانعام', data), isNull);
    expect(
      search
          .search(data: data, query: 'الناس')
          .matchedSurahs
          .map((c) => c.number),
      [114],
    );
    expect(
      search.search(data: data, query: 'كلمةغيرموجودةابدا').isEmpty,
      isTrue,
    );
    expect(search.search(data: data, query: 'َّ').isEmpty, isTrue);
    expect(
      QuranSurahSearch.findChapters(
        data.chapters,
        'مدنيه',
        includeRevelationType: true,
      ),
      hasLength(28),
    );
  });

  test('References accept normalized prefixes, digits and separators', () {
    for (final query in [
      '2:255',
      '٢ : ٢٥٥',
      '۲ / ۲۵۵',
      'سُورَة البقره آيه ٢٥٥',
    ]) {
      final ref = QuranReferenceParser.parse(query, data);
      expect(ref?.globalAyah, 262, reason: query);
    }
    expect(QuranReferenceParser.parse('سورة ٣', data)?.surah, 3);
    expect(QuranReferenceParser.parse('سوره ال عمران آية ١٨', data)?.ayah, 18);
    expect(QuranReferenceParser.parse('صَفْحَة ٦٠٤', data)?.page, 604);
    expect(QuranReferenceParser.parse('ايَة ٢٦٢', data)?.globalAyah, 262);
    for (final query in ['سورة ١١٥', 'سورة البقرة ٢٨٧', '٢:٠', 'ص ٦٠٥']) {
      expect(QuranReferenceParser.parse(query, data), isNull, reason: query);
    }
  });

  test('Verse normalization preserves original text and highlight ranges', () {
    expect(QuranSearchNormalizer.normalize('ٱلْأَعْلَىٰ'), 'الاعلي');
    for (final entry in {
      'إِلَٰهَ': 'اله',
      'شَهَٰدَة': 'شهاده',
      'هَٰرُون': 'هارون',
      'وَلَٰكِن': 'ولكن',
      'هَٰذَا': 'هذا',
    }.entries) {
      expect(QuranSearchNormalizer.normalize(entry.key), entry.value);
    }
    expect(
      QuranSearchNormalizer.normalize('ءَامَنُوا'),
      QuranSearchNormalizer.normalize('آمنوا'),
    );
    for (final query in [
      'الله لا إله إلا هو',
      'الله لا اله الا هو',
      'اللَّهُ\u00a0لا\u00a0إلَهَ إلّا هُوَ',
      '\u200fالله لا اله الا هو',
    ]) {
      final results = search.search(data: data, query: query);
      expect(
        results.matchedAyahs.any((a) => a.globalAyah == 262),
        isTrue,
        reason: query,
      );
      final ayah = results.matchedAyahs.firstWhere((a) => a.globalAyah == 262);
      expect(ayah.originalText, data.chapter(2).ayahs[254]);
      expect(ayah.matchRanges, isNotEmpty);
      for (final range in ayah.matchRanges) {
        expect(range.start, inInclusiveRange(0, ayah.originalText.length - 1));
        expect(
          range.end,
          inInclusiveRange(range.start + 1, ayah.originalText.length),
        );
      }
    }
    expect(
      search.search(data: data, query: 'الذين امنوا').matchedAyahs,
      isNotEmpty,
    );
  });

  test(
    'General Arabic search handles diacritics, hamzas, digits and pasted text',
    () {
      expect(
        AppFormatters.normalizeArabic('أَذْكَار'),
        AppFormatters.normalizeArabic('اذكار'),
      );
      expect(
        AppFormatters.normalizeArabic('إبراهيم'),
        AppFormatters.normalizeArabic('ابراهيم'),
      );
      expect(
        AppFormatters.normalizeArabic('آل عمران'),
        AppFormatters.normalizeArabic('ال عمران'),
      );
      expect(
        AppFormatters.normalizeArabic('\u200fأَحْمَد\u00a0علی ۱۲٣'),
        'احمد علي 123',
      );
    },
  );

  testWidgets(
    'Mobile index, search and reciter search use the corrected names',
    (tester) async {
      tester.view.physicalSize = const Size(390, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = InMemoryLocalStorage();
      final audio = TestQuranAudioService();
      final quran = QuranCubit(
        repository: quranRepository,
        storage: storage,
        audio: audio,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      final settings = SettingsCubit(
        storage: storage,
        locationService: FakeLocationService(),
        notifications: FakeNotificationService(),
      );
      await quran.load();
      await settings.load();
      addTearDown(quran.close);
      addTearDown(settings.close);
      addTearDown(audio.dispose);
      final boundaryKey = GlobalKey();

      Widget app(Widget page) => RepositoryProvider<LocalStorageService>.value(
        value: storage,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<QuranCubit>.value(value: quran),
            BlocProvider<SettingsCubit>.value(value: settings),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: RepaintBoundary(key: boundaryKey, child: page),
          ),
        ),
      );

      await tester.pumpWidget(app(const QuranIndexPage()));
      await tester.pumpAndSettle();
      expect(find.text('سورة آل عمران'), findsOneWidget);
      expect(find.text('سورة الأنعام'), findsOneWidget);
      expect(find.text('سورة الأعراف'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('/tmp/mishkat-arabic-index.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      for (final query in ['سور', 'سورة']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        expect(find.text('سورة آل عمران'), findsOneWidget);
        expect(find.text('لا توجد سورة مطابقة للبحث'), findsNothing);
      }
      for (final entry in {
        'سورة الانعام': 'الأنعام',
        'سوره الاعراف': 'الأعراف',
        'العمران': 'آل عمران',
        'االانعام': 'الأنعام',
      }.entries) {
        await tester.enterText(find.byType(TextField), entry.key);
        await tester.pumpAndSettle();
        expect(find.text('سورة ${entry.value}'), findsOneWidget);
      }
      await tester.pumpWidget(
        app(const QuranSearchPage(initialQuery: 'سورة الانعام')),
      );
      await tester.pumpAndSettle();
      expect(find.text('سورة الأنعام'), findsWidgets);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(320, 960);
      for (final query in ['سورة آل عمران', 'الله لا اله الا هو']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        expect(find.text('لا توجد نتائج'), findsNothing);
        expect(tester.takeException(), isNull, reason: query);
      }
      tester.view.physicalSize = const Size(390, 960);

      await tester.pumpWidget(app(const QuranAudioPlayerPage()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ابراهيم');
      await tester.pumpAndSettle();
      expect(find.text('إبراهيم الأخضر'), findsOneWidget);
      expect(find.text('لا يوجد قارئ بهذا الاسم'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
