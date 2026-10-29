import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/mushaf_layout_repository.dart';
import '../cubit/quran_visual_recall_cubit.dart';
import '../cubit/quran_visual_recall_state.dart';
import '../services/mushaf_coordinate_mapper.dart';

/// Interactive touch layer for Q13 In-Mushaf Visual Recall.
///
/// Intercepts user taps on the Mushaf page, translates screen/widget coordinates into
/// native SVG viewBox units via [MushafCoordinateMapper], hit-tests against pre-computed
/// geometry via [MushafLayoutRepository.findAyahAt], verifies that the hit belongs
/// to the current queue item, and reveals that Ayah through [QuranVisualRecallCubit].
///
/// Seamlessly integrates with [InteractiveViewer] transformations (zoom and pan)
/// and safely ignores non-queued Ayahs, empty margins, and decorative elements.
class MushafVisualRecallInteractionLayer extends StatelessWidget {
  const MushafVisualRecallInteractionLayer({
    super.key,
    required this.page,
    required this.visualRecallCubit,
    this.effectiveLayoutRepo,
    required this.viewBox,
    this.onDoubleTap,
    this.mapper = const MushafCoordinateMapper(),
    required this.child,
  });

  /// The 1-based Mushaf page number currently rendered (1..604).
  final int page;

  /// The active Visual Recall Cubit orchestrator.
  final QuranVisualRecallCubit visualRecallCubit;

  /// Preloaded layout repository instance.
  final MushafLayoutRepository? effectiveLayoutRepo;

  /// Native SVG viewBox rect for the page.
  final Rect viewBox;

  /// Optional double-tap callback (typically zooms reset in InteractiveViewer).
  final VoidCallback? onDoubleTap;

  /// Coordinate mapper converting widget pixels to native viewBox units.
  final MushafCoordinateMapper mapper;

  /// Child widget (the Mushaf page Stack containing SVG and mask overlays).
  final Widget child;

  void _onTapUp(TapUpDetails details, Size contentSize) {
    final repo =
        effectiveLayoutRepo ??
        (MushafLayoutRepository.instance.isLoaded
            ? MushafLayoutRepository.instance
            : null);
    if (repo == null || !repo.isLoaded) return;

    final pageGeom = repo.getPageGeometry(page);
    if (pageGeom == null) return;

    // Convert local tap coordinate to SVG viewBox units with padding: EdgeInsets.zero
    // (exact 1:1 match with SvgPicture.asset and VisualMaskPainter inside the Stack).
    final viewBoxCoord = mapper.localToViewBox(
      localPosition: details.localPosition,
      contentSize: contentSize,
      viewBox: pageGeom.viewBox,
      padding: EdgeInsets.zero,
    );

    // If tap fell in letterbox/pillarbox margin or outside page bounds -> safe no-op
    if (viewBoxCoord == null) return;

    // Hit-test against pre-computed page Ayahs
    final hitAyah = repo.findAyahAt(page, viewBoxCoord);
    if (hitAyah == null) return;

    final state = visualRecallCubit.state;

    // 1. Handle interactive range selection
    if (state.isRangeSelecting) {
      visualRecallCubit.updateRangeEnd(hitAyah.globalAyah);
      return;
    }

    // 2. Reveal only the Ayah whose turn has actually arrived. Future Ayahs stay
    // masked even if they are tapped, so the learner cannot accidentally expose
    // the rest of the passage before assessing the current Ayah.
    if (state.hasActiveSession) {
      if (hitAyah.globalAyah != state.currentGlobalAyah ||
          state.isCurrentAyahRevealed) {
        return;
      }

      visualRecallCubit.revealCurrentAyah();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<QuranVisualRecallCubit, QuranVisualRecallState, bool>(
      bloc: visualRecallCubit,
      selector: (state) => state.hasActiveSession || state.isRangeSelecting,
      builder: (context, isActive) {
        if (!isActive) {
          return child;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final contentSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );

            return Semantics(
              label: visualRecallCubit.state.hasActiveSession
                  ? 'التسميع البصري. اضغط رقم الآية الحالية لإظهارها.'
                  : 'تحديد نطاق التسميع البصري',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: onDoubleTap,
                onTapUp: (details) => _onTapUp(details, contentSize),
                child: child,
              ),
            );
          },
        );
      },
    );
  }
}
