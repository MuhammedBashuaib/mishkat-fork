import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/offline_audio_download_controller.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../data/models/memorization_status.dart';
import '../../data/models/mushaf_layout_models.dart';
import '../../data/models/quran_models.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_memorization_cubit.dart';
import '../cubit/quran_state.dart';
import '../cubit/quran_visual_recall_cubit.dart';
import '../../../../core/theme/navigation_icons.dart';

/// Modal bottom sheet presented upon long-pressing an Ayah.
///
/// Displays the Ayah context, Arabic text from local Quran data, primary audio playback action,
/// text copy utility, and future integration placeholders for Tafsir and Ayah-level bookmarks.
class AyahActionSheet extends StatelessWidget {
  const AyahActionSheet({
    super.key,
    required this.ayah,
    required this.quranData,
    this.playbackOrigin = QuranPlaybackOrigin.general,
  });

  final AyahBounds ayah;
  final QuranData quranData;
  final QuranPlaybackOrigin playbackOrigin;

  /// Shows the [AyahActionSheet] as a modal bottom sheet.
  static Future<String?> show({
    required BuildContext context,
    required AyahBounds ayah,
    required QuranData quranData,
    QuranPlaybackOrigin playbackOrigin = QuranPlaybackOrigin.general,
  }) {
    SettingsCubit? settingsCubit;
    try {
      settingsCubit = context.read<SettingsCubit>();
    } catch (_) {}
    QuranMemorizationCubit? memCubit;
    try {
      memCubit = context.read<QuranMemorizationCubit>();
    } catch (_) {}
    QuranVisualRecallCubit? recallCubit;
    try {
      recallCubit = context.read<QuranVisualRecallCubit>();
    } catch (_) {}
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<QuranCubit>()),
          if (settingsCubit != null) BlocProvider.value(value: settingsCubit),
          if (memCubit != null) BlocProvider.value(value: memCubit),
          if (recallCubit != null) BlocProvider.value(value: recallCubit),
        ],
        child: AyahActionSheet(
          ayah: ayah,
          quranData: quranData,
          playbackOrigin: playbackOrigin,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chapter = quranData.chapter(ayah.surah);
    final ayahIndex = (ayah.ayah - 1).clamp(0, chapter.ayahs.length - 1);
    final ayahText = chapter.ayahs.isNotEmpty ? chapter.ayahs[ayahIndex] : '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16241D) : const Color(0xFFFAF7F2),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFDED8CD),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Drag handle pill
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.2,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Header with Surah name and close button
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'سورة ${chapter.name}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'الآية ${ayah.ayah} · صفحة ${ayah.page} · الجزء ${_juzFor(quranData, ayah.globalAyah)}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'إغلاق',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 16),

                      // Arabic Ayah text display
                      if (ayahText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : const Color(0xFFE8E2D5),
                            ),
                          ),
                          child: Text(
                            ayahText,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontFamily: 'Amiri',
                              fontSize: 20,
                              height: 1.85,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Primary Action: Audio Playback
                      BlocBuilder<QuranCubit, QuranState>(
                        builder: (context, state) {
                          final isThisAyahPlaying =
                              state.audioStatus == QuranAudioStatus.playing &&
                              state.audioGlobalAyah == ayah.globalAyah;
                          final isThisAyahLoading =
                              state.audioStatus == QuranAudioStatus.loading &&
                              state.audioGlobalAyah == ayah.globalAyah;

                          return FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              backgroundColor: const Color(0xFF107C41),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: isThisAyahLoading
                                ? null
                                : () {
                                    final cubit = context.read<QuranCubit>();
                                    final settingsCubit = context
                                        .read<SettingsCubit?>();
                                    final continuous =
                                        settingsCubit
                                            ?.state
                                            .settings
                                            .quranContinuous ??
                                        true;
                                    final autoScroll =
                                        settingsCubit
                                            ?.state
                                            .settings
                                            .quranAutoScroll ??
                                        true;
                                    if (isThisAyahPlaying) {
                                      cubit.toggleAudio(
                                        continuous: continuous,
                                        autoScroll: autoScroll,
                                        origin: playbackOrigin,
                                      );
                                    } else {
                                      cubit.playAyah(
                                        ayah.globalAyah,
                                        continuous: continuous,
                                        autoScroll: autoScroll,
                                        origin: playbackOrigin,
                                      );
                                    }
                                  },
                            icon: isThisAyahLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    isThisAyahPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                  ),
                            label: Text(
                              isThisAyahPlaying
                                  ? 'إيقاف مؤقت للتلاوة'
                                  : 'تشغيل التلاوة',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      Builder(
                        builder: (context) {
                          OfflineAudioDownloadController? downloads;
                          try {
                            downloads = context
                                .read<OfflineAudioDownloadController>();
                          } catch (_) {}
                          if (downloads == null) return const SizedBox.shrink();
                          final controller = downloads;
                          return AnimatedBuilder(
                            animation: controller,
                            builder: (context, _) {
                              final task = controller.state;
                              final isThisAyah =
                                  task.startAyah == ayah.globalAyah &&
                                  task.endAyah == ayah.globalAyah;
                              return OutlinedButton.icon(
                                onPressed: task.isRunning
                                    ? (isThisAyah ? controller.cancel : null)
                                    : () async {
                                        final quran = context
                                            .read<QuranCubit>();
                                        final reciter =
                                            AppConstants.findReciter(
                                              quran.reciter,
                                            );
                                        await controller.downloadRange(
                                          reciter: reciter,
                                          startAyah: ayah.globalAyah,
                                          endAyah: ayah.globalAyah,
                                          label:
                                              'الآية ${ayah.ayah} من سورة ${chapter.name}',
                                        );
                                        if (context.mounted) {
                                          final result = controller.state;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                result.status ==
                                                        OfflineDownloadStatus
                                                            .completed
                                                    ? 'تم حفظ صوت الآية دون إنترنت.'
                                                    : result.error ?? 'تعذّر حفظ صوت الآية.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                icon: Icon(
                                  isThisAyah && task.isRunning
                                      ? Icons.stop_circle_outlined
                                      : Icons.download_for_offline_outlined,
                                ),
                                label: Text(
                                  isThisAyah && task.isRunning
                                      ? 'إيقاف التنزيل'
                                      : 'حفظ صوت هذه الآية دون إنترنت',
                                ),
                              );
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      // Secondary Actions Row
                      Row(
                        children: [
                          Expanded(
                            child: _SecondaryActionButton(
                              icon: Icons.copy,
                              label: 'نسخ',
                              onPressed: () async {
                                final shareText =
                                    '$ayahText [سورة ${chapter.name}: ${ayah.ayah}]';
                                await Clipboard.setData(
                                  ClipboardData(text: shareText),
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('تم نسخ الآية الكريمة'),
                                      duration: Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SecondaryActionButton(
                              icon: Icons.menu_book,
                              label: 'التفسير',
                              onPressed: () =>
                                  Navigator.of(context).pop('tafsir'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          BlocBuilder<QuranCubit, QuranState>(
                            buildWhen: (prev, curr) =>
                                prev.isAyahBookmarked(ayah.globalAyah) !=
                                curr.isAyahBookmarked(ayah.globalAyah),
                            builder: (context, state) {
                              final isBookmarked = state.isAyahBookmarked(
                                ayah.globalAyah,
                              );
                              return Expanded(
                                child: _SecondaryActionButton(
                                  icon: isBookmarked
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  label: isBookmarked ? 'إزالة' : 'حفظ',
                                  badge: isBookmarked ? 'محفوظة' : null,
                                  onPressed: () async {
                                    final cubit = context.read<QuranCubit>();
                                    await cubit.toggleAyahBookmark(
                                      ayah.globalAyah,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            isBookmarked
                                                ? 'تمت إزالة الآية من العلامات'
                                                : 'تم حفظ الآية في العلامات المرجعية',
                                          ),
                                          duration: const Duration(seconds: 2),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      // Memorization Status Action
                      Builder(
                        builder: (context) {
                          QuranMemorizationCubit? memCubit;
                          try {
                            memCubit = context.watch<QuranMemorizationCubit>();
                          } catch (_) {}
                          if (memCubit == null) return const SizedBox.shrink();

                          final item = memCubit.state.getItem(ayah.globalAyah);
                          final status = item.status;

                          Color statusColor;
                          switch (status) {
                            case MemorizationStatus.memorized:
                              statusColor = const Color(0xFF2E7D32);
                            case MemorizationStatus.learning:
                              statusColor = theme.colorScheme.primary;
                            case MemorizationStatus.needsRevision:
                              statusColor = const Color(0xFFE65100);
                            case MemorizationStatus.notStarted:
                              statusColor = theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6);
                          }

                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Material(
                              color: isDark
                                  ? const Color(0xFF1E3027)
                                  : const Color(0xFFEFECE6),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showMemorizationStatusPicker(
                                  context,
                                  memCubit!,
                                  ayah.globalAyah,
                                  status,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        status == MemorizationStatus.memorized
                                            ? Icons.check_circle_rounded
                                            : status ==
                                                  MemorizationStatus
                                                      .needsRevision
                                            ? Icons.replay_rounded
                                            : Icons.school_outlined,
                                        size: 18,
                                        color: statusColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  'حالة الحفظ: ',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withValues(alpha: 0.7),
                                                  ),
                                                ),
                                                Text(
                                                  status.arabicLabel,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (status !=
                                                MemorizationStatus
                                                    .notStarted) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'آخر مراجعة: ${_formatTimeAgo(item.lastReviewedAt)} · القادمة: ${_formatNextReview(item.nextReviewAt)} · الأخطاء: ${item.mistakeCount}',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.55),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Text(
                                        'تغيير',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        MishkatNavigationIcons.forward,
                                        size: 11,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      // Visual Recall Actions
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Material(
                          color: isDark
                              ? const Color(0xFF1B2E24)
                              : const Color(0xFFE8F2EC),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.school_outlined,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'التسميع والاستحضار البصري',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            Navigator.of(context)
                                                .pop('visual_recall_single'),
                                        icon: const Icon(
                                          Icons.visibility_off_outlined,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'تسميع الآية',
                                          style: TextStyle(fontSize: 11.5),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 4,
                                          ),
                                          side: BorderSide(
                                            color: theme.colorScheme.primary
                                                .withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            Navigator.of(context)
                                                .pop('visual_recall_range'),
                                        icon: const Icon(
                                          Icons.linear_scale_rounded,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'تحديد مقطع',
                                          style: TextStyle(fontSize: 11.5),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 4,
                                          ),
                                          side: BorderSide(
                                            color: theme.colorScheme.primary
                                                .withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMemorizationStatusPicker(
    BuildContext context,
    QuranMemorizationCubit cubit,
    int globalAyah,
    MemorizationStatus currentStatus,
  ) async {
    final newStatus = await showModalBottomSheet<MemorizationStatus>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'تحديد حالة الحفظ للآية',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ...MemorizationStatus.values.map(
                (status) => ListTile(
                  title: Text(
                    status.arabicLabel,
                    style: TextStyle(
                      fontWeight: status == currentStatus
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: status == currentStatus
                      ? const Icon(Icons.check_rounded, color: Colors.green)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(status),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (newStatus != null) {
      await cubit.setItemStatus(globalAyah, newStatus);
    }
  }

  int _juzFor(QuranData data, int global) {
    var value = 1;
    for (final juz in data.juz) {
      if (data.globalFor(juz.surah, juz.ayah) <= global) value = juz.number;
    }
    return value;
  }

  String _formatTimeAgo(DateTime? date) {
    if (date == null) return 'لم تُراجع';
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'اليوم';
    if (diff.inDays == 1) return 'أمس';
    if (diff.inDays == 2) return 'منذ يومين';
    if (diff.inDays <= 10) return 'منذ ${diff.inDays} أيام';
    return 'منذ ${diff.inDays} يوم';
  }

  String _formatNextReview(DateTime? date) {
    if (date == null) return 'غير محدد';
    final now = DateTime.now();
    final diff = date.difference(now);
    if (diff.inDays < 0 ||
        (date.year == now.year &&
            date.month == now.month &&
            date.day == now.day)) {
      return 'اليوم';
    }
    if (diff.inDays == 0 || diff.inDays == 1) return 'غداً';
    if (diff.inDays == 2) return 'بعد يومين';
    return 'بعد ${diff.inDays} أيام';
  }
}

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    this.badge,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final String? badge;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = onPressed != null;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isEnabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.38),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isEnabled
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 9,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
