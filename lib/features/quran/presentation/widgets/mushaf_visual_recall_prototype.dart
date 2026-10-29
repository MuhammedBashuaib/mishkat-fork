import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/models/mushaf_layout_models.dart';
import '../../data/repositories/mushaf_layout_repository.dart';
import '../pages/quran_reader_page.dart';
import '../services/mushaf_coordinate_mapper.dart';

/// Geometry masking mode for Phase 0 prototype investigation.
enum MaskBoundaryMode {
  /// Raw axis-aligned bounding rectangles directly from metadata.
  raw,

  /// Micro-inset (0.5 SVG points contraction on shared line boundaries).
  microInset,

  /// Subtle rounded corners (R = 3.0 pt) for calligraphic visual softening.
  rounded,
}

/// Visual masking painter that renders solid opaque overlays over target Ayah geometry.
class VisualMaskPainter extends CustomPainter {
  const VisualMaskPainter({
    required this.maskedAyah,
    this.neighborAyah,
    required this.viewBox,
    this.mapper = const MushafCoordinateMapper(),
    required this.maskColor,
    this.neighborHighlightColor,
    this.boundaryMode = MaskBoundaryMode.raw,
  });

  final AyahBounds? maskedAyah;
  final AyahBounds? neighborAyah;
  final Rect viewBox;
  final MushafCoordinateMapper mapper;
  final Color maskColor;
  final Color? neighborHighlightColor;
  final MaskBoundaryMode boundaryMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || viewBox.isEmpty) return;

    // 1. Paint optional neighbor highlight (for boundary safety inspection)
    if (neighborAyah != null && neighborHighlightColor != null) {
      final neighborPaint = Paint()
        ..color = neighborHighlightColor!
        ..style = PaintingStyle.fill;
      _paintAyahGeometry(
        canvas,
        size,
        neighborAyah!,
        neighborPaint,
        isMask: false,
      );
    }

    // 2. Paint opaque visual mask over target Ayah
    if (maskedAyah != null) {
      final maskPaint = Paint()
        ..color = maskColor
        ..style = PaintingStyle.fill;
      _paintAyahGeometry(canvas, size, maskedAyah!, maskPaint, isMask: true);
    }
  }

  void _paintAyahGeometry(
    Canvas canvas,
    Size size,
    AyahBounds ayah,
    Paint paint, {
    required bool isMask,
  }) {
    for (final segment in ayah.segments) {
      if (segment is AyahRectSegment) {
        Rect effectiveRect = segment.rect;

        if (isMask && boundaryMode == MaskBoundaryMode.microInset) {
          // Contract horizontal edges by 0.5 SVG points if not full-width
          final isLeftEdge = effectiveRect.left <= 2.0;
          final isRightEdge = effectiveRect.right >= (viewBox.width - 2.0);
          final insetLeft = isLeftEdge ? 0.0 : 0.5;
          final insetRight = isRightEdge ? 0.0 : 0.5;
          effectiveRect = Rect.fromLTRB(
            effectiveRect.left + insetLeft,
            effectiveRect.top,
            effectiveRect.right - insetRight,
            effectiveRect.bottom,
          );
        }

        final localRect = mapper.viewBoxRectToLocal(
          viewBoxRect: effectiveRect,
          contentSize: size,
          viewBox: viewBox,
          padding: EdgeInsets.zero, // Exact 1:1 match with SvgPicture.asset
        );

        if (isMask && boundaryMode == MaskBoundaryMode.rounded) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(localRect, const Radius.circular(3.0)),
            paint,
          );
        } else {
          canvas.drawRect(localRect, paint);
        }
      } else if (segment is AyahPolygonSegment) {
        final localPath = mapper.viewBoxPathToLocal(
          points: segment.points,
          contentSize: size,
          viewBox: viewBox,
          padding: EdgeInsets.zero, // Exact 1:1 match with SvgPicture.asset
        );
        canvas.drawPath(localPath, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant VisualMaskPainter oldDelegate) {
    return oldDelegate.maskedAyah != maskedAyah ||
        oldDelegate.neighborAyah != neighborAyah ||
        oldDelegate.viewBox != viewBox ||
        oldDelegate.maskColor != maskColor ||
        oldDelegate.neighborHighlightColor != neighborHighlightColor ||
        oldDelegate.boundaryMode != boundaryMode;
  }
}

