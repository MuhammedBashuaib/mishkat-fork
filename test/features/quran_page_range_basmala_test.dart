import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_alignment_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = QuranAlignmentEngine();
  const basmala = 'بسم الله الرحمن الرحيم';
  late QuranData quran;
  late List<AuthoritativeWord> page604;

  setUpAll(() async {
    quran = await QuranRepository().load();
    page604 = engine.prepareTargetTokens(
      chapters: quran.chapters,
      startGlobalAyah: quran.page(604).first.global,
      endGlobalAyah: quran.page(604).last.global,
    );
  });

  String surah(int number) => quran.chapter(number).ayahs.join(' ');

  QuranAlignmentResult read(
    List<AuthoritativeWord> target,
    String text, {
    QuranAlignmentResult? after,
    bool isFinal = true,
  }) => engine.align(
    targetWords: target,
    transcript: text,
    committedTargetIndex: after?.committedTargetIndex ?? 0,
    committedAlignedWords: after?.alignedWords,
    committedDiscrepancies: after?.discrepancies,
    isFinal: isFinal,
    followRecitation: true,
  );

  test('page 604 follows all three Surahs with their optional basmalas', () {
    final result = read(
      page604,
      '$basmala ${surah(112)} $basmala ${surah(113)} $basmala ${surah(114)}',
    );
    expect(result.isCompleted, isTrue);
    expect(result.committedTargetIndex, page604.length);
    expect(result.matchedWordsCount, page604.length);
    expect(result.completedGlobalAyahs, hasLength(15));
    expect(result.discrepancies, isEmpty);
  });

  test('a separately spoken basmala cannot award progress or an error', () {
    final ikhlas = read(page604, surah(112));
    final introduction = read(page604, basmala, after: ikhlas);
    expect(introduction.committedTargetIndex, ikhlas.committedTargetIndex);
    expect(introduction.matchedWordsCount, ikhlas.matchedWordsCount);
    expect(introduction.completedGlobalAyahs, ikhlas.completedGlobalAyahs);
    expect(introduction.discrepancies, isEmpty);
    expect(introduction.isCompleted, isFalse);
    expect(
      introduction.alignedWords[ikhlas.committedTargetIndex].status,
      WordAlignmentStatus.upcoming,
    );

    final falaq = read(page604, surah(113), after: introduction);
    final secondIntroduction = read(page604, basmala, after: falaq);
    final nas = read(page604, surah(114), after: secondIntroduction);
    expect(nas.isCompleted, isTrue);
    expect(nas.matchedWordsCount, page604.length);
    expect(nas.discrepancies, isEmpty);
  });

  test('cross-Surah live previews never commit or complete the range', () {
    final text = '${surah(112)} $basmala ${surah(113)} $basmala ${surah(114)}';
    final preview = read(page604, text, isFinal: false);
    expect(preview.committedTargetIndex, 0);
    expect(preview.completedGlobalAyahs, isEmpty);
    expect(preview.isCompleted, isFalse);
    expect(preview.matchedWordsCount, page604.length);
    expect(preview.discrepancies, isEmpty);

    final finalResult = read(page604, text);
    expect(finalResult.isCompleted, isTrue);
  });

  test('an exact live basmala prefix waits at the next Surah opening', () {
    final ikhlas = read(page604, surah(112));
    for (final prefix in ['بسم', 'بسم الله', 'بسم الله الرحمن']) {
      final preview = read(page604, prefix, after: ikhlas, isFinal: false);
      expect(preview.committedTargetIndex, ikhlas.committedTargetIndex);
      expect(preview.matchedWordsCount, ikhlas.matchedWordsCount);
      expect(preview.discrepancies, isEmpty);
      expect(preview.isCompleted, isFalse);
    }
    final falaq = read(page604, '$basmala ${surah(113)}', after: ikhlas);
    expect(falaq.completedGlobalAyahs, hasLength(9));
    expect(falaq.discrepancies, isEmpty);
  });

  test('an incomplete final or malformed basmala cannot skip Quran words', () {
    final ikhlas = read(page604, surah(112));
    for (final text in ['بسم الله', 'بسم الله الملك الرحيم ${surah(113)}']) {
      final result = read(page604, text, after: ikhlas);
      expect(result.committedTargetIndex, ikhlas.committedTargetIndex);
      expect(result.completedGlobalAyahs, ikhlas.completedGlobalAyahs);
      expect(result.isCompleted, isFalse);
      expect(result.uncertainCount, 1);
    }
  });

  test('missing next-Surah opening is not supplied by the basmala', () {
    final ikhlas = read(page604, surah(112));
    final firstFalaq = quran.chapter(113).ayahs.first.split(RegExp(r'\s+'));
    final result = read(
      page604,
      '$basmala ${firstFalaq.skip(1).join(' ')}',
      after: ikhlas,
    );
    expect(
      result.alignedWords[ikhlas.committedTargetIndex].status.isMatched,
      isFalse,
    );
    expect(
      result.completedGlobalAyahs,
      isNot(contains(quran.globalFor(113, 1))),
    );
  });

  test('the numbered Fatiha basmala stays part of the scored Quran', () {
    final fatiha = engine.prepareTargetTokens(
      chapters: quran.chapters,
      startGlobalAyah: 1,
      endGlobalAyah: 7,
    );
    final first = read(fatiha, basmala);
    expect(first.committedTargetIndex, 4);
    expect(first.matchedWordsCount, 4);
    expect(first.completedGlobalAyahs, {1});
    expect(first.discrepancies, isEmpty);
  });

  test('the actual basmala inside An-Naml 30 is scored, not ignored', () {
    final target = engine.prepareTargetTokens(
      chapters: quran.chapters,
      startGlobalAyah: quran.globalFor(27, 30),
      endGlobalAyah: quran.globalFor(27, 30),
    );
    final first = read(target, 'إنه من سليمان وإنه');
    final result = read(target, basmala, after: first);
    expect(result.isCompleted, isTrue);
    expect(result.matchedWordsCount, target.length);
    expect(result.discrepancies, isEmpty);
  });

  test('an inserted basmala inside an ayah is not silently ignored', () {
    final ikhlas = read(page604, surah(112));
    final opening = read(page604, 'قل', after: ikhlas);
    final result = read(page604, '$basmala أعوذ برب الفلق', after: opening);
    expect(result.committedTargetIndex, opening.committedTargetIndex);
    expect(result.isCompleted, isFalse);
    expect(result.uncertainCount, 1);
  });

  test('crossing into At-Tawba does not allow an unnumbered basmala', () {
    final target = engine.prepareTargetTokens(
      chapters: quran.chapters,
      startGlobalAyah: quran.globalFor(8, 75),
      endGlobalAyah: quran.globalFor(9, 1),
    );
    final anfal = read(target, quran.chapter(8).ayahs.last);
    final introduced = read(
      target,
      '$basmala ${quran.chapter(9).ayahs.first}',
      after: anfal,
    );
    expect(introduced.committedTargetIndex, anfal.committedTargetIndex);
    expect(introduced.isCompleted, isFalse);
    expect(introduced.uncertainCount, 1);

    final direct = read(target, quran.chapter(9).ayahs.first, after: anfal);
    expect(direct.isCompleted, isTrue);
    expect(direct.discrepancies, isEmpty);
  });
}
