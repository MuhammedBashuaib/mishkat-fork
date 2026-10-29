import '../../data/models/quran_models.dart';
import '../../data/models/quran_search_models.dart';
import 'quran_search_normalizer.dart';

/// Intelligent reference parser capable of identifying structured Quranic targets
/// such as Surah:Ayah ("2:255", "البقرة 255"), page numbers ("ص 255"), global Ayahs,
/// and exact Surah names.
class QuranReferenceParser {
  const QuranReferenceParser._();

  static final RegExp _surahAyahSepRegex = RegExp(
    r'^(\d{1,3})[:/\-\s](\d{1,3})$',
  );
  static final RegExp _pageExplicitRegex = RegExp(
    r'^(?:ص|صفحة|صفحه)\s*(\d{1,3})$',
    caseSensitive: false,
  );
  static final RegExp _globalAyahRegex = RegExp(
    r'^(?:#|g|آية|ايه)\s*(\d{1,4})$',
    caseSensitive: false,
  );
  static final RegExp _singleNumberRegex = RegExp(r'^(\d{1,4})$');
  static final RegExp _surahNameAyahRegex = RegExp(r'^(.*?)\s+(\d{1,3})$');

  /// Attempts to parse [rawQuery] into a direct [QuranParsedReference].
  /// Returns `null` if no structured reference can be determined.
  static QuranParsedReference? parse(String rawQuery, QuranData data) {
    var query = rawQuery.trim();
    if (query.isEmpty) return null;

    // Convert Eastern Arabic numerals to standard ASCII
    query = QuranSearchNormalizer.convertArabicDigits(query);

    // 1. Explicit Page Reference: "ص 255", "صفحة 45"
    final pageMatch = _pageExplicitRegex.firstMatch(query);
    if (pageMatch != null) {
      final pageNum = int.tryParse(pageMatch.group(1)!);
      if (pageNum != null && pageNum >= 1 && pageNum <= 604) {
        final info = data.page(pageNum);
        final ch = data.chapter(info.first.surah);
        return QuranParsedReference(
          type: QuranReferenceType.page,
          title: 'صفحة $pageNum',
          subtitle: 'سورة ${ch.name} · آية ${info.first.ayah}',
          page: pageNum,
          globalAyah: info.first.global,
        );
      }
    }

    // 2. Explicit Global Ayah Reference: "#255", "g6236", "آية 1"
    final globalMatch = _globalAyahRegex.firstMatch(query);
    if (globalMatch != null) {
      final gNum = int.tryParse(globalMatch.group(1)!);
      if (gNum != null && gNum >= 1 && gNum <= 6236) {
        final point = data.pointForGlobal(gNum);
        final page = data.pageForGlobal(gNum);
        final ch = data.chapter(point.surah);
        return QuranParsedReference(
          type: QuranReferenceType.globalAyah,
          title: 'آية رقم $gNum (بالترتيب الشامل)',
          subtitle: 'سورة ${ch.name} · آية ${point.ayah} · صفحة $page',
          page: page,
          surah: point.surah,
          ayah: point.ayah,
          globalAyah: gNum,
        );
      }
    }

    // 3. Numeric Surah:Ayah Reference: "2:255", "2/255", "2 255", "2-255"
    final surahAyahMatch = _surahAyahSepRegex.firstMatch(query);
    if (surahAyahMatch != null) {
      final surahNum = int.tryParse(surahAyahMatch.group(1)!);
      final ayahNum = int.tryParse(surahAyahMatch.group(2)!);
      if (surahNum != null &&
          ayahNum != null &&
          surahNum >= 1 &&
          surahNum <= 114) {
        final ch = data.chapter(surahNum);
        if (ayahNum >= 1 && ayahNum <= ch.ayahs.length) {
          final global = data.globalFor(surahNum, ayahNum);
          final page = data.pageForGlobal(global);
          return QuranParsedReference(
            type: QuranReferenceType.ayah,
            title: 'سورة ${ch.name} · آية $ayahNum',
            subtitle: 'صفحة $page · ${ch.revelationType}',
            page: page,
            surah: surahNum,
            ayah: ayahNum,
            globalAyah: global,
          );
        }
      }
    }

    // 4. Surah Name + Ayah: "البقرة 255", "سورة الكهف 10", "ال عمران 18"
    final nameAyahMatch = _surahNameAyahRegex.firstMatch(query);
    if (nameAyahMatch != null) {
      var namePart = nameAyahMatch.group(1)!.trim();
      final ayahNum = int.tryParse(nameAyahMatch.group(2)!);
      if (namePart.startsWith('سورة ')) {
        namePart = namePart.substring(5).trim();
      }
      final normName = QuranSearchNormalizer.normalize(namePart);
      if (normName.isNotEmpty && ayahNum != null) {
        for (final ch in data.chapters) {
          final chNorm = QuranSearchNormalizer.normalize(ch.name);
          final chEnNorm = QuranSearchNormalizer.normalize(ch.englishName);
          if (chNorm == normName ||
              chEnNorm == normName ||
              chNorm == 'ال$normName' ||
              'ال$chNorm' == normName) {
            if (ayahNum >= 1 && ayahNum <= ch.ayahs.length) {
              final global = data.globalFor(ch.number, ayahNum);
              final page = data.pageForGlobal(global);
              return QuranParsedReference(
                type: QuranReferenceType.ayah,
                title: 'سورة ${ch.name} · آية $ayahNum',
                subtitle: 'صفحة $page · ${ch.revelationType}',
                page: page,
                surah: ch.number,
                ayah: ayahNum,
                globalAyah: global,
              );
            }
          }
        }
      }
    }

    // 5. Single Number: e.g. "255" or "1"
    final singleMatch = _singleNumberRegex.firstMatch(query);
    if (singleMatch != null) {
      final num = int.tryParse(singleMatch.group(1)!);
      if (num != null && num >= 1 && num <= 604) {
        final info = data.page(num);
        final ch = data.chapter(info.first.surah);
        return QuranParsedReference(
          type: QuranReferenceType.page,
          title: 'صفحة $num',
          subtitle: 'سورة ${ch.name} · آية ${info.first.ayah}',
          page: num,
          globalAyah: info.first.global,
        );
      }
    }

    // 6. Direct Surah Name Match: "البقرة", "سورة يوسف"
    var surahQuery = query;
    if (surahQuery.startsWith('سورة ')) {
      surahQuery = surahQuery.substring(5).trim();
    }
    final normSurahQuery = QuranSearchNormalizer.normalize(surahQuery);
    if (normSurahQuery.isNotEmpty) {
      for (final ch in data.chapters) {
        final chNorm = QuranSearchNormalizer.normalize(ch.name);
        if (chNorm == normSurahQuery ||
            chNorm == 'ال$normSurahQuery' ||
            'ال$chNorm' == normSurahQuery) {
          return QuranParsedReference(
            type: QuranReferenceType.surah,
            title: 'سورة ${ch.name}',
            subtitle:
                '${ch.revelationType} · ${ch.ayahs.length} آية · صفحة ${ch.page}',
            page: ch.page,
            surah: ch.number,
            globalAyah: ch.globalStart,
          );
        }
      }
    }

    return null;
  }
}
