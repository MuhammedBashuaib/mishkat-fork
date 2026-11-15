import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/mushaf_coordinate_mapper.dart';

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
  PictureInfo? _picture;
  bool _failed = false;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (!identical(_bundle, bundle)) {
      _bundle = bundle;
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
    _picture?.picture.dispose();
    _picture = null;
    _failed = false;
    final loader = SvgAssetLoader(
      'assets/mushaf/pages/${widget.page.toString().padLeft(3, '0')}.svg',
      assetBundle: _bundle,
    );
    unawaited(_decode(loader, generation));
  }

  Future<void> _decode(SvgAssetLoader loader, int generation) async {
    try {
      final picture = await vg.loadPicture(loader, context);
      if (!mounted || generation != _loadGeneration) {
        picture.picture.dispose();
        return;
      }
      setState(() => _picture = picture);
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _picture?.picture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picture = _picture;
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
