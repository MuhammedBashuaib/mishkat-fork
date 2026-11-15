import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/mushaf_layout_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_line_breaks_repository.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_coordinate_mapper.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_line_layout.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_visual_mask_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const viewBox = Rect.fromLTWH(0, 0, 345, 550);
  const tallSize = Size(345, 850);
  const mapper = MushafCoordinateMapper(
    contentPadding: EdgeInsets.zero,
    lineBreaks: [100, 300],
  );

  test(
    'tall pages fill the height by spacing lines without stretching ink',
    () {
      final bands = mapper.getBands(contentSize: tallSize, viewBox: viewBox);
      expect(bands, hasLength(3));
      expect(bands.first.source.top, viewBox.top);
      expect(bands.last.source.bottom, viewBox.bottom);
      expect(bands.first.destination.top, 0);
      expect(bands.last.destination.bottom, tallSize.height);
      expect(bands[0].destination, const Rect.fromLTRB(0, 0, 345, 100));
      expect(bands[1].destination, const Rect.fromLTRB(0, 250, 345, 450));
      expect(bands[2].destination, const Rect.fromLTRB(0, 600, 345, 850));
      for (var index = 0; index < bands.length; index++) {
        final band = bands[index];
        expect(band.scale, 1);
        expect(
          band.destination.height / band.source.height,
          closeTo(band.scale, 1e-10),
        );
        if (index > 0) {
          expect(band.source.top, bands[index - 1].source.bottom);
          expect(
            band.destination.top - bands[index - 1].destination.bottom,
            150,
          );
        }
      }
      expect(
        mapper.getSvgDestinationRect(contentSize: tallSize, viewBox: viewBox),
        Offset.zero & tallSize,
      );
    },
  );

  test('short pages preserve the original centered contain fit', () {
    const size = Size(844, 390);
    const original = MushafCoordinateMapper(contentPadding: EdgeInsets.zero);
    final destination = original.getSvgDestinationRect(
      contentSize: size,
      viewBox: viewBox,
    );
    expect(
      mapper.getSvgDestinationRect(contentSize: size, viewBox: viewBox),
      destination,
    );
    final bands = mapper.getBands(contentSize: size, viewBox: viewBox);
    for (var index = 0; index < bands.length; index++) {
      final band = bands[index];
      expect(band.destination.left, closeTo(destination.left, 1e-10));
      expect(band.destination.width, closeTo(destination.width, 1e-10));
      expect(
        band.destination.height / band.source.height,
        closeTo(band.scale, 1e-10),
      );
      if (index > 0) {
        expect(
          band.destination.top,
          closeTo(bands[index - 1].destination.bottom, 1e-10),
        );
      }
    }
  });

  test('unsegmented opening pages keep their viewBox and original fit', () {
    const opening = Rect.fromLTWH(-53.3109, -198.4777, 345, 550);
    final bands = const MushafLineLayout().getBands(
      contentSize: tallSize,
      viewBox: opening,
    );
    expect(bands, hasLength(1));
    expect(bands.single.source, opening);
    expect(bands.single.destination, const Rect.fromLTWH(0, 150, 345, 550));
  });

  test('layout respects asymmetric padding and offset source coordinates', () {
    const shifted = Rect.fromLTWH(-50, -200, 345, 550);
    const shiftedMapper = MushafCoordinateMapper(
      contentPadding: EdgeInsets.fromLTRB(13, 17, 42, 33),
      lineBreaks: [-100, 100],
    );
    final bands = shiftedMapper.getBands(
      contentSize: const Size(400, 900),
      viewBox: shifted,
    );
    expect(bands.first.source, const Rect.fromLTRB(-50, -200, 295, -100));
    expect(bands.first.destination, const Rect.fromLTWH(13, 17, 345, 100));
    expect(bands.last.destination.bottom, 867);
    for (final point in [
      shifted.topLeft,
      const Offset(100, -100),
      const Offset(100, 100),
      shifted.bottomRight,
    ]) {
      final local = shiftedMapper.viewBoxToLocal(
        viewBoxCoordinate: point,
        contentSize: const Size(400, 900),
        viewBox: shifted,
      );
      final restored = shiftedMapper.localToViewBox(
        localPosition: local,
        contentSize: const Size(400, 900),
        viewBox: shifted,
      );
      expect(restored, point);
    }
    expect(
      shiftedMapper.getSvgDestinationRect(
        contentSize: tallSize,
        viewBox: shifted,
        padding: EdgeInsets.zero,
      ),
      Offset.zero & tallSize,
    );
  });

  test('hit testing follows each line and rejects the new blank gaps', () {
    final bands = mapper.getBands(contentSize: tallSize, viewBox: viewBox);
    for (final band in bands) {
      for (final point in [
        band.source.topLeft,
        band.source.center,
        band.source.bottomRight,
      ]) {
        final local = mapper.viewBoxToLocal(
          viewBoxCoordinate: point,
          contentSize: tallSize,
          viewBox: viewBox,
        );
        expect(
          mapper.localToViewBox(
            localPosition: local,
            contentSize: tallSize,
            viewBox: viewBox,
          ),
          point,
        );
      }
    }
    for (final point in [
      const Offset(150, 175),
      const Offset(150, 525),
      const Offset(-2, 50),
      const Offset(347, 50),
      const Offset(150, -2),
      const Offset(150, 852),
    ]) {
      expect(
        mapper.localToViewBox(
          localPosition: point,
          contentSize: tallSize,
          viewBox: viewBox,
        ),
        isNull,
      );
    }
  });

  test('selection edges at a cut stay attached to their own line', () {
    final bands = mapper.getBands(contentSize: tallSize, viewBox: viewBox);
    for (final band in bands) {
      expect(
        mapper.viewBoxRectToLocal(
          viewBoxRect: band.source,
          contentSize: tallSize,
          viewBox: viewBox,
        ),
        band.destination,
      );
    }
    expect(
      mapper.viewBoxRectToLocal(
        viewBoxRect: const Rect.fromLTRB(10, 90, 100, 100),
        contentSize: tallSize,
        viewBox: viewBox,
      ),
      const Rect.fromLTRB(10, 90, 100, 100),
    );
    expect(
      mapper.viewBoxRectToLocal(
        viewBoxRect: const Rect.fromLTRB(10, 100, 100, 110),
        contentSize: tallSize,
        viewBox: viewBox,
      ),
      const Rect.fromLTRB(10, 250, 100, 260),
    );
    // Multi-line verse rectangles still conceal every line they span.
    expect(
      mapper.viewBoxRectToLocal(
        viewBoxRect: const Rect.fromLTRB(10, 90, 100, 310),
        contentSize: tallSize,
        viewBox: viewBox,
      ),
      const Rect.fromLTRB(10, 90, 100, 610),
    );
  });

  test('invalid cuts cannot create empty or overlapping source slices', () {
    final layout = MushafLineLayout(
      lineBreaks: [550, 300, 100, 100, 0, -1, 900, double.nan, double.infinity],
    );
    final bands = layout.getBands(contentSize: tallSize, viewBox: viewBox);
    expect(bands.map((band) => band.source), [
      const Rect.fromLTRB(0, 0, 345, 100),
      const Rect.fromLTRB(0, 100, 345, 300),
      const Rect.fromLTRB(0, 300, 345, 550),
    ]);
    expect(layout.getBands(contentSize: Size.zero, viewBox: viewBox), isEmpty);
    expect(layout.getBands(contentSize: tallSize, viewBox: Rect.zero), isEmpty);
  });

  group('curved whitespace seams', () {
    const seams = [
      [Offset(0, 100), Offset(100, 80), Offset(200, 120), Offset(345, 100)],
      [Offset(0, 300), Offset(100, 280), Offset(200, 320), Offset(345, 300)],
    ];
    const curvedMapper = MushafCoordinateMapper(
      contentPadding: EdgeInsets.zero,
      lineSeams: seams,
    );

    Offset local(Offset point) => curvedMapper.viewBoxToLocal(
      viewBoxCoordinate: point,
      contentSize: tallSize,
      viewBox: viewBox,
    );

    test('bands keep overhanging ink in the correct original line', () {
      final bands = curvedMapper.getBands(
        contentSize: tallSize,
        viewBox: viewBox,
      );
      expect(bands.first.source, const Rect.fromLTRB(0, 0, 345, 120));
      expect(bands[1].source, const Rect.fromLTRB(0, 80, 345, 320));
      expect(bands[1].destination, const Rect.fromLTRB(0, 230, 345, 470));
      expect(bands.last.destination.bottom, tallSize.height);
      // The same y belongs to different lines on opposite sides of the seam.
      expect(local(const Offset(100, 90)), const Offset(100, 240));
      expect(local(const Offset(200, 90)), const Offset(200, 90));
      expect(bands.first.sourceClip.contains(const Offset(100, 90)), isFalse);
      expect(bands[1].sourceClip.contains(const Offset(100, 90)), isTrue);
      expect(bands.first.sourceClip.contains(const Offset(200, 90)), isTrue);
      for (final band in bands) {
        expect(band.destination.width / band.source.width, 1);
        expect(band.destination.height / band.source.height, 1);
      }
    });

    test(
      'every line round-trips, including points on seams and page edges',
      () {
        for (var x = 0.0; x <= 345; x += 11.5) {
          for (var y = 0.0; y <= 550; y += 5.5) {
            final point = Offset(x, y);
            final restored = curvedMapper.localToViewBox(
              localPosition: local(point),
              contentSize: tallSize,
              viewBox: viewBox,
            );
            expect(restored, isNotNull, reason: '$point disappeared at a seam');
            expect(restored!.dx, closeTo(point.dx, 1e-7));
            expect(restored.dy, closeTo(point.dy, 1e-7));
          }
          for (final seam in seams) {
            final edge = MushafLineBand.boundaryY(seam, x);
            final gap = Offset(x, local(Offset(x, edge)).dy - 75);
            expect(
              curvedMapper.localToViewBox(
                localPosition: gap,
                contentSize: tallSize,
                viewBox: viewBox,
              ),
              isNull,
              reason: 'Inserted whitespace is not an ayah target: $gap',
            );
          }
        }
      },
    );

    test('rectangles and polygons split around seams without filling gaps', () {
      final rectangle = curvedMapper.viewBoxRectToLocalPath(
        viewBoxRect: const Rect.fromLTRB(90, 70, 110, 100),
        contentSize: tallSize,
        viewBox: viewBox,
      );
      expect(rectangle.contains(const Offset(100, 75)), isTrue);
      expect(rectangle.contains(const Offset(100, 240)), isTrue);
      expect(rectangle.contains(const Offset(100, 150)), isFalse);
      expect(rectangle.contains(const Offset(100, 90)), isFalse);
      final polygon = curvedMapper.viewBoxPathToLocal(
        points: const [Offset(90, 70), Offset(110, 70), Offset(100, 100)],
        contentSize: tallSize,
        viewBox: viewBox,
      );
      expect(polygon.contains(const Offset(100, 75)), isTrue);
      expect(polygon.contains(const Offset(100, 240)), isTrue);
      expect(polygon.contains(const Offset(100, 150)), isFalse);
      expect(polygon.contains(const Offset(100, 90)), isFalse);
    });

    test('ayah-number badges stay circular close to a curved seam', () {
      const ayah = AyahBounds(
        globalAyah: 13,
        surah: 2,
        ayah: 6,
        page: 3,
        bounds: Rect.fromLTRB(80, 70, 120, 110),
        segments: [AyahRectSegment(Rect.fromLTRB(80, 70, 120, 110))],
        numberCenter: Offset(100, 85),
      );
      final window = const VisualMaskPainter(
        maskedAyahs: [ayah],
        viewBox: viewBox,
        mapper: curvedMapper,
        maskColor: Colors.white,
      ).ayahNumberWindow(ayah, tallSize)!;
      expect(window.center, const Offset(100, 235));
      expect(window.size, const Size(20, 20));
    });
  });

  test('all printed ayah targets and masks follow the bundled line seams', () async {
    final geometry = await MushafLayoutRepository().load();
    final seamsByPage = await MushafLineBreaksRepository().load();
    expect(seamsByPage.length, 604);
    var checkedMarkers = 0;
    var checkedSegments = 0;
    for (final size in [
      const Size(320, 568),
      const Size(430, 932),
      const Size(844, 390),
    ]) {
      for (final page in geometry.pages) {
        final mapper = MushafCoordinateMapper(
          contentPadding: EdgeInsets.zero,
          lineSeams: seamsByPage[page.page]!,
        );
        final bands = mapper.getBands(contentSize: size, viewBox: page.viewBox);
        expect(bands, isNotEmpty);
        for (final band in bands) {
          expect(
            band.destination.height / band.source.height,
            closeTo(band.scale, 1e-6),
            reason: 'Page ${page.page} at $size must retain glyph proportions',
          );
        }

        Offset checkPoint(Offset source, int global) {
          final local = mapper.viewBoxToLocal(
            viewBoxCoordinate: source,
            contentSize: size,
            viewBox: page.viewBox,
          );
          final restored = mapper.localToViewBox(
            localPosition: local,
            contentSize: size,
            viewBox: page.viewBox,
          );
          final reason = 'Page ${page.page}, ayah $global, $source at $size';
          expect(restored, isNotNull, reason: reason);
          expect(restored!.dx, closeTo(source.dx, .001), reason: reason);
          expect(restored.dy, closeTo(source.dy, .001), reason: reason);
          expect(page.findAyahAt(restored)?.globalAyah, global, reason: reason);
          return local;
        }

        for (final ayah in page.ayahs) {
          if (ayah.numberCenter case final center?) {
            checkPoint(center, ayah.globalAyah);
            checkedMarkers++;
          }
          for (final segment in ayah.segments) {
            final local = checkPoint(segment.samplePoint, ayah.globalAyah);
            checkedSegments++;
            if (size != const Size(430, 932)) continue;
            final Path path;
            if (segment is AyahRectSegment) {
              path = mapper.viewBoxRectToLocalPath(
                viewBoxRect: segment.rect,
                contentSize: size,
                viewBox: page.viewBox,
              );
            } else {
              path = mapper.viewBoxPathToLocal(
                points: (segment as AyahPolygonSegment).points,
                contentSize: size,
                viewBox: page.viewBox,
              );
            }
            // A sample exactly on a seam can be on a path edge. A tiny inward
            // offset handles that boundary without accepting a displaced mask.
            expect(
              [
                Offset.zero,
                const Offset(0, .01),
                const Offset(0, -.01),
                const Offset(.01, 0),
                const Offset(-.01, 0),
              ].any((offset) => path.contains(local + offset)),
              isTrue,
              reason:
                  'Page ${page.page}, ayah ${ayah.globalAyah}: '
                  'the mask must follow its printed segment',
            );
          }
        }
      }
    }
    expect(checkedMarkers, 6236 * 3);
    expect(checkedSegments, 11386 * 3);
  });
}
