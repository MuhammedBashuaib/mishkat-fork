import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/library/data/models/library_models.dart';
import 'package:mishkat_app/features/library/data/repositories/library_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'background book parsing preserves every bundled entry and cache',
    () async {
      final repository = LibraryRepository();
      final catalog = await repository.loadCatalog();
      for (final book in catalog.where(
        (book) => book.contentType != 'tafsir',
      )) {
        final raw = await rootBundle.loadString(
          'assets/data/${book.contentPath.split('/').last}',
        );
        final expected = ((jsonDecode(raw) as Map)['entries'] as List)
            .map(
              (entry) => LibraryEntry.fromJson(
                Map<String, dynamic>.from(entry as Map),
              ),
            )
            .toList();
        final actual = await repository.loadBook(book);
        expect(actual, expected, reason: book.id);
        expect(identical(await repository.loadBook(book), actual), isTrue);
      }
    },
  );

  test(
    'background tafsir parsing preserves all verses and source links',
    () async {
      final repository = LibraryRepository();
      final book = (await repository.loadCatalog()).firstWhere(
        (book) => book.contentType == 'tafsir',
      );
      final entries = await repository.loadBook(book);
      expect(entries, hasLength(6236));
      expect(entries.first.id, 'tafsir-1');
      expect(entries.last.id, 'tafsir-6236');
      expect(
        entries.every((entry) => entry.sourceUrl == book.sourceUrl),
        isTrue,
      );
      final tafsir = jsonDecode(
        await rootBundle.loadString('assets/data/tafsir-muyassar.json'),
      ) as Map;
      for (var index = 0; index < entries.length; index++) {
        expect(entries[index].number, index + 1);
        expect(
          entries[index].text,
          endsWith('${tafsir['entries']['${index + 1}']}'),
        );
      }
    },
  );
}
