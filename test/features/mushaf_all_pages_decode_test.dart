import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_artwork_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'explicit cached asset bundle cannot cross an isolate boundary',
    () async {
      await rootBundle.loadString('assets/data/quran.json');
      const path = 'assets/mushaf/pages/008.svg';
      final bytes = await rootBundle.load(path);
      final loader = SvgAssetLoader(path, assetBundle: rootBundle);
      await expectLater(
        Isolate.run(() => loader.provideSvg(bytes)),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            contains('Illegal argument in isolate message'),
          ),
        ),
      );
    },
  );

  test(
    'raw SVG bytes cross a real isolate boundary after assets are cached',
    () async {
      await rootBundle.loadString('assets/data/quran.json');
      final bytes = await rootBundle.load('assets/mushaf/pages/008.svg');
      final loader = SvgBytesLoader(Uint8List.sublistView(bytes));
      // Exercise the actual SVG compiler across an isolate boundary even
      // though flutter_svg bypasses isolates in Debug/widget tests.
      final compiled = await Isolate.run(() => loader.loadBytes(null));
      expect(compiled.lengthInBytes, greaterThan(0));
      final xml = await Isolate.run(() => loader.provideSvg(null));
      expect(xml, loader.provideSvg(null));
      expect(xml, contains('<svg'));
      final picture = await vg.loadPicture(loader, null);
      expect(picture.size.isEmpty, isFalse);
      picture.picture.dispose();
    },
  );

  test('every bundled Mushaf page decodes into a nonempty vector picture', () async {
    final failures = <String>[];
    final cache = MushafArtworkCache(bundle: rootBundle);
    addTearDown(cache.clear);
    for (var page = 1; page <= 604; page++) {
      try {
        final lease = await cache.acquire(page);
        final picture = lease.picture;
        try {
          expect(picture.size.isEmpty, isFalse, reason: 'Page $page');
        } finally {
          lease.release();
        }
      } catch (error, stack) {
        failures.add(
          'Page $page: $error\n${stack.toString().split('\n').take(5).join('\n')}',
        );
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