/// Isolated Phase 0 Prototype Widget for Visual Recall Validation.
///
/// Features:
/// - Independent page navigation (never calls `QuranCubit.openPage`).
/// - Single Ayah masking & revealing.
/// - Adjacent neighbor highlighting for edge-bleed verification.
/// - Interactive zoom & pan via [TransformationController].
/// - Light / Dark Mushaf theme switcher.
/// - Raw vs Micro-inset vs Rounded mask modes.
class MushafVisualRecallPrototype extends StatefulWidget {
  const MushafVisualRecallPrototype({
    super.key,
    required this.layoutRepository,
    this.initialPage = 1,
    this.initialTargetGlobalAyah,
    this.initialNeighborGlobalAyah,
    this.initialMasked = true,
    this.initialThemeMode = ThemeMode.light,
    this.initialBoundaryMode = MaskBoundaryMode.raw,
    this.initialZoom = 1.0,
  });

  final MushafLayoutRepository layoutRepository;
  final int initialPage;
  final int? initialTargetGlobalAyah;
  final int? initialNeighborGlobalAyah;
  final bool initialMasked;
  final ThemeMode initialThemeMode;
  final MaskBoundaryMode initialBoundaryMode;
  final double initialZoom;

  @override
  State<MushafVisualRecallPrototype> createState() =>
      MushafVisualRecallPrototypeState();
}

