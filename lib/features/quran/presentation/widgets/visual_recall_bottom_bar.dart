import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../data/models/visual_recall_models.dart';
import '../cubit/quran_visual_recall_cubit.dart';
import '../cubit/quran_visual_recall_state.dart';

/// Assessment and session control bar for Q13 In-Mushaf Visual Recall.
///
/// Renders at the bottom of the Quran reader during active recall drills, presenting:
/// - Drill progress indicator and Ayah index
/// - Explicit reveal button in [VisualRecallPhase.activeRecall]
/// - Self-assessment choices ("أعرفها ومتقنة", "تحتاج مراجعة") in [VisualRecallPhase.evaluating]
/// - Transient submission / spinner state disabling duplicate taps
/// - Actionable error banner with retry on persistence failure
/// - Completion summary in [VisualRecallPhase.completed]
class VisualRecallBottomBar extends StatelessWidget {
  const VisualRecallBottomBar({super.key, required this.cubit});

  final QuranVisualRecallCubit cubit;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuranVisualRecallCubit, QuranVisualRecallState>(
      bloc: cubit,
      builder: (context, state) {
        if (state.isIdle) {
          return const SizedBox.shrink();
        }

        final colors = context.mishkat;
        final theme = Theme.of(context);

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            color: theme.colorScheme.surface,
            elevation: 12,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(MishkatRadius.lg),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Error banner with retry if an uncommitted failure occurred
                    if (state.error != null) ...[
                      _buildErrorBanner(context, state, colors),
                      const SizedBox(height: 8),
                    ],

                    if (state.isRangeSelecting)
                      _buildRangeSelectionView(context, state, colors)
                    else if (state.isCompleted)
                      _buildCompletedView(context, state, colors, theme)
                    else if (state.hasActiveSession)
                      _buildActiveSessionView(context, state, colors, theme),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorBanner(
    BuildContext context,
    QuranVisualRecallState state,
    MishkatColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MishkatRadius.md),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.error ?? 'تعذر حفظ نتيجة التسميع على القرص',
              style: TextStyle(
                color: colors.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: state.isLoading
                ? null
                : () => cubit.retryLastOutcome().ignore(),
            style: TextButton.styleFrom(
              foregroundColor: colors.error,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'إعادة المحاولة',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSessionView(
    BuildContext context,
    QuranVisualRecallState state,
    MishkatColors colors,
    ThemeData theme,
  ) {
    final currentIndex1Based = state.currentIndex + 1;
    final total = state.totalCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Header: Progress & Close Button
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'التسميع البصري: آية $currentIndex1Based من $total',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(state.progress * 100).toInt()}%',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total > 0
                          ? (state.currentIndex / total).clamp(0.0, 1.0)
                          : 0.0,
                      minHeight: 5,
                      backgroundColor: colors.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: state.isAudioSyncEnabled
                  ? 'تعطيل التزامن الصوتي'
                  : 'تفعيل التزامن الصوتي',
              icon: Icon(
                state.isAudioSyncEnabled
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                color: state.isAudioSyncEnabled
                    ? colors.primary
                    : colors.textSecondary,
                size: 20,
              ),
              onPressed: state.isLoading ? null : () => cubit.toggleAudioSync(),
            ),
            IconButton(
              tooltip: 'إنهاء الجلسة',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: state.isLoading ? null : () => cubit.endSession(),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Action Section: Either Active Recall prompt or Assessment choices
        if (state.isActiveRecall)
          _buildRecallControls(context, state, colors)
        else if (state.isEvaluating)
          _buildEvaluationControls(context, state, colors),
      ],
    );
  }

  Widget _buildRecallControls(
    BuildContext context,
    QuranVisualRecallState state,
    MishkatColors colors,
  ) {
    if (state.isTimedMaskActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(MishkatRadius.md),
          border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: (state.remainingMaskDuration / 3).clamp(0.0, 1.0),
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                state.isAudioPaused
                    ? 'الترديد متوقف مؤقتاً (${state.remainingMaskDuration}ث)'
                    : 'ردّد الآية غيباً (${state.remainingMaskDuration}ث)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: colors.primary,
                ),
              ),
            ),
            IconButton(
              tooltip: state.isAudioPaused ? 'استئناف' : 'إيقاف مؤقت',
              icon: Icon(
                state.isAudioPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                size: 20,
                color: colors.primary,
              ),
              onPressed: () => cubit.toggleAudioPlayback(),
            ),
            TextButton(
              onPressed: () => cubit.skipTimedMaskDelay(),
              child: const Text('تخطي المهلة'),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        if (state.isAudioSyncEnabled) ...[
          IconButton.filledTonal(
            tooltip: state.isAudioPlaying
                ? 'إيقاف التلاوة'
                : (state.isAudioPaused ? 'استئناف التلاوة' : 'استماع للآية'),
            icon: Icon(
              state.isAudioPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 20,
            ),
            onPressed: () => cubit.toggleAudioPlayback(),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            state.isAudioPlaying
                ? 'تلاوة الآية جارية...'
                : 'ردّد من حفظك، ثم اضغط رقم الآية الحالية لإظهارها',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => cubit.revealCurrentAyah(),
          icon: const Icon(Icons.visibility_rounded, size: 18),
          label: const Text('إظهار الآية'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MishkatRadius.md),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEvaluationControls(
    BuildContext context,
    QuranVisualRecallState state,
    MishkatColors colors,
  ) {
    final isLoading = state.isLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'جارٍ حفظ النتيجة...',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            // 1. Known / Confirmed (Green)
            Expanded(
              flex: 5,
              child: ElevatedButton.icon(
                onPressed: isLoading
                    ? null
                    : () => cubit.recordKnown().ignore(),
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text(
                  'أعرفها ومتقنة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: colors.primary.withValues(
                    alpha: 0.5,
                  ),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(MishkatRadius.md),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 2. Needs Revision (Amber)
            Expanded(
              flex: 4,
              child: OutlinedButton.icon(
                onPressed: isLoading
                    ? null
                    : () => cubit.recordNeedsRevision().ignore(),
                icon: Icon(
                  Icons.replay_rounded,
                  size: 18,
                  color: colors.warning,
                ),
                label: Text(
                  'تحتاج مراجعة',
                  style: TextStyle(
                    color: colors.warning,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: colors.warning.withValues(alpha: 0.6),
                  ),
                  backgroundColor: colors.warning.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(MishkatRadius.md),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRangeSelectionView(
    BuildContext context,
    QuranVisualRecallState state,
    MishkatColors colors,
  ) {
    final start = state.rangeSelectionStart ?? 1;
    final end = state.rangeSelectionEnd ?? 1;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تحديد نطاق التسميع البصري',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                'الآيات المحددة: من $start إلى $end',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => cubit.cancelRangeSelection(),
          child: const Text('إلغاء'),
        ),
        const SizedBox(width: 6),
        FilledButton(
          onPressed: () => cubit.confirmRangeSelection(),
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MishkatRadius.md),
            ),
          ),
          child: const Text('بدء التسميع'),
        ),
      ],
    );
  }

  Widget _buildCompletedView(
    BuildContext context,
    QuranVisualRecallState state,
    MishkatColors colors,
    ThemeData theme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.stars_rounded, color: colors.gold, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'اكتملت الجلسة بنجاح! 🎉',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    'تم تقييم ${state.completedCount} آية وحفظها في سجلك.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => cubit.dismissSummary(),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(MishkatRadius.md),
                ),
              ),
              child: const Text('إنهاء'),
            ),
          ],
        ),
      ],
    );
  }
}
