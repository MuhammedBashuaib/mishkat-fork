/// The printed Madinah page structure, independent of recitation progress.
enum PrintedMushafLineKind { text, surahTitle, basmala }

class PrintedMushafWord {
  const PrintedMushafWord({
    required this.globalAyah,
    required this.ordinal,
    required this.text,
    required this.isMarker,
    required this.ayahNumber,
  });

  final int globalAyah;

  /// Zero-based word ordinal in the application's canonical verse. A printed
  /// token can be part of a canonical word; such tokens share this ordinal.
  /// Verse end markers use -1 and never consume a recitation word.
  final int ordinal;

  /// QPC Hafs Unicode text used only for drawing with the bundled QPC font.
  final String text;
  final bool isMarker;
  final int ayahNumber;

  factory PrintedMushafWord.fromJson(List<dynamic> json) => PrintedMushafWord(
    globalAyah: json[0] as int,
    ordinal: json[1] as int,
    text: json[2] as String,
    isMarker: json[3] == 1,
    ayahNumber: json[4] as int,
  );
}

class PrintedMushafLine {
  const PrintedMushafLine({
    required this.number,
    required this.kind,
    required this.surah,
    required this.centered,
    required this.words,
  });

  final int number;
  final PrintedMushafLineKind kind;
  final int? surah;
  final bool centered;
  final List<PrintedMushafWord> words;

  factory PrintedMushafLine.fromJson(Map<String, dynamic> json) =>
      PrintedMushafLine(
        number: json['n'] as int,
        kind: PrintedMushafLineKind.values[json['k'] as int],
        surah: json['s'] as int?,
        centered: json['c'] == 1,
        words: List.unmodifiable(
          (json['w'] as List).map(
            (word) => PrintedMushafWord.fromJson(word as List<dynamic>),
          ),
        ),
      );
}

class PrintedMushafPage {
  const PrintedMushafPage({required this.page, required this.lines});

  final int page;
  final List<PrintedMushafLine> lines;

  factory PrintedMushafPage.fromJson(Map<String, dynamic> json) =>
      PrintedMushafPage(
        page: json['p'] as int,
        lines: List.unmodifiable(
          (json['l'] as List).map(
            (line) => PrintedMushafLine.fromJson(
              Map<String, dynamic>.from(line as Map),
            ),
          ),
        ),
      );
}

class PrintedMushafData {
  const PrintedMushafData({
    required this.version,
    required this.pages,
    required this.canonicalWordCount,
    required this.printedWordCount,
  });

  final int version;
  final List<PrintedMushafPage> pages;
  final int canonicalWordCount;
  final int printedWordCount;

  factory PrintedMushafData.fromJson(Map<String, dynamic> json) =>
      PrintedMushafData(
        version: json['version'] as int,
        canonicalWordCount: json['canonicalWordCount'] as int,
        printedWordCount: json['printedWordCount'] as int,
        pages: List.unmodifiable(
          (json['pages'] as List).map(
            (page) => PrintedMushafPage.fromJson(
              Map<String, dynamic>.from(page as Map),
            ),
          ),
        ),
      );
}
