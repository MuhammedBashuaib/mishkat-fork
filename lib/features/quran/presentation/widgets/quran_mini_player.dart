import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../data/models/quran_models.dart';
import '../../domain/models/audio_repeat_config.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_state.dart';
import 'quran_player_settings_sheet.dart';

/// Persistent, lightweight Quran Mini Player widget with Tikrar & Tardid support.
///
/// Provides synchronized playback controls, Ayah position, reciter attribution,
/// scrubbable progress bar, repetition badge, and delay countdown banner.
class QuranMiniPlayer extends StatelessWidget {
  const QuranMiniPlayer({
    super.key,
    this.playbackOrigin = QuranPlaybackOrigin.general,
  });

  final QuranPlaybackOrigin playbackOrigin;

  @override
  Widget build(BuildContext context) {
    final settingsCubit = context.watch<SettingsCubit?>();
    final settings = settingsCubit?.state.settings;
    final autoScroll = settings?.quranAutoScroll ?? true;
    final continuous = settings?.quranContinuous ?? true;
    final cubit = context.read<QuranCubit>();

    return BlocBuilder<QuranCubit, QuranState>(
      buildWhen: (previous, current) =>
          previous.audioStatus != current.audioStatus ||
          previous.audioGlobalAyah != current.audioGlobalAyah ||
          previous.audioSurah != current.audioSurah ||
          previous.audioWordIndex != current.audioWordIndex ||
          previous.listeningMode != current.listeningMode ||
          previous.sleepTimerRemaining != current.sleepTimerRemaining ||
          previous.playbackSpeed != current.playbackSpeed ||
          previous.activeStation != current.activeStation ||
          previous.error != current.error ||
          previous.data != current.data ||
          previous.repeatConfig != current.repeatConfig ||
          previous.repeatState.status != current.repeatState.status,
      builder: (context, state) {
        final isStation = state.activeStation != null;
        final isSurah = state.audioSurah != null;
        final isWord = state.audioWordIndex != null;
        final isListening = isSurah || isStation;
        final isAudioActive =
            state.audioStatus != QuranAudioStatus.idle &&
            (state.audioGlobalAyah != null || isListening);

        if (!isAudioActive && state.audioStatus != QuranAudioStatus.failure) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final isPlaying = state.audioStatus == QuranAudioStatus.playing;
        final isLoading = state.audioStatus == QuranAudioStatus.loading;
        final isFailure = state.audioStatus == QuranAudioStatus.failure;

        final QuranPoint? point =
            (state.audioGlobalAyah == null || state.data == null)
            ? null
            : state.data!.pointForGlobal(state.audioGlobalAyah!);

        final surahNumber = state.audioSurah ?? point?.surah;
        final surahName = (surahNumber != null && state.data != null)
            ? state.data!.chapter(surahNumber).name
            : '';
        final reciterInfo = AppConstants.findReciter(cubit.reciter);

        final title = isStation
            ? state.activeStation!.title
            : isWord
            ? 'نطق الكلمات التعليمي · Quran.com'
            : reciterInfo.name;
        final subtitle = isStation
            ? state.activeStation!.subtitle
            : isSurah
            ? 'سورة $surahName · تلاوة متصلة'
            : (point == null
                  ? 'التلاوة المباركة'
                  : 'سورة $surahName · الآية ${point.ayah}'
                        '${isWord ? ' · الكلمة ${state.audioWordIndex}' : ''}');

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF16241D)
                      : const Color(0xFFF7F4EE),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFDED8CD),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.25 : 0.06,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Row: Reciter, Ayah Context, Controls, Dismiss
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Row(
                        children: [
                          // Reciter & Ayah Details + Repeat Badge
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        isStation
                                            ? Icons.radio_rounded
                                            : Icons.volume_up_rounded,
                                        size: 14,
                                        color: isDark
                                            ? const Color(0xFF4CAF50)
                                            : const Color(0xFF107C41),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          title,
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    theme.colorScheme.onSurface,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          subtitle,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.65),
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (!isListening && !isWord) ...[
                                        const SizedBox(width: 6),
                                        _RepeatBadgeButton(
                                          config: state.repeatConfig,
                                          repeatState: state.repeatState,
                                          onPressed: () =>
                                              _showRepeatConfigSheet(
                                                context,
                                                cubit,
                                                state,
                                                playbackOrigin,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Controls: Prev, Play/Pause, Next
                          if (!isStation && !isWord) ...[
                            IconButton(
                              tooltip: isSurah
                                  ? 'السورة السابقة'
                                  : 'الآية السابقة',
                              iconSize: 22,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: () => cubit.previousAudioAyah(
                                autoScroll: autoScroll,
                              ),
                              icon: const Icon(Icons.skip_previous_rounded),
                            ),
                            const SizedBox(width: 4),
                          ],
                          IconButton.filled(
                            tooltip: isPlaying
                                ? 'إيقاف مؤقت'
                                : 'متابعة التلاوة',
                            iconSize: 24,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                            style: IconButton.styleFrom(
                              backgroundColor: isDark
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFF107C41),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: isLoading
                                ? null
                                : isWord
                                ? cubit.toggleWordAudio
                                : () => cubit.toggleAudio(
                                    continuous: continuous,
                                    autoScroll: autoScroll,
                                    origin: playbackOrigin,
                                  ),
                            icon: isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                          ),
                          const SizedBox(width: 4),
                          if (!isStation && !isWord) ...[
                            IconButton(
                              tooltip: isSurah
                                  ? 'السورة التالية'
                                  : 'الآية التالية',
                              iconSize: 22,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: () =>
                                  cubit.nextAudioAyah(autoScroll: autoScroll),
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                            const SizedBox(width: 2),
                          ],

                          // Close / Stop Playback
                          IconButton(
                            tooltip: 'إيقاف التلاوة',
                            iconSize: 20,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            onPressed: cubit.stopAudio,
                            icon: Icon(
                              Icons.close_rounded,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Delay Countdown Banner (isolated rebuilds)
                    if (!isListening) const _DelayCountdownBanner(),

                    // Scrubber / Progress Bar (isolated rebuilds)
                    if (!isFailure && !isStation)
                      _MiniPlayerProgressBar(cubit: cubit),

                    if (isListening)
                      _ListeningSettingsBar(cubit: cubit, state: state),

                    // Failure Banner
                    if (isFailure)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 16,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                state.error ??
                                    'تعذّر تشغيل التلاوة. تحقق من الاتصال.',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: isWord
                                  ? cubit.toggleWordAudio
                                  : () => cubit.toggleAudio(
                                      continuous: continuous,
                                      autoScroll: autoScroll,
                                      origin: playbackOrigin,
                                    ),
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static void _showRepeatConfigSheet(
    BuildContext context,
    QuranCubit cubit,
    QuranState state,
    QuranPlaybackOrigin playbackOrigin,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RepeatConfigurationSheet(
        cubit: cubit,
        currentConfig: state.repeatConfig,
        currentAyah:
            state.audioGlobalAyah ??
            state.data?.page(state.currentPage).first.global ??
            1,
        playbackOrigin: playbackOrigin,
      ),
    );
  }
}

class _ListeningSettingsBar extends StatelessWidget {
  const _ListeningSettingsBar({required this.cubit, required this.state});

  final QuranCubit cubit;
  final QuranState state;

  @override
  Widget build(BuildContext context) {
    final remaining = state.sleepTimerRemaining;
    final isStation = state.activeStation != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 6),
      child: Row(
        children: [
          Icon(
            remaining != null
                ? Icons.bedtime_outlined
                : isStation
                ? Icons.radio_rounded
                : quranListeningModeIcon(state.listeningMode),
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              remaining != null
                  ? 'يتوقف بعد ${formatSleepTimer(remaining)}'
                  : isStation
                  ? 'بث مباشر'
                  : quranListeningModeLabel(state.listeningMode),
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isStation && state.playbackSpeed != 1.0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${state.playbackSpeed}×'),
            ),
          IconButton(
            key: const Key('quran-player-settings'),
            tooltip: 'إعدادات المشغّل',
            iconSize: 21,
            visualDensity: VisualDensity.compact,
            onPressed: () => showQuranPlayerSettings(context, cubit),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }
}

class _RepeatBadgeButton extends StatelessWidget {
  const _RepeatBadgeButton({
    required this.config,
    required this.repeatState,
    required this.onPressed,
  });

  final AudioRepeatConfig config;
  final AudioRepeatState repeatState;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    String label;
    bool isActive = false;

    if (config.mode == AudioRepeatMode.none) {
      label = '1×';
    } else if (config.mode == AudioRepeatMode.singleAyah) {
      isActive = true;
      final total = config.isInfiniteAyah ? '∞' : '${config.ayahRepeatCount}';
      if (repeatState.isPlaying || repeatState.isDelaying) {
        label = '${repeatState.currentAyahRepeat}/$total';
      } else {
        label = '$total×';
      }
    } else if (config.mode == AudioRepeatMode.rangeLoop) {
      isActive = true;
      final cycle = config.isInfiniteRange ? '∞' : '${config.rangeRepeatCount}';
      label = 'طواف $cycle';
    } else {
      isActive = true;
      label = 'تكرار مقطع';
    }

    return Tooltip(
      message: 'إعدادات التكرار والترديد',
      child: Material(
        color: isActive
            ? (isDark ? const Color(0x334CAF50) : const Color(0x1F107C41))
            : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.repeat_rounded,
                  size: 11,
                  color: isActive
                      ? (isDark
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFF107C41))
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isActive
                        ? (isDark
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF107C41))
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DelayCountdownBanner extends StatelessWidget {
  const _DelayCountdownBanner();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuranCubit, QuranState>(
      buildWhen: (prev, curr) =>
          prev.repeatState.isDelaying != curr.repeatState.isDelaying ||
          prev.repeatState.remainingDelaySeconds !=
              curr.repeatState.remainingDelaySeconds,
      builder: (context, state) {
        if (!state.repeatState.isDelaying) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final seconds = state.repeatState.remainingDelaySeconds;

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x2BD97706) : const Color(0x1FF59E0B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                size: 16,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ترديد الآية... متبقي $seconds ثوانٍ',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFFB45309),
                  ),
                ),
              ),
              InkWell(
                onTap: () => context.read<QuranCubit>().skipDelay(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    'تخطي المهلة',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFB45309),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RepeatConfigurationSheet extends StatefulWidget {
  const _RepeatConfigurationSheet({
    required this.cubit,
    required this.currentConfig,
    required this.currentAyah,
    required this.playbackOrigin,
  });

  final QuranCubit cubit;
  final AudioRepeatConfig currentConfig;
  final int currentAyah;
  final QuranPlaybackOrigin playbackOrigin;

  @override
  State<_RepeatConfigurationSheet> createState() =>
      _RepeatConfigurationSheetState();
}

class _RepeatConfigurationSheetState extends State<_RepeatConfigurationSheet> {
  late AudioRepeatMode _mode;
  late int _ayahRepeats;
  late int _rangeRepeats;
  late int _delaySeconds;
  late int _startAyah;
  late int _endAyah;

  @override
  void initState() {
    super.initState();
    _mode = widget.currentConfig.mode;
    _ayahRepeats = widget.currentConfig.ayahRepeatCount;
    _rangeRepeats = widget.currentConfig.rangeRepeatCount;
    _delaySeconds = widget.currentConfig.delaySeconds;
    _startAyah = widget.currentConfig.startGlobalAyah;
    _endAyah = widget.currentConfig.endGlobalAyah;

    if (_mode == AudioRepeatMode.none) {
      _startAyah = widget.currentAyah;
      _endAyah = widget.currentAyah;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'خيارات التكرار والترديد',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Mode selector
              Text(
                'نمط التكرار:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildModeChip(AudioRepeatMode.none, 'بدون تكرار'),
                  _buildModeChip(AudioRepeatMode.singleAyah, 'تكرار الآية'),
                  _buildModeChip(
                    AudioRepeatMode.rangeLoop,
                    'طواف المقطع كحلقة',
                  ),
                  _buildModeChip(
                    AudioRepeatMode.perAyahRange,
                    'تكرار كل آية في المقطع',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Ayah repeats selector
              if (_mode != AudioRepeatMode.none &&
                  _mode != AudioRepeatMode.rangeLoop) ...[
                Text(
                  'عدد مرات تكرار الآية:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                _buildCountSelector(
                  selected: _ayahRepeats,
                  onSelected: (val) => setState(() => _ayahRepeats = val),
                ),
                const SizedBox(height: 16),
              ],

              // Range repeats selector
              if (_mode == AudioRepeatMode.rangeLoop ||
                  _mode == AudioRepeatMode.perAyahRange) ...[
                Text(
                  'عدد مرات تكرار المقطع (الجولات):',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                _buildCountSelector(
                  selected: _rangeRepeats,
                  onSelected: (val) => setState(() => _rangeRepeats = val),
                ),
                const SizedBox(height: 16),
              ],

              // Tardid delay selector
              Text(
                'مهلة الترديد بين التلاوات (صمت للحفظ):',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              _buildDelaySelector(
                selected: _delaySeconds,
                onSelected: (val) => setState(() => _delaySeconds = val),
              ),
              const SizedBox(height: 24),

              // Apply button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF107C41),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    final newConfig = AudioRepeatConfig(
                      mode: _mode,
                      startGlobalAyah: _startAyah,
                      endGlobalAyah: _endAyah,
                      ayahRepeatCount: _ayahRepeats,
                      rangeRepeatCount: _rangeRepeats,
                      delaySeconds: _delaySeconds,
                    );
                    widget.cubit.setRepeatConfig(newConfig);
                    if (_mode != AudioRepeatMode.none) {
                      widget.cubit.startRepeatPlayback(
                        newConfig,
                        initialGlobalAyah: widget.currentAyah,
                        origin: widget.playbackOrigin,
                      );
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'تطبيق وبدء التلاوة',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeChip(AudioRepeatMode mode, String label) {
    final isSelected = _mode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _mode = mode),
    );
  }

  Widget _buildCountSelector({
    required int selected,
    required ValueChanged<int> onSelected,
  }) {
    const counts = [1, 2, 3, 5, 7, 10, AudioRepeatConfig.infinite];
    return Wrap(
      spacing: 6,
      children: counts.map((count) {
        final isSelected = selected == count;
        final label = count == AudioRepeatConfig.infinite ? '∞' : '$count×';
        return ChoiceChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (_) => onSelected(count),
        );
      }).toList(),
    );
  }

  Widget _buildDelaySelector({
    required int selected,
    required ValueChanged<int> onSelected,
  }) {
    const delays = [0, 1, 2, 3, 5, 7, 10];
    return Wrap(
      spacing: 6,
      children: delays.map((delay) {
        final isSelected = selected == delay;
        final label = delay == 0 ? 'بدون مهلة' : '$delay ث';
        return ChoiceChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (_) => onSelected(delay),
        );
      }).toList(),
    );
  }
}

class _MiniPlayerProgressBar extends StatelessWidget {
  const _MiniPlayerProgressBar({required this.cubit});

  final QuranCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<Duration?>(
      initialData: cubit.audioService.duration,
      stream: cubit.audioService.durationStream,
      builder: (context, durationSnapshot) {
        final duration =
            durationSnapshot.data ??
            cubit.audioService.duration ??
            Duration.zero;

        return StreamBuilder<Duration>(
          initialData: cubit.audioService.currentPosition,
          stream: cubit.audioService.positionStream,
          builder: (context, positionSnapshot) {
            final position =
                positionSnapshot.data ?? cubit.audioService.currentPosition;

            final totalMs = duration.inMilliseconds;
            final currentMs = position.inMilliseconds;
            final progress = (totalMs > 0)
                ? (currentMs / totalMs).clamp(0.0, 1.0)
                : 0.0;

            final posText = _formatDuration(position);
            final durText = _formatDuration(duration);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                      activeTrackColor: isDark
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFF107C41),
                      inactiveTrackColor: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.08),
                      thumbColor: isDark
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFF107C41),
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: (val) {
                        if (totalMs > 0) {
                          cubit.seekAudio(
                            Duration(milliseconds: (val * totalMs).round()),
                          );
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          posText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          durText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
