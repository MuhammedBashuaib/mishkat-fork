import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_artwork_cache.dart';

Future<PictureInfo> _picture() => vg.loadPicture(
  const SvgStringLoader(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>',
  ),
  null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent requests decode once and retain until all leases release',
    () async {
      final completer = Completer<PictureInfo>();
      var decodes = 0;
      final cache = MushafArtworkCache(
        bundle: rootBundle,
        decoder: (_) {
          decodes++;
          return completer.future;
        },
      );
      final first = cache.acquire(8);
      final second = cache.acquire(8);
      final picture = await _picture();
      completer.complete(picture);
      final leases = await Future.wait([first, second]);
      expect(decodes, 1);
      expect(leases[0].picture, same(leases[1].picture));
      cache.clear();
      expect(picture.picture.debugDisposed, isFalse);
      leases[0].release();
      leases[0].release();
      expect(picture.picture.debugDisposed, isFalse);
      leases[1].release();
      expect(picture.picture.debugDisposed, isTrue);
    },
  );

  test(
    'LRU eviction is bounded and does not dispose a displayed page',
    () async {
      var decodes = 0;
      final cache = MushafArtworkCache(
        bundle: rootBundle,
        maxEntries: 2,
        decoder: (_) async {
          decodes++;
          return _picture();
        },
      );
      final visible = await cache.acquire(1);
      final second = await cache.acquire(2);
      second.release();
      final third = await cache.acquire(3);
      third.release();
      expect(second.picture.picture.debugDisposed, isTrue);
      expect(visible.picture.picture.debugDisposed, isFalse);
      final retained = await cache.acquire(3);
      expect(retained.picture, same(third.picture));
      expect(decodes, 3);
      retained.release();
      visible.release();
      cache.clear();
      expect(visible.picture.picture.debugDisposed, isTrue);
      expect(third.picture.picture.debugDisposed, isTrue);
    },
  );

  test('failed requests retry without poisoning the cache', () async {
    var decodes = 0;
    final cache = MushafArtworkCache(
      bundle: rootBundle,
      decoder: (_) async {
        if (++decodes == 1) throw StateError('temporary failure');
        return _picture();
      },
    );
    await expectLater(cache.acquire(8), throwsStateError);
    final lease = await cache.acquire(8);
    expect(decodes, 2);
    lease.release();
    cache.clear();
  });

  test('prefetch reuses nearby pictures and ignores page boundaries', () async {
    var decodes = 0;
    final cache = MushafArtworkCache(
      bundle: rootBundle,
      decoder: (_) async {
        decodes++;
        return _picture();
      },
    );
    await cache.prefetch(0);
    await cache.prefetch(605);
    await cache.prefetch(7);
    final lease = await cache.acquire(7);
    expect(decodes, 1);
    lease.release();
    cache.clear();
  });
}
