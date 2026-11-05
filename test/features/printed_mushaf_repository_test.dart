import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/printed_mushaf_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/printed_mushaf_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_recitation_text.dart';

class _CountingBundle extends CachingAssetBundle {
  int reads = 0;
  bool failNext = false;

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    reads++;
    if (failNext) {
      failNext = false;
      return Future.error(StateError('temporary asset failure'));
    }
    return rootBundle.loadString(key);
  }

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrintedMushafRepository printed;
  late MushafLayoutRepository geometry;
  late QuranData quran;
  late Map<int, List<String>> canonical;
  late Map<int, List<PrintedMushafWord>> verses;

  setUpAll(() async {
    printed = PrintedMushafRepository();
    geometry = MushafLayoutRepository();
    await printed.load();
    await geometry.load();
    quran = await QuranRepository().load();
    canonical = {
      for (final surah in quran.chapters)
        for (var i = 0; i < surah.ayahs.length; i++)
          surah.globalStart + i: surah.ayahs[i]
              .split(RegExp(r'\s+'))
              .where(QuranRecitationText.hasArabicLetter)
              .toList(),
    };
    verses = {};
    for (final page in printed.data.pages) {
      for (final line in page.lines) {
        for (final word in line.words) {
          (verses[word.globalAyah] ??= []).add(word);
        }
      }
    }
  });

  String normalized(String text) =>
      QuranRecitationText.normalize(text).replaceAll(RegExp(r'\s+'), '');

  test('bundled printed map covers every canonical word and page boundary', () {
    expect(printed.data.version, 1);
    expect(printed.data.pages.length, 604);
    expect(printed.data.canonicalWordCount, 77430);
    expect(printed.data.printedWordCount, 77433);
    expect(verses.keys.toList(), List.generate(6236, (i) => i + 1));
    final positions = <(int, int)>{};
    final ordinalsByVerse = <int, Set<int>>{};
    var wordParts = 0;
    for (final page in printed.data.pages) {
      expect(page.page, inInclusiveRange(1, 604));
      expect(
        page.lines.map((line) => line.number),
        List.generate(page.page <= 2 ? 8 : 15, (i) => i + 1),
      );
      for (final line in page.lines) {
        expect(line.surah, inInclusiveRange(1, 114));
        if (line.kind != PrintedMushafLineKind.text) {
          expect(line.words, isEmpty);
          continue;
        }
        expect(line.words, isNotEmpty);
        for (final word in line.words) {
          expect(
            geometry.pageForAyah(word.globalAyah),
            page.page,
            reason: 'Wrong printed page for verse ${word.globalAyah}',
          );
          if (!word.isMarker) {
            wordParts++;
            expect(
              word.ordinal,
              inInclusiveRange(0, canonical[word.globalAyah]!.length - 1),
            );
            positions.add((word.globalAyah, word.ordinal));
            (ordinalsByVerse[word.globalAyah] ??= {}).add(word.ordinal);
          }
        }
      }
    }
    expect(wordParts, 77433);
    expect(positions.length, 77430);
    for (final entry in canonical.entries) {
      expect(
        ordinalsByVerse[entry.key],
        List.generate(entry.value.length, (i) => i),
        reason: 'Missing or shifted canonical ordinal in verse ${entry.key}',
      );
    }
  });

  test('all printed word parts correspond to canonical Arabic in order', () {
    // These two spellings and the combining-hamza form are independently
    // documented differences between the existing text and the QPC script.
    final exactScriptDifferences = <(int, int), (String, String)>{
      (quran.globalFor(2, 72), 3): ('فَٱدَّٰرَْٰٔتُمْ', 'فَٱدَّٰرَٰءۡتُمۡ'),
      (quran.globalFor(12, 39), 0): ('يَٰصَىٰحِبَىِ', 'يَٰصَٰحِبَيِ'),
      (quran.globalFor(12, 41), 0): ('يَٰصَىٰحِبَىِ', 'يَٰصَٰحِبَيِ'),
    };
    final encounteredDifferences = <(int, int)>{};
    for (final entry in verses.entries) {
      final words = entry.value.where((word) => !word.isMarker).toList();
      final parts = <int, String>{};
      var previous = -1;
      for (final word in words) {
        expect(word.ordinal, inInclusiveRange(previous, previous + 1));
        previous = word.ordinal;
        parts.update(
          word.ordinal,
          (text) => '$text${word.text}',
          ifAbsent: () => word.text,
        );
      }
      for (final part in parts.entries) {
        final original = canonical[entry.key]![part.key];
        if (normalized(original) == normalized(part.value)) continue;
        final key = (entry.key, part.key);
        encounteredDifferences.add(key);
        expect(
          exactScriptDifferences[key],
          (original, part.value),
          reason:
              'Unverified script mapping for verse ${entry.key}, word ${part.key}',
        );
      }
    }
    expect(encounteredDifferences, exactScriptDifferences.keys.toSet());
  });

  test(
    'printed end markers preserve source positions without word ordinals',
    () {
      for (final entry in verses.entries) {
        final markers = entry.value.where((word) => word.isMarker).toList();
        expect(markers, hasLength(1));
        expect(identical(entry.value.last, markers.single), isTrue);
        expect(markers.single.ordinal, -1);
        final ayah = geometry.getAyah(entry.key)!;
        expect(markers.single.ayahNumber, ayah.ayah);
        expect(markers.single.text, matches(RegExp(r'^[٠-٩]+$')));
      }
    },
  );

  test(
    'split and joined source tokens preserve individual canonical indices',
    () {
      for (final location in [(2, 181, 2), (8, 6, 3), (13, 37, 7)]) {
        final global = quran.globalFor(location.$1, location.$2);
        final parts = verses[global]!
            .where((word) => word.ordinal == location.$3)
            .toList();
        expect(parts.map((word) => normalized(word.text)), ['بعد', 'ما']);
        expect(normalized(canonical[global]![location.$3]), 'بعدما');
        final following = verses[global]!.firstWhere(
          (word) => word.ordinal == location.$3 + 1,
        );
        expect(
          normalized(following.text),
          normalized(canonical[global]![location.$3 + 1]),
        );
      }
      final ilYasin = verses[quran.globalFor(37, 130)]!
          .where((word) => !word.isMarker)
          .toList();
      expect(ilYasin.map((word) => word.ordinal), [0, 1, 2, 3]);
      expect(ilYasin.skip(2).map((word) => normalized(word.text)), [
        'ال',
        'ياسين',
      ]);
    },
  );

  test(
    'opening and final pages retain printed multi-ayah lines and headings',
    () {
      final first = printed.page(1)!;
      expect(first.lines.first.kind, PrintedMushafLineKind.surahTitle);
      expect(first.lines.every((line) => line.centered), isTrue);
      expect(first.lines[3].words.map((word) => word.globalAyah).toSet(), {
        3,
        4,
      });
      final second = printed.page(2)!;
      expect(second.lines[1].kind, PrintedMushafLineKind.basmala);
      expect(second.lines[2].words.map((word) => word.globalAyah).toSet(), {
        8,
        9,
      });
      expect(
        printed
            .page(3)!
            .lines
            .every(
              (line) =>
                  line.kind == PrintedMushafLineKind.text && !line.centered,
            ),
        isTrue,
      );
      expect(printed.page(50)!.lines.first.surah, 3);
      expect(printed.page(50)!.lines[1].kind, PrintedMushafLineKind.basmala);
      final headings = printed
          .page(604)!
          .lines
          .where((line) => line.kind == PrintedMushafLineKind.surahTitle);
      expect(headings.map((line) => (line.number, line.surah)), [
        (1, 112),
        (5, 113),
        (10, 114),
      ]);
      expect(printed.page(0), isNull);
      expect(printed.page(605), isNull);
    },
  );

  test(
    'asset loading shares pending work and returns fresh cached futures',
    () async {
      final bundle = _CountingBundle();
      final repository = PrintedMushafRepository(bundle: bundle);
      expect(repository.page(1), isNull);
      final pending = repository.load();
      expect(identical(pending, repository.load()), isTrue);
      final data = await pending;
      expect(bundle.reads, 1);
      final first = repository.load();
      final second = repository.load();
      expect(identical(first, second), isFalse);
      expect(identical(await first, data), isTrue);
      expect(identical(await second, data), isTrue);
      expect(bundle.reads, 1);
      expect(repository.isLoaded, isTrue);
    },
  );

  test(
    'failed bundled load can retry without retaining a failed future',
    () async {
      final bundle = _CountingBundle()..failNext = true;
      final repository = PrintedMushafRepository(bundle: bundle);
      await expectLater(repository.load(), throwsStateError);
      expect(repository.isLoaded, isFalse);
      expect(repository.page(1), isNull);
      await repository.load();
      expect(repository.page(604), isNotNull);
      expect(bundle.reads, 2);
    },
  );
}
