import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_state.dart';

String quranListeningModeLabel(QuranListeningMode mode) => switch (mode) {
  QuranListeningMode.once => 'تشغيل مرة واحدة',
  QuranListeningMode.repeat => 'تكرار السورة',
  QuranListeningMode.next => 'تشغيل السورة التالية',
};

IconData quranListeningModeIcon(QuranListeningMode mode) => switch (mode) {
  QuranListeningMode.once => Icons.looks_one_outlined,
  QuranListeningMode.repeat => Icons.repeat_one_rounded,
  QuranListeningMode.next => Icons.playlist_play_rounded,
};

String formatSleepTimer(Duration duration) {
  final seconds = (duration.inMilliseconds / 1000).ceil().clamp(0, 86400);
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

Future<void> showQuranPlayerSettings(BuildContext context, QuranCubit cubit) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: context.mishkat.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => QuranPlayerSettingsSheet(cubit: cubit),
    );

/// Listening preferences are independent of the Mushaf's Ayah repetition tools.
class QuranPlayerSettingsSheet extends StatefulWidget {
  const QuranPlayerSettingsSheet({super.key, required this.cubit});

  final QuranCubit cubit;

  @override
  State<QuranPlayerSettingsSheet> createState() =>
      _QuranPlayerSettingsSheetState();
}

