import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/adhkar_models.dart';

class AdhkarRepository {
  List<AdhkarCategory>? _cache;

  Future<List<AdhkarCategory>> load() async {
    if (_cache case final List<AdhkarCategory> data) return data;
    final decoded = jsonDecode(
      await rootBundle.loadString('assets/data/adhkar.json'),
    ) as List;
    final categories = decoded
        .map(
          (item) =>
              AdhkarCategory.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    _splitMorningAndEvening(categories);
    _cache = categories;
    return categories;
  }

  /// The source edition combines both daily wirds in one chapter and puts the
  /// evening alternative between brackets.  A reader should never have to
  /// translate those alternatives while reciting, so the app exposes two
  /// focused chapters with independent progress.
  void _splitMorningAndEvening(List<AdhkarCategory> categories) {
    final sourceIndex = categories.indexWhere((item) => item.id == 1);
    if (sourceIndex < 0) return;
    final source = categories[sourceIndex];
    final morning = <DhikrItem>[];
    final evening = <DhikrItem>[];

    for (var index = 0; index < source.items.length; index++) {
      final item = source.items[index];
      // The same tahlil is narrated with different counts. Present it once;
      // retain the source's morning-only hundred-count option.
      if (index == 18) continue;
      // Three narrations in the source are specific to the morning.
      if (index != 18 && index != 19 && index != 20) {
        evening.add(
          DhikrItem(
            text: _dailyWirdText(item.text, index, evening: true),
            count: index == 8 ? 7 : item.count,
            title: item.title,
            countOptions: index == 17 ? const [1, 10] : const [],
            note: index == 17
                ? 'عشر مرات، أو مرة واحدة عند الكسل؛ كما ورد في حصن المسلم.'
                : '',
          ),
        );
      }
      // "أعوذ بكلمات الله التامات" here is the evening-specific narration.
      if (index != 22) {
        morning.add(
          DhikrItem(
            text: _dailyWirdText(item.text, index, evening: false),
            count: index == 8 ? 7 : item.count,
            title: item.title,
            countOptions: index == 17 ? const [1, 10, 100] : const [],
            note: index == 17
                ? 'ورد عشر مرات، أو مرة واحدة عند الكسل، وورد مائة مرة في الصباح. اختر العدد لوردك.'
                : '',
          ),
        );
      }
    }

    categories[sourceIndex] = AdhkarCategory(
      id: 1,
      name: 'أذكار الصباح',
      items: morning,
    );
    categories.insert(
      sourceIndex + 1,
      AdhkarCategory(id: 133, name: 'أذكار المساء', items: evening),
    );
  }

  String _dailyWirdText(String text, int index, {required bool evening}) {
    if (index == 17) {
      return text.substring(2, text.indexOf('))'));
    }
    if (!evening) {
      return text.replaceAll(RegExp(r'\s*\[\s*و?إذا أمسى[^\]]*\]'), '').trim();
    }

    final withoutAlternatives = text
        .replaceAll(RegExp(r'\s*\[\s*و?إذا أمسى[^\]]*\]'), '')
        .trim();
    switch (index) {
      case 2:
        return withoutAlternatives
            .replaceAll('أَصْبَحْنَا', 'أَمْسَيْنَا')
            .replaceAll('وَأَصْبَحَ', 'وَأَمْسَى')
            .replaceAll('هَذَا الْيَوْمِ', 'هَذِهِ اللَّيْلَةِ')
            .replaceAll('مَا بَعْدَهُ', 'مَا بَعْدَهَا');
      case 3:
        return '((اللَّهُمَّ بِكَ أَمْسَيْنَا، وَبِكَ أَصْبَحْنَا، وَبِكَ نَحْيَا، '
            'وَبِكَ نَمُوتُ وَإِلَيْكَ الْمَصِيرُ)).';
      case 5:
        return withoutAlternatives.replaceAll('أَصْبَحْتُ', 'أَمْسَيْتُ');
      case 6:
        return withoutAlternatives.replaceAll('أَصْبَحَ بِي', 'أَمْسَى بِي');
      case 14:
        return text
            .substring(text.indexOf('قال:') + 4, text.lastIndexOf(']'))
            .trim();
      case 15:
        return withoutAlternatives.replaceAll('أَصْبَحْنا', 'أَمْسَيْنا');
      default:
        return withoutAlternatives;
    }
  }
}
