import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/mushaf_interaction_cubit.dart';
import '../cubit/quran_visual_recall_cubit.dart';
import '../services/mushaf_coordinate_mapper.dart';

/// Interactive touch layer placed over a Mushaf page.
///
/// Intercepts Tap and Long-Press gestures, converts touch positions to SVG viewBox
/// coordinates via [MushafCoordinateMapper], hit-tests against pre-extracted Q2 geometry,
/// and delegates selection/action-sheet requests to [MushafInteractionCubit].
class MushafInteractionLayer extends StatelessWidget {
  const MushafInteractionLayer({
    super.key,
    required this.page,
    required this.child,
    this.onDoubleTap,
    this.mapper = const MushafCoordinateMapper(),
  });

  final int page;
  final Widget child;
  final VoidCallback? onDoubleTap;
  final MushafCoordinateMapper mapper;

  QuranVisualRecallCubit? _tryGetVisualRecallCubit(BuildContext context) {
    try {
      return BlocProvider.of<QuranVisualRecallCubit>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  void _onTapUp(BuildContext context, TapUpDetails details, Size contentSize) {
    // If Visual Recall is actively running, yield entirely to Visual Recall interaction
    final recallCubit = _tryGetVisualRecallCubit(context);
    if (recallCubit != null &&
        (recallCubit.state.hasActiveSession ||
            recallCubit.state.isRangeSelecting)) {
      return;
    }

    final cubit = context.read<MushafInteractionCubit>();
    final pageGeom = cubit.layoutRepository.getPageGeometry(page);
    if (pageGeom == null) return;

    final viewBoxCoord = mapper.localToViewBox(
      localPosition: details.localPosition,
      contentSize: contentSize,
      viewBox: pageGeom.viewBox,
    );

    if (viewBoxCoord == null) {
      // Tap fell in letterbox/pillarbox empty margin
      cubit.clearSelection();
      return;
    }

    final hitAyah = pageGeom.findAyahAt(viewBoxCoord);
    if (hitAyah != null) {
      cubit.selectAyah(hitAyah);
    } else {
      cubit.clearSelection();
    }
  }

  void _onLongPressStart(
    BuildContext context,
    LongPressStartDetails details,
    Size contentSize,
  ) {
    final recallCubit = _tryGetVisualRecallCubit(context);
    if (recallCubit != null &&
        (recallCubit.state.hasActiveSession ||
            recallCubit.state.isRangeSelecting)) {
      return;
    }

    final cubit = context.read<MushafInteractionCubit>();
    final pageGeom = cubit.layoutRepository.getPageGeometry(page);
    if (pageGeom == null) return;

    final viewBoxCoord = mapper.localToViewBox(
      localPosition: details.localPosition,
      contentSize: contentSize,
      viewBox: pageGeom.viewBox,
    );

    // Empty margins or non-Ayah headers do NOT trigger the Action Sheet
    if (viewBoxCoord == null) return;

    final hitAyah = pageGeom.findAyahAt(viewBoxCoord);
    if (hitAyah != null) {
      cubit.selectAyah(hitAyah, openActionSheet: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentSize = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: onDoubleTap,
          onTapUp: (details) => _onTapUp(context, details, contentSize),
          onLongPressStart: (details) =>
              _onLongPressStart(context, details, contentSize),
          child: child,
        );
      },
    );
  }
}
