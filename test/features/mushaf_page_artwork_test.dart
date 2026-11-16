import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_coordinate_mapper.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_artwork_cache.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_page_artwork.dart';

class _PageBundle extends CachingAssetBundle {
  _PageBundle({this.svg});

  final String? svg;
  int loads = 0;
  bool fail = false;
  bool failOnce = false;
  final reads = <String, int>{};
  final gates = <String, Completer<void>>{};

  @override
  Future<ByteData> load(String key) async {
    loads++;
    reads.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (gates[key] case final gate?) await gate.future;
    if (failOnce) {
      failOnce = false;
      throw StateError('Temporary page read failure');
    }
    if (fail) throw StateError('Page unavailable');
    return ByteData.sublistView(
      Uint8List.fromList(
        utf8.encode(
          svg ??
              '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10 -20 100 100">
  <rect x="0" y="-10" width="10" height="10" fill="#ff0000"/>
  <rect x="0" y="60" width="10" height="10" fill="#0000ff"/>
</svg>''',
        ),
      ),
    );
  }
}

void main() {
  const viewBox = Rect.fromLTWH(-10, -20, 100, 100);
  const mapper = MushafCoordinateMapper(
    contentPadding: EdgeInsets.zero,
    lineBreaks: [30],
  );

  Future<void> mount(
    WidgetTester tester,
    _PageBundle bundle, {
    GlobalKey? boundaryKey,
    ColorFilter? colorFilter,
    Size size = const Size(100, 200),
    int page = 1,
    MushafCoordinateMapper pageMapper = mapper,
    Rect pageViewBox = viewBox,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: bundle,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox.fromSize(
                size: size,
                child: MushafPageArtwork(
                  page: page,
                  viewBox: pageViewBox,
                  mapper: pageMapper,
                  colorFilter: colorFilter,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  MushafPageArtworkPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.painter)
      .whereType<MushafPageArtworkPainter>()
      .single;

  testWidgets(
    'safe bands move ink without stretching or losing viewBox offsets',
    (tester) async {
      final key = GlobalKey();
      await mount(tester, _PageBundle(), boundaryKey: key);
      final pixels = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      });
      List<int> rgba(int x, int y) =>
          pixels!.sublist((y * 100 + x) * 4, (y * 100 + x) * 4 + 4);
      expect(rgba(15, 15), [255, 0, 0, 255]);
      expect(rgba(15, 185), [0, 0, 255, 255]);
      expect(rgba(15, 85).last, 0);
      expect(rgba(15, 115).last, 0);
      expect(rgba(15, 25).last, 0);
      expect(rgba(25, 15).last, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('appearance and viewport changes reuse the decoded page', (
    tester,
  ) async {
    final bundle = _PageBundle();
    await mount(tester, bundle);
    final original = painter(tester).picture;
    const filter = ColorFilter.mode(Colors.white, BlendMode.srcIn);
    await mount(
      tester,
      bundle,
      colorFilter: filter,
      size: const Size(200, 400),
    );
    expect(painter(tester).picture, same(original));
    expect(painter(tester).colorFilter, filter);
    expect(bundle.reads['assets/mushaf/pages/001.svg'], 1);
    await mount(tester, bundle, page: 2);
    expect(original.picture.debugDisposed, isFalse);
    final replacement = painter(tester).picture;
    expect(replacement, isNot(same(original)));
    expect(bundle.reads['assets/mushaf/pages/002.svg'], 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(replacement.picture.debugDisposed, isFalse);
    MushafArtworkCache.forBundle(bundle).clear();
    expect(original.picture.debugDisposed, isTrue);
    expect(replacement.picture.debugDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed page load can be retried', (tester) async {
    final bundle = _PageBundle()..fail = true;
    await mount(tester, bundle);
    expect(find.text('تعذر تحميل صفحة المصحف. إعادة المحاولة'), findsOneWidget);
    bundle.fail = false;
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل صفحة المصحف. إعادة المحاولة'), findsNothing);
    expect(painter(tester).picture.size, const Size(100, 100));
    expect(bundle.reads['assets/mushaf/pages/001.svg'], 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temporary failure recovers without requiring a tap', (
    tester,
  ) async {
    final bundle = _PageBundle()..failOnce = true;
    await mount(tester, bundle);
    expect(find.text('تعذر تحميل صفحة المصحف. إعادة المحاولة'), findsNothing);
    expect(painter(tester).picture.size, const Size(100, 100));
    expect(bundle.reads['assets/mushaf/pages/001.svg'], 2);
  });

  testWidgets('returning to a nearby page reuses its ready picture', (
    tester,
  ) async {
    final bundle = _PageBundle();
    await mount(tester, bundle, page: 8);
    final original = painter(tester).picture;
    await mount(tester, bundle, page: 9);
    await mount(tester, bundle, page: 8);
    expect(painter(tester).picture, same(original));
    expect(bundle.reads['assets/mushaf/pages/008.svg'], 1);
    expect(find.text('تعذر تحميل صفحة المصحف. إعادة المحاولة'), findsNothing);
  });

  testWidgets(
    'late page load cannot replace a newer page or update disposed state',
    (tester) async {
      final bundle = _PageBundle();
      final gate = Completer<void>();
      bundle.gates['assets/mushaf/pages/010.svg'] = gate;
      Widget app(int page) => MaterialApp(
        home: DefaultAssetBundle(
          bundle: bundle,
          child: SizedBox(
            width: 100,
            height: 200,
            child: MushafPageArtwork(
              page: page,
              viewBox: viewBox,
              mapper: mapper,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(10));
      await tester.pumpWidget(app(20));
      await tester.pumpAndSettle();
      final current = painter(tester).picture;
      gate.complete();
      await tester.pumpAndSettle();
      expect(painter(tester).picture, same(current));
      await tester.pumpWidget(const SizedBox.shrink());
      MushafArtworkCache.forBundle(bundle).clear();
      expect(current.picture.debugDisposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('curved seams preserve ink extending across nominal row bounds', (
    tester,
  ) async {
    final bundle = _PageBundle(
      svg: '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect x="15" y="55" width="10" height="10" fill="#ff0000"/>
  <rect x="65" y="35" width="10" height="10" fill="#0000ff"/>
</svg>''',
    );
    const curvedMapper = MushafCoordinateMapper(
      contentPadding: EdgeInsets.zero,
      lineSeams: [
        [
          Offset(0, 50),
          Offset(8, 50),
          Offset(10, 70),
          Offset(30, 70),
          Offset(32, 50),
          Offset(58, 50),
          Offset(60, 30),
          Offset(80, 30),
          Offset(82, 50),
          Offset(100, 50),
        ],
      ],
    );
    final key = GlobalKey();
    await mount(
      tester,
      bundle,
      boundaryKey: key,
      pageMapper: curvedMapper,
      pageViewBox: const Rect.fromLTWH(0, 0, 100, 100),
    );
    final pixels = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
      } finally {
        image.dispose();
      }
    });
    var redPixels = 0;
    var bluePixels = 0;
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 100; x++) {
        final offset = (y * 100 + x) * 4;
        if (pixels![offset + 3] == 0) continue;
        if (pixels[offset] == 255) {
          redPixels++;
          expect(x, inInclusiveRange(15, 24));
          expect(y, inInclusiveRange(55, 64));
        } else if (pixels[offset + 2] == 255) {
          bluePixels++;
          expect(x, inInclusiveRange(65, 74));
          expect(y, inInclusiveRange(135, 144));
        } else {
          fail('Unexpected ink at $x, $y');
        }
      }
    }
    expect(redPixels, 100, reason: 'Every upper-line pixel is retained once');
    expect(bluePixels, 100, reason: 'Every lower-line pixel is retained once');
    expect(tester.takeException(), isNull);
  });
}
