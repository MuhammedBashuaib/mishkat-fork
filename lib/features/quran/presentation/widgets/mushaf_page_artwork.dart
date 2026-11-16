import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/mushaf_coordinate_mapper.dart';
import '../services/mushaf_artwork_cache.dart';

/// Draws the original page with extra space only between verified ink-free cuts.
///
/// One decoded vector picture serves every band, size and paper appearance.
/// The mapper is shared with selection and recitation overlays so their geometry
/// follows the same placement as the calligraphy.
class MushafPageArtwork extends StatefulWidget {
  const MushafPageArtwork({
    super.key,
    required this.page,
    required this.viewBox,
    required this.mapper,
    this.colorFilter,
  });

  final int page;
  final Rect viewBox;
  final MushafCoordinateMapper mapper;
  final ColorFilter? colorFilter;

  @override
  State<MushafPageArtwork> createState() => _MushafPageArtworkState();
}

class _MushafPageArtworkState extends State<MushafPageArtwork> {
  AssetBundle? _bundle;
  MushafArtworkCache? _cache;
  MushafArtworkLease? _lease;
  bool _failed = false;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (!identical(_bundle, bundle)) {
      _bundle = bundle;
      _cache = MushafArtworkCache.forBundle(bundle);
      _loadPicture();
    }
  }

  @override
  void didUpdateWidget(covariant MushafPageArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) _loadPicture();
  }

  void _loadPicture() {
    final generation = ++_loadGeneration;
    _lease?.release();
    _lease = null;
    _failed = false;
    unawaited(_decode(_cache!, widget.page, generation));
  }

  Future<void> _decode(
    MushafArtworkCache cache,
    int page,
    int generation,
  ) async {
    // Recover a transient local read failure once before offering manual retry.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final lease = await cache.acquire(page);
        if (!mounted || generation != _loadGeneration) {
          lease.release();
          return;
        }
        setState(() => _lease = lease);
        // Only nearby pages are warmed; never retain the entire Mushaf.
        for (final neighbor in [page - 1, page + 1]) {
          if (neighbor >= 1 && neighbor <= 604) {
            unawaited(
              cache.prefetch(neighbor).catchError((Object error) {
                // A speculative read must not fail the page currently on screen.
                debugPrint('Mushaf prefetch $neighbor failed: $error');
              }),
            );
          }
        }
        return;
      } catch (error, stackTrace) {
        if (!mounted || generation != _loadGeneration) return;
        if (attempt == 1) {
          debugPrint('Mushaf page $page failed to load: $error');
          debugPrintStack(stackTrace: stackTrace);
          setState(() => _failed = true);
        }
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _lease?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picture = _lease?.picture;
    return RepaintBoundary(
      child: picture != null
          ? CustomPaint(
              painter: MushafPageArtworkPainter(
                picture: picture,
                viewBox: widget.viewBox,
                mapper: widget.mapper,
                colorFilter: widget.colorFilter,
              ),
              size: Size.infinite,
              isComplex: true,
            )
          : Center(
              child: _failed
                  ? TextButton.icon(
                      onPressed: () => setState(_loadPicture),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text(
                        'تعذر تحميل صفحة المصحف. إعادة المحاولة',
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
    );
  }
}

class MushafPageArtworkPainter extends CustomPainter {
  const MushafPageArtworkPainter({
    required this.picture,
    required this.viewBox,
    required this.mapper,
    this.colorFilter,
  });

  final PictureInfo picture;
  final Rect viewBox;
  final MushafCoordinateMapper mapper;
  final ColorFilter? colorFilter;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || picture.size.isEmpty) return;
    if (colorFilter != null) {
      canvas.saveLayer(Offset.zero & size, Paint()..colorFilter = colorFilter);
    }
    for (final band in mapper.getBands(contentSize: size, viewBox: viewBox)) {
      canvas.save();
      canvas.translate(band.destination.left, band.destination.top);
      canvas.scale(band.scale);
      canvas.translate(-band.source.left, -band.source.top);
      // The cut follows the whitespace around diacritics. Its bounds can
      // overlap a neighboring line, so a rectangular destination clip would
      // incorrectly remove ink extending past the nominal line boundary.
      canvas.clipPath(band.sourceClip, doAntiAlias: false);
      // Decoded SVG pictures start at (0, 0), even when the source viewBox
      // has a non-zero origin, as on the two ornamented opening pages.
      canvas.translate(viewBox.left, viewBox.top);
      canvas.scale(
        viewBox.width / picture.size.width,
        viewBox.height / picture.size.height,
      );
      canvas.drawPicture(picture.picture);
      canvas.restore();
    }
    if (colorFilter != null) canvas.restore();
  }

  @override
  bool shouldRepaint(MushafPageArtworkPainter oldDelegate) =>
      oldDelegate.picture != picture ||
      oldDelegate.viewBox != viewBox ||
      oldDelegate.colorFilter != colorFilter ||
      oldDelegate.mapper.contentPadding != mapper.contentPadding ||
      !listEquals(oldDelegate.mapper.lineBreaks, mapper.lineBreaks) ||
      !listEquals(oldDelegate.mapper.lineSeams, mapper.lineSeams);
}