class MushafVisualRecallPrototypeState
    extends State<MushafVisualRecallPrototype> {
  late int _currentPage;
  late int? _targetGlobalAyah;
  late int? _neighborGlobalAyah;
  late bool _isMasked;
  late ThemeMode _themeMode;
  late MaskBoundaryMode _boundaryMode;

  final TransformationController _transformationController =
      TransformationController();
  late double _zoomScale;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _targetGlobalAyah = widget.initialTargetGlobalAyah;
    _neighborGlobalAyah = widget.initialNeighborGlobalAyah;
    _isMasked = widget.initialMasked;
    _themeMode = widget.initialThemeMode;
    _boundaryMode = widget.initialBoundaryMode;
    _zoomScale = widget.initialZoom;

    if (_zoomScale != 1.0) {
      _transformationController.value = Matrix4.diagonal3Values(
        _zoomScale,
        _zoomScale,
        1.0,
      );
    }

    if (_targetGlobalAyah == null) {
      _selectDefaultAyahsForPage(_currentPage);
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _selectDefaultAyahsForPage(int page) {
    final pageGeom = widget.layoutRepository.getPageGeometry(page);
    if (pageGeom != null && pageGeom.ayahs.isNotEmpty) {
      _targetGlobalAyah = pageGeom.ayahs.first.globalAyah;
      if (pageGeom.ayahs.length > 1) {
        _neighborGlobalAyah = pageGeom.ayahs[1].globalAyah;
      } else {
        _neighborGlobalAyah = null;
      }
    } else {
      _targetGlobalAyah = null;
      _neighborGlobalAyah = null;
    }
  }

  void setPage(int page) {
    if (page < 1 || page > 604) return;
    setState(() {
      _currentPage = page;
      _selectDefaultAyahsForPage(page);
    });
  }

  void setTargetAyah(int? globalAyah) {
    setState(() => _targetGlobalAyah = globalAyah);
  }

  void setNeighborAyah(int? globalAyah) {
    setState(() => _neighborGlobalAyah = globalAyah);
  }

  void toggleMask() {
    setState(() => _isMasked = !_isMasked);
  }

  void setZoom(double scale) {
    setState(() {
      _zoomScale = scale;
      _transformationController.value = Matrix4.diagonal3Values(
        scale,
        scale,
        1.0,
      );
    });
  }

  void setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  void setBoundaryMode(MaskBoundaryMode mode) {
    setState(() => _boundaryMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _themeMode == ThemeMode.dark;
    final backgroundColor = isDark
        ? MushafThemeColors.darkBackground
        : MushafThemeColors.lightBackground;
    final inkColor = isDark
        ? MushafThemeColors.darkInk
        : MushafThemeColors.lightInk;
    final maskColor = backgroundColor;
    final neighborColor = isDark
        ? const Color(0x403B82F6) // translucent soft blue in dark
        : const Color(0x352563EB); // translucent blue in light

    final pageGeom = widget.layoutRepository.getPageGeometry(_currentPage);
    final viewBox =
        pageGeom?.viewBox ??
        (_currentPage <= 2
            ? const Rect.fromLTWH(-53.3109, -198.4777, 345, 550)
            : const Rect.fromLTWH(0, 0, 345, 550));

    final AyahBounds? targetBounds = _targetGlobalAyah != null
        ? widget.layoutRepository.getAyah(_targetGlobalAyah!)
        : null;
    final AyahBounds? neighborBounds = _neighborGlobalAyah != null
        ? widget.layoutRepository.getAyah(_neighborGlobalAyah!)
        : null;

    final svgColorFilter = isDark
        ? ColorFilter.mode(inkColor, BlendMode.srcIn)
        : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              // 1. Mushaf Page Canvas Area
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return InteractiveViewer(
                      transformationController: _transformationController,
                      constrained: true,
                      minScale: 1.0,
                      maxScale: 3.0,
                      child: Center(
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Layer 1: Native unchanged Mushaf SVG
                              SvgPicture.asset(
                                'assets/mushaf/pages/${_currentPage.toString().padLeft(3, '0')}.svg',
                                fit: BoxFit.contain,
                                colorFilter: svgColorFilter,
                                placeholderBuilder: (_) => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),

                              // Layer 2: Prototype Visual Mask & Neighbor Highlight
                              CustomPaint(
                                size: Size.infinite,
                                painter: VisualMaskPainter(
                                  maskedAyah: _isMasked ? targetBounds : null,
                                  neighborAyah: neighborBounds,
                                  viewBox: viewBox,
                                  maskColor: maskColor,
                                  neighborHighlightColor: neighborColor,
                                  boundaryMode: _boundaryMode,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 2. Prototype Control Strip
              Container(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: Page Navigation & Target Status
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, size: 16),
                            tooltip: 'الصفحة السابقة',
                            onPressed: _currentPage > 1
                                ? () => setPage(_currentPage - 1)
                                : null,
                          ),
                          Text(
                            'صفحة $_currentPage',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios, size: 16),
                            tooltip: 'الصفحة التالية',
                            onPressed: _currentPage < 604
                                ? () => setPage(_currentPage + 1)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: toggleMask,
                            icon: Icon(
                              _isMasked
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 16,
                            ),
                            label: Text(
                              _isMasked ? 'كشف الآية' : 'إخفاء الآية',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isMasked
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Row 2: Zoom, Theme, and Boundary Mode Selectors
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('تكبير: ', style: TextStyle(fontSize: 11)),
                          ChoiceChip(
                            label: const Text(
                              '1.0×',
                              style: TextStyle(fontSize: 11),
                            ),
                            selected: _zoomScale == 1.0,
                            onSelected: (_) => setZoom(1.0),
                          ),
                          const SizedBox(width: 4),
                          ChoiceChip(
                            label: const Text(
                              '1.5×',
                              style: TextStyle(fontSize: 11),
                            ),
                            selected: _zoomScale == 1.5,
                            onSelected: (_) => setZoom(1.5),
                          ),
                          const SizedBox(width: 4),
                          ChoiceChip(
                            label: const Text(
                              '2.0×',
                              style: TextStyle(fontSize: 11),
                            ),
                            selected: _zoomScale == 2.0,
                            onSelected: (_) => setZoom(2.0),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              isDark ? Icons.light_mode : Icons.dark_mode,
                              size: 20,
                            ),
                            tooltip: 'تغيير المظهر',
                            onPressed: () => setThemeMode(
                              isDark ? ThemeMode.light : ThemeMode.dark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
