import 'dart:math';

/// Orthographic equivalence for recitation, deliberately stricter than search.
/// Similar-looking Quranic words must not be awarded a correct match.
class QuranRecitationText {
  const QuranRecitationText._();

  static final _marks = RegExp(
    r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u08D3-\u08FF\u0640]',
  );
  static final _arabicLetter = RegExp(r'[ء-يٱ-ۓۺ-ۿ]');
  static final _nonSpeech = RegExp(r'\[[^\]]*\]|\([^)]*\)|\*[^*]*\*');
  static final _nonArabic = RegExp(
    r'[^\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF…\s]',
  );
  static final _hallucinations = <RegExp>[
    RegExp(r'اشتركوا?\s*(في)?\s*(ال)?قناة'),
    RegExp(r'لا\s*تنس(وا)?\s*(ال)?اشتراك'),
    RegExp(r'شكرا\s*(لكم)?\s*(على)?\s*(ال)?مشاهدة'),
    RegExp(r'(ال)?مشاهدة\s+ممتعة'),
    RegExp(r'نانسي\s+قنقر'),
    RegExp(r'شركة\s+\S+\s+للخدمات\s+\S+'),
    RegExp(r'موسيقى'),
  ];

  static const unclearWord = '…';
  static const letterNames = <String, List<String>>{
    'الم': ['الف', 'لام', 'ميم'],
    'المص': ['الف', 'لام', 'ميم', 'صاد'],
    'الر': ['الف', 'لام', 'را'],
    'المر': ['الف', 'لام', 'ميم', 'را'],
    'كهيعص': ['كاف', 'ها', 'يا', 'عين', 'صاد'],
    'طه': ['طا', 'ها'],
    'طسم': ['طا', 'سين', 'ميم'],
    'طس': ['طا', 'سين'],
    'يس': ['يا', 'سين'],
    'ص': ['صاد'],
    'حم': ['حا', 'ميم'],
    'عسق': ['عين', 'سين', 'قاف'],
    'ق': ['قاف'],
    'ن': ['نون'],
  };

  static bool hasArabicLetter(String value) => _arabicLetter.hasMatch(value);

  static String normalize(String value) => value
      .replaceAll(RegExp(r'[ﻵﻶﻷﻸﻹﻺﻻﻼ]'), 'لا')
      .replaceAll(_marks, '')
      .replaceAll('ءا', 'ا')
      .replaceAll(RegExp(r'[أإآٱٲٳٵ]'), 'ا')
      .replaceAll(RegExp(r'[ىئی]'), 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ة', 'ه')
      .replaceAll('ک', 'ك')
      .replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'),
        '',
      )
      .trim();

  /// Keeps repetitions: a repeated word can be real practice or self-correction.
  /// The aligner, rather than a destructive text rewrite, resolves these runs.
  static List<String> transcriptWords(String raw) {
    var text = raw.replaceAll(_nonSpeech, ' ');
    final bare = text.replaceAll(_marks, '');
    if (_hallucinations.any((pattern) => pattern.hasMatch(bare))) {
      text = bare;
      for (final pattern in _hallucinations) {
        text = text.replaceAll(pattern, ' ');
      }
    }
    text = text.replaceAll(_nonArabic, ' ').replaceAll(RegExp(r'[،؛؟۔]'), ' ');
    return text
        .split(RegExp(r'\s+'))
        .map((word) => word.trim())
        .where((word) => word == unclearWord || hasArabicLetter(word))
        .toList(growable: false);
  }

  /// Allowed differences are derived from the actual Uthmani spelling.
  /// In particular, قل/قال, يعلمون/تعلمون and وإن/إن remain different words.
  static Set<String> spellings(String uthmani) {
    final expandedAlef = uthmani
        .replaceAll(RegExp(r'ى[\u064B-\u065F]*ٰ'), 'ى')
        .replaceAll(RegExp(r'و[\u064B-\u065F]*ٰ'), 'ا')
        .replaceAll('ٰ', 'ا')
        .replaceAllMapped(RegExp(r'ۦ(?=[ء-ي])'), (_) => 'ي');
    final withoutSilentLetters = uthmani.replaceAll(
      RegExp(r'[ء-ي][\u064B-\u065F]*۟'),
      '',
    );
    final forms = <String>{
      normalize(uthmani),
      normalize(expandedAlef),
      normalize(withoutSilentLetters),
    }..remove('');

    // The night and dual relative pronouns use a second lam in modern spelling.
    // The plural الذين must not accept اللذين (a different grammatical form).
    for (final form in forms.toList()) {
      final dualOblique =
          RegExp(r'[ذت]َيْن').hasMatch(uthmani) &&
          RegExp(r'^[وفبك]?ال[ذت]ين$').hasMatch(form);
      if (RegExp(r'^[وفبك]?ال(يل|ذان|تان)$').hasMatch(form) || dualOblique) {
        forms.add(
          form.replaceFirstMapped(RegExp(r'^([وفبك]?)ال'), (m) => '${m[1]}الل'),
        );
      }
    }
    if (RegExp(r'ً[ۭۢ]?ا$').hasMatch(uthmani)) {
      for (final form in forms.toList()) {
        if (form.endsWith('ا')) forms.add(form.substring(0, form.length - 1));
      }
    }
    if (RegExp(r'[ًٌٍ]').hasMatch(uthmani)) {
      for (final form in forms.toList()) {
        final base = form.endsWith('ا')
            ? form.substring(0, form.length - 1)
            : form;
        if (base.length >= 2) forms.add('$baseن');
      }
    }
    return forms;
  }

  static bool sameWord(String uthmani, String recognized) {
    final actual = normalize(recognized);
    return actual.isNotEmpty && spellings(uthmani).contains(actual);
  }

  /// Approximate similarity locates a mismatch; it never makes it correct.
  static double similarity(String expected, String recognized) {
    if (sameWord(expected, recognized)) return 1;
    final a = normalize(expected);
    final b = normalize(recognized);
    if (a.isEmpty || b.isEmpty) return 0;
    return min(0.9, 1 - _distance(a, b) / max(a.length, b.length));
  }

  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        current[j] = min(
          min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }
}
