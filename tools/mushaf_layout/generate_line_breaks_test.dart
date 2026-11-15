// Run from mishkat_app:
// flutter test tools/mushaf_layout/generate_line_breaks_test.dart
// Optional: --dart-define=MUSHAF_SEAM_PREVIEW=true generates samples in /tmp.
// Transparent paths protect visible ink with a one-pixel safety margin.
// The original SVG assets are never rewritten.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const _width = 690;
const _height = 1100;
const _scale = 2.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('extract transparent paths between Mushaf lines', () async {
    const preview = bool.fromEnvironment('MUSHAF_SEAM_PREVIEW');
    final pages = <Map<String, Object>>[];
    final histogram = <int, int>{};
    final omitted = <int, List<int>>{};
    for (var page = 1; page <= 604; page++) {
      if (preview && ![175, 176, 562].contains(page)) continue;
      final seams = <List<ui.Offset>>[];
      // Preserve the continuous decorative frames on the opening spread.
      if (page > 2) {
        final info = await vg.loadPicture(
          SvgAssetLoader(
            'assets/mushaf/pages/${page.toString().padLeft(3, '0')}.svg',
          ),
          null,
        );
        expect(info.size, const ui.Size(345, 550));
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
          ..scale(_scale)
          ..drawPicture(info.picture);
        final rasterPicture = recorder.endRecording();
        final image = await rasterPicture.toImage(_width, _height);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final ink = List<bool>.filled(_width * _height, false);
        final protectedInk = List<bool>.filled(_width * _height, false);
        for (var y = 0; y < _height; y++) {
          for (var x = 0; x < _width; x++) {
            if (bytes[(y * _width + x) * 4 + 3] == 0) continue;
            ink[y * _width + x] = true;
            for (var dy = -1; dy <= 1; dy++) {
              for (var dx = -1; dx <= 1; dx++) {
                final px = x + dx, py = y + dy;
                if (px >= 0 && px < _width && py >= 0 && py < _height) {
                  protectedInk[py * _width + px] = true;
                }
              }
            }
          }
        }
        for (var boundary = 0; boundary < 14; boundary++) {
          // Source baseline spacing is ~35.94 units; its first interline
          // whitespace is near y=42, including surah-title/basmala pages.
          final center = ((42 + boundary * 35.94) * _scale).round();
          List<ui.Offset>? seam;
          for (final radius in [20, 28]) {
            seam = _findSeam(protectedInk, center, radius);
            if (seam != null) break;
          }
          seam ??= _straightFallback(ink, center);
          if (seam == null) {
            omitted.putIfAbsent(page, () => []).add(boundary + 1);
          } else {
            if (seams.isNotEmpty) {
              expect(
                seam.map((p) => p.dy).reduce(math.min),
                greaterThan(seams.last.map((p) => p.dy).reduce(math.max)),
                reason: 'Page $page, seam ${boundary + 1}',
              );
            }
            seams.add(_simplify(seam));
          }
        }
        if (preview) await _preview(info.picture, seams, page);
        image.dispose();
        rasterPicture.dispose();
        info.picture.dispose();
      }
      pages.add({
        'p': page,
        'seams': [
          for (final seam in seams)
            [
              for (final p in seam) [p.dx, p.dy],
            ],
        ],
      });
      histogram.update(seams.length, (n) => n + 1, ifAbsent: () => 1);
      if (page % 50 == 0) {
        // ignore: avoid_print
        print('Scanned $page / 604 pages');
      }
    }
    if (!preview) expect(pages, hasLength(604));
    final target = preview
        ? '/tmp/mushaf-seams-preview.json'
        : 'assets/data/mushaf-line-breaks.json';
    await File(target)
        .writeAsString('${jsonEncode({'version': 2, 'pages': pages})}\n');
    // ignore: avoid_print
    print('Seams per page: $histogram; omitted boundaries: $omitted');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

List<ui.Offset>? _findSeam(List<bool> blocked, int center, int radius) {
  final top = center - radius, rows = radius * 2 + 1;
  final back = List.generate(_width, (_) => List<int>.filled(rows, -1));
  var previous = List<double>.generate(
    rows,
    (r) => blocked[(top + r) * _width]
        ? double.infinity
        : .01 * (top + r - center).abs(),
  );
  for (var x = 1; x < _width; x++) {
    final next = List<double>.filled(rows, double.infinity);
    for (var r = 0; r < rows; r++) {
      if (blocked[(top + r) * _width + x]) continue;
      for (var dr = -1; dr <= 1; dr++) {
        final last = r + dr;
        if (last < 0 || last >= rows) continue;
        final cost =
            previous[last] + .2 * dr.abs() + .01 * (top + r - center).abs();
        if (cost < next[r]) {
          next[r] = cost;
          back[x][r] = last;
        }
      }
    }
    previous = next;
  }
  var last = 0;
  for (var r = 1; r < rows; r++) {
    if (previous[r] < previous[last]) last = r;
  }
  if (!previous[last].isFinite) return null;
  final seam = List<ui.Offset>.filled(_width, ui.Offset.zero);
  for (var x = _width - 1; x >= 0; x--) {
    final y = top + last;
    expect(blocked[y * _width + x], isFalse);
    seam[x] = ui.Offset((x + .5) / _scale, (y + .5) / _scale);
    if (x > 0) last = back[x][last];
  }
  return [ui.Offset(0, seam.first.dy), ...seam, ui.Offset(345, seam.last.dy)];
}

List<ui.Offset>? _straightFallback(List<bool> ink, int center) {
  double? nearest;
  var bestDistance = double.infinity;
  bool clear(int row) {
    for (var x = 0; x < _width; x++) {
      if (ink[row * _width + x]) return false;
    }
    return true;
  }

  for (var y = center - 20; y < center + 20; y++) {
    if (!clear(y) || !clear(y + 1)) continue;
    final candidate = (y + 1) / _scale;
    final distance = (candidate - center / _scale).abs();
    if (distance < bestDistance) {
      nearest = candidate;
      bestDistance = distance;
    }
  }
  if (nearest == null) return null;
  return [ui.Offset(0, nearest), ui.Offset(345, nearest)];
}

List<ui.Offset> _simplify(List<ui.Offset> points) {
  if (points.length <= 2) return points;
  final result = <ui.Offset>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final a = points[i] - result.last, b = points[i + 1] - points[i];
    if (a.dx * b.dy != a.dy * b.dx) result.add(points[i]);
  }
  result.add(points.last);
  return result;
}

Future<void> _preview(
  ui.Picture picture,
  List<List<ui.Offset>> seams,
  int page,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(const ui.Color(0xFFF6F1E8), ui.BlendMode.src)
    ..scale(2);
  final boundaries = [
    const [ui.Offset(0, 0), ui.Offset(345, 0)],
    ...seams,
    const [ui.Offset(0, 550), ui.Offset(345, 550)],
  ];
  final gap = 200 / seams.length;
  for (var i = 0; i < boundaries.length - 1; i++) {
    final upper = boundaries[i], lower = boundaries[i + 1];
    final path = ui.Path()..moveTo(upper.first.dx, upper.first.dy);
    for (final p in upper.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in lower.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.save();
    canvas.translate(0, gap * i);
    canvas.clipPath(path, doAntiAlias: false);
    canvas.drawPicture(picture);
    canvas.restore();
  }
  final result = recorder.endRecording();
  final image = await result.toImage(690, 1500);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('/tmp/mushaf-seams-$page.png')
      .writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  result.dispose();
}