class _QuranPlayerSettingsSheetState extends State<QuranPlayerSettingsSheet> {
  final _minutesController = TextEditingController();
  bool _showCustomTimer = false;
  String? _timerError;

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  void _applyCustomTimer() {
    final value = int.tryParse(
      AppFormatters.normalizeArabic(_minutesController.text),
    );
    if (value == null || value < 1 || value > 720) {
      setState(() => _timerError = 'أدخل مدة من دقيقة إلى ٧٢٠ دقيقة');
      return;
    }
    widget.cubit.setSleepTimer(Duration(minutes: value));
    FocusScope.of(context).unfocus();
    setState(() {
      _timerError = null;
      _showCustomTimer = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final media = MediaQuery.of(context);
    final availableHeight =
        (media.size.height - media.viewInsets.bottom - media.padding.top).clamp(
          0.0,
          double.infinity,
        );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight * .94),
          child: Material(
            color: colors.surface,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SheetHeader(),
                  Flexible(
                    child: BlocBuilder<QuranCubit, QuranState>(
                      bloc: widget.cubit,
                      builder: (context, state) {
                        final isStation = state.activeStation != null;
                        final remaining = state.sleepTimerRemaining;
                        return SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!isStation) ...[
                                _SettingsGroup(
                                  title: 'عند انتهاء السورة',
                                  icon: Icons.playlist_play_rounded,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          for (final mode
                                              in QuranListeningMode.values) ...[
                                            if (mode != QuranListeningMode.once)
                                              const SizedBox(width: 8),
                                            Expanded(
                                              child: _ChoiceTile(
                                                key: Key(
                                                  'listening-mode-${mode.name}',
                                                ),
                                                label: switch (mode) {
                                                  QuranListeningMode.once =>
                                                    'مرة واحدة',
                                                  QuranListeningMode.repeat =>
                                                    'تكرار',
                                                  QuranListeningMode.next =>
                                                    'التالي',
                                                },
                                                semanticLabel:
                                                    quranListeningModeLabel(
                                                      mode,
                                                    ),
                                                icon: quranListeningModeIcon(
                                                  mode,
                                                ),
                                                selected:
                                                    state.listeningMode == mode,
                                                onTap: () => widget.cubit
                                                    .setListeningMode(mode),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        switch (state.listeningMode) {
                                          QuranListeningMode.once =>
                                            'يتوقف الصوت بعد نهاية السورة.',
                                          QuranListeningMode.repeat =>
                                            'تُعاد السورة تلقائيًا من بدايتها.',
                                          QuranListeningMode.next => 'يتابع السور بالترتيب حتى سورة الناس.',
                                        },
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: colors.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              _SettingsGroup(
                                title: 'مؤقت النوم',
                                icon: Icons.bedtime_outlined,
                                trailing: remaining == null
                                    ? Text(
                                        'غير مفعّل',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: colors.textMuted),
                                      )
                                    : Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.primarySoft,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'متبقٍ ${formatSleepTimer(remaining)}',
                                          key: const Key(
                                            'sleep-timer-countdown',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: colors.primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        for (final minutes in [
                                          10,
                                          20,
                                          30,
                                          60,
                                        ]) ...[
                                          if (minutes != 10)
                                            const SizedBox(width: 8),
                                          Expanded(
                                            child: _ChoiceTile(
                                              key: Key('sleep-timer-$minutes'),
                                              label: minutes.toString(),
                                              caption: 'دقيقة',
                                              semanticLabel:
                                                  'إيقاف بعد $minutes دقيقة',
                                              onTap: () =>
                                                  widget.cubit.setSleepTimer(
                                                    Duration(minutes: minutes),
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            foregroundColor: colors.primary,
                                          ),
                                          onPressed: () => setState(() {
                                            _showCustomTimer =
                                                !_showCustomTimer;
                                            _timerError = null;
                                          }),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 16,
                                          ),
                                          label: const Text('مدة مخصصة'),
                                        ),
                                        const Spacer(),
                                        if (remaining != null)
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              foregroundColor:
                                                  colors.textSecondary,
                                            ),
                                            onPressed: () => widget.cubit
                                                .setSleepTimer(null),
                                            child: const Text('إلغاء المؤقت'),
                                          ),
                                      ],
                                    ),
                                    if (_showCustomTimer) ...[
                                      Divider(
                                        height: 20,
                                        color: colors.borderSubtle,
                                      ),
                                      TextField(
                                        key: const Key(
                                          'sleep-timer-custom-minutes',
                                        ),
                                        controller: _minutesController,
                                        keyboardType: TextInputType.number,
                                        textInputAction: TextInputAction.done,
                                        scrollPadding: const EdgeInsets.only(
                                          bottom: 80,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: 'المدة بالدقائق',
                                          hintText: 'مثلاً ١٠',
                                          errorText: _timerError,
                                          filled: true,
                                          fillColor: colors.surface,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        onSubmitted: (_) => _applyCustomTimer(),
                                      ),
                                      const SizedBox(height: 10),
                                      FilledButton(
                                        onPressed: _applyCustomTimer,
                                        child: const Text('بدء المؤقت'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (!isStation) ...[
                                const SizedBox(height: 12),
                                _SettingsGroup(
                                  title: 'سرعة التلاوة',
                                  icon: Icons.speed_rounded,
                                  child: Row(
                                    children: [
                                      for (final speed in [
                                        0.75,
                                        1.0,
                                        1.25,
                                        1.5,
                                      ]) ...[
                                        if (speed != .75)
                                          const SizedBox(width: 6),
                                        Expanded(
                                          child: _ChoiceTile(
                                            label: speed == 1
                                                ? 'الطبيعية'
                                                : '$speed×',
                                            semanticLabel:
                                                'سرعة التلاوة $speed',
                                            selected:
                                                state.playbackSpeed == speed,
                                            compact: true,
                                            onTap: () => widget.cubit
                                                .setPlaybackSpeed(speed),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Text(
                                'يستمر الصوت في الخلفية وعند قفل الشاشة',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.textSecondary),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(
            color: colors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 20, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 22,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إعدادات المشغّل',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'خصّص التلاوة والاستماع',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'إغلاق الإعدادات',
                style: IconButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  backgroundColor: colors.surfaceMuted,
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.borderSubtle),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.icon,
    this.caption,
    this.selected = false,
    this.compact = false,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final IconData? icon;
  final String? caption;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final theme = Theme.of(context);
    final foreground = selected ? colors.primary : colors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.primarySoft : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? colors.primary : colors.borderSubtle,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 46 : 66),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 22, color: foreground),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      caption!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
