import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('حزمة المصحف مكتملة ومترابطة', () async {
    final data = await QuranRepository().load();
    expect(data.chapters, hasLength(114));
    expect(data.pages, hasLength(604));
    expect(data.chapters.expand((chapter) => chapter.ayahs), hasLength(6236));
    expect(data.page(1).first.global, 1);
    expect(data.page(604).last.global, 6236);
    expect(data.pageForGlobal(data.globalFor(36, 1)), data.chapter(36).page);
  });

  test('concurrent loads share work and reuse decoded data', () async {
    final repository = QuranRepository();
    final first = repository.load();
    final second = repository.load();
    expect(identical(first, second), isTrue);
    final data = await first;
    expect(identical(await repository.load(), data), isTrue);
  });

  test('البحث العربي يتجاهل التشكيل', () async {
    final repository = QuranRepository();
    final data = await repository.load();
    final results = repository.search(data, 'الحمد لله');
    expect(results, isNotEmpty);
    expect(results.first.chapter.number, 1);
  });
}
