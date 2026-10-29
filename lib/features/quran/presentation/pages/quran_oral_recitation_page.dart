import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/audio_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/oral_recitation_models.dart';
import '../../data/repositories/quran_repository.dart';
import '../cubit/quran_memorization_cubit.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_oral_recitation_cubit.dart';
import '../cubit/quran_oral_recitation_state.dart';
import '../services/speech_recognition_service.dart';

/// Production page for real microphone-based Oral Recitation, real-time Quran alignment,
/// mistake inspection, and memorization progress recording.
class QuranOralRecitationPage extends StatelessWidget {
  const QuranOralRecitationPage({
    super.key,
    this.surahNumber = 1,
    this.startGlobalAyah,
    this.endGlobalAyah,
    this.planId,
    this.speechService,
    this.cubit,
    this.quranRepository,
  });

  final int surahNumber;
  final int? startGlobalAyah;
  final int? endGlobalAyah;
  final String? planId;
  final SpeechRecognitionService? speechService;
  final QuranOralRecitationCubit? cubit;
  final QuranRepository? quranRepository;

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider<QuranOralRecitationCubit>.value(
        value: cubit!,
        child: const _QuranOralRecitationView(),
      );
    }
    return BlocProvider<QuranOralRecitationCubit>(
      create: (ctx) {
        final repo = quranRepository ?? ctx.read<QuranRepository>();
        SpeechRecognitionService resolvedSpeech;
        var ownsSpeechService = false;
        if (speechService != null) {
          resolvedSpeech = speechService!;
        } else {
          try {
            resolvedSpeech = ctx.read<SpeechRecognitionService>();
          } catch (_) {
            resolvedSpeech = NativeSpeechRecognitionService();
            ownsSpeechService = true;
          }
        }
        QuranAudioService? audioService;
        try {
          audioService = ctx.read<QuranCubit>().audioService;
        } catch (_) {}
        final cubit = QuranOralRecitationCubit(
          speechService: resolvedSpeech,
          quranRepository: repo,
          memorizationCubit: ctx.read<QuranMemorizationCubit>(),
          audioService: audioService,
          ownsSpeechService: ownsSpeechService,
        );
        unawaited(() async {
          await cubit.prepareSession(
            surahNumber: surahNumber,
            startGlobalAyah: startGlobalAyah,
            endGlobalAyah: endGlobalAyah,
            planId: planId,
          );
          if (!cubit.isClosed && cubit.state.lifecycle.isPermissionDenied) {
            await cubit.requestPermissionAndInitialize();
          }
        }());
        return cubit;
      },
      child: const _QuranOralRecitationView(),
    );
  }
}

class _QuranOralRecitationView extends StatefulWidget {
  const _QuranOralRecitationView();

  @override
  State<_QuranOralRecitationView> createState() =>
      _QuranOralRecitationViewState();
}

class _QuranOralRecitationViewState extends State<_QuranOralRecitationView>
    with WidgetsBindingObserver {
  final Map<int, GlobalKey> _ayahKeys = <int, GlobalKey>{};
  int? _lastFocusedGlobalAyah;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<QuranOralRecitationCubit>().checkAndRefreshPermission();
    } else if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached ||
            state == AppLifecycleState.hidden) &&
        mounted) {
      final cubit = context.read<QuranOralRecitationCubit>();
      unawaited(cubit.pauseRecitation());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;

    return BlocConsumer<QuranOralRecitationCubit, QuranOralRecitationState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage &&
          current.errorMessage != null &&
          !current.lifecycle.isPermissionDenied &&
          !current.lifecycle.isPermissionPermanentlyDenied &&
          !current.lifecycle.isRecognizerUnavailable &&
          !current.lifecycle.isLanguageUnavailable,
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: Colors.red.shade800,
            ),
          );
        }
      },
      builder: (context, state) {
        if (kDebugMode) {
          debugPrint(
            '[Q14_UI_RENDER] session=${state.sessionId} '
            'ayah=${state.currentGlobalAyah} '
            'wordIdx=${state.currentWordIndex} '
            'committed=${state.committedTargetIndex} '
            'matched=${state.matchedWordsCount} '
            'omi=${state.omissionsCount} '
            'sub=${state.substitutionsCount} '
            'disc=${state.discrepancies.length} '
            'liveTranscript="${state.liveTranscript}"',
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'التسميع الشفهي الذكي',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
          ),
          backgroundColor: colors.background,
          body: SafeArea(
            child: state.lifecycle.isCompleted
                ? _buildCompletedView(context, state)
                : Column(
                    children: [
                      _buildHeaderBanner(context, state),
                      Expanded(child: _buildRecitationCanvas(context, state)),
                      if (state.liveTranscript.isNotEmpty)
                        _buildTranscriptTicker(context, state),
                      _buildControlDock(context, state),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderBanner(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;
    final startAyah = state.targetWords.isEmpty
        ? state.startGlobalAyah
        : state.targetWords.first.ayahInSurah;
    final endAyah = state.targetWords.isEmpty
        ? state.endGlobalAyah
        : state.targetWords.last.ayahInSurah;

    final badgeColor = switch (state.lifecycle) {
      OralRecitationLifecycle.listening => colors.primary,
      OralRecitationLifecycle.paused => Colors.orange,
      OralRecitationLifecycle.requestingPermission ||
      OralRecitationLifecycle.initializingSpeechEngine ||
      OralRecitationLifecycle.permissionGranted => Colors.blue,
      OralRecitationLifecycle.permissionDenied ||
      OralRecitationLifecycle.permissionPermanentlyDenied => Colors.red,
      OralRecitationLifecycle.recognizerUnavailable ||
      OralRecitationLifecycle.languageUnavailable => Colors.orange,
      _ => colors.textSecondary,
    };

    final badgeLabel = switch (state.lifecycle) {
      OralRecitationLifecycle.listening => 'جاري الاستماع...',
      OralRecitationLifecycle.paused => 'متوقف مؤقتاً',
      OralRecitationLifecycle.requestingPermission => 'جارٍ طلب الإذن...',
      OralRecitationLifecycle.permissionGranted => 'تم منح الإذن',
      OralRecitationLifecycle.initializingSpeechEngine =>
        'جارٍ تهيئة المحرك...',
      OralRecitationLifecycle.permissionDenied => 'الإذن مطلوب',
      OralRecitationLifecycle.permissionPermanentlyDenied =>
        'مرفوض من الإعدادات',
      OralRecitationLifecycle.recognizerUnavailable => 'المحرك غير متاح',
      OralRecitationLifecycle.languageUnavailable => 'العربية تحتاج تفعيل',
      _ => 'جاهز للتسميع',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${state.surahName} · الآيات $startAyah - $endAyah',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Icon(Icons.timer_outlined, size: 14, color: colors.textSecondary),
              const SizedBox(width: 4),
              Text(
                AppFormatters.duration(
                  Duration(seconds: state.durationSeconds),
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: MishkatRadius.brPill,
            child: LinearProgressIndicator(
              value: (state.progressPercentage / 100.0).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: colors.borderSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                badgeLabel,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${state.progressPercentage.toStringAsFixed(0)}٪ مكتمل',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecitationCanvas(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;

    final isPermissionGate =
        state.lifecycle.isRequestingPermission ||
        state.lifecycle.isInitializingSpeechEngine ||
        state.lifecycle.isPermissionDenied ||
        state.lifecycle.isPermissionPermanentlyDenied ||
        state.lifecycle.isRecognizerUnavailable ||
        state.lifecycle.isLanguageUnavailable;

    if (isPermissionGate) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _buildPermissionGateCard(context, state),
        ),
      );
    }

    final ayahsMap = <int, List<RecitationWordAlignment>>{};
    for (final word in state.alignedWords) {
      ayahsMap
          .putIfAbsent(word.authoritativeWord.globalAyah, () => [])
          .add(word);
    }
    if (ayahsMap.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: colors.primary),
            const SizedBox(height: 12),
            Text(
              'جارٍ تجهيز جلسة التسميع...',
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    final currentGlobal = ayahsMap.containsKey(state.currentGlobalAyah)
        ? state.currentGlobalAyah
        : ayahsMap.keys.first;
    final isRevealed = state.revealedGlobals.contains(currentGlobal);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark ? colors.surface : const Color(0xFFFFFCF4);

    if (_lastFocusedGlobalAyah != currentGlobal) {
      _lastFocusedGlobalAyah = currentGlobal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ayahContext = _ayahKeys[currentGlobal]?.currentContext;
        if (ayahContext == null) return;
        Scrollable.ensureVisible(
          ayahContext,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          alignment: .28,
        );
      });
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .08),
            borderRadius: MishkatRadius.brXl,
            boxShadow: MishkatShadows.elevated(context),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: BoxDecoration(
              color: pageColor,
              borderRadius: BorderRadius.circular(MishkatRadius.xl - 4),
              border: Border.all(color: colors.primary.withValues(alpha: .3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        tooltip: isRevealed ? 'إخفاء الآية' : 'كشف الآية',
                        icon: Icon(
                          isRevealed
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_outlined,
                          color: colors.primary,
                          size: 20,
                        ),
                        onPressed: () {
                          final cubit = context
                              .read<QuranOralRecitationCubit>();
                          if (isRevealed) {
                            cubit.hideAyah(currentGlobal);
                          } else {
                            cubit.revealAyah(currentGlobal);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: _buildSurahNameplate(context, state.surahName),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'من الآية ${ayahsMap.values.first.first.authoritativeWord.ayahInSurah} إلى الآية ${ayahsMap.values.last.first.authoritativeWord.ayahInSurah}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: colors.primary.withValues(alpha: .22),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          size: 13,
                          color: colors.primary.withValues(alpha: .7),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: colors.primary.withValues(alpha: .22),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final entry in ayahsMap.entries)
                  _buildMushafAyah(
                    context,
                    words: entry.value,
                    isCurrent: entry.key == currentGlobal,
                    isCompleted: state.completedGlobalAyahs.contains(entry.key),
                    isRevealed: state.revealedGlobals.contains(entry.key),
                  ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .06),
                    borderRadius: MishkatRadius.brSm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        state.lifecycle.isListening
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_none_rounded,
                        size: 17,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          state.lifecycle.isListening
                              ? 'تظهر الكلمات تباعاً مع تلاوتك'
                              : state.lifecycle.isPaused
                              ? 'التسميع متوقف مؤقتاً'
                              : 'اضغط بدء التسميع واقرأ من حفظك',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.primaryStrong,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSurahNameplate(BuildContext context, String surahName) {
    final colors = context.mishkat;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .08),
        borderRadius: MishkatRadius.brMd,
        border: Border.all(color: colors.primary.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.diamond_outlined,
            size: 12,
            color: colors.primary.withValues(alpha: .65),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'سورة $surahName',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.primaryStrong,
                fontFamily: 'Amiri',
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.diamond_outlined,
            size: 12,
            color: colors.primary.withValues(alpha: .65),
          ),
        ],
      ),
    );
  }

  Widget _buildMushafAyah(
    BuildContext context, {
    required List<RecitationWordAlignment> words,
    required bool isCurrent,
    required bool isCompleted,
    required bool isRevealed,
  }) {
    final colors = context.mishkat;
    final hasMistake = words.any(
      (word) =>
          word.status == WordAlignmentStatus.omission ||
          word.status == WordAlignmentStatus.substitution,
    );
    final showAll = isCompleted || isRevealed;

    return AnimatedContainer(
      key: _ayahKeys.putIfAbsent(
        words.first.authoritativeWord.globalAyah,
        GlobalKey.new,
      ),
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
      decoration: BoxDecoration(
        color: isCurrent
            ? colors.primary.withValues(alpha: .065)
            : Colors.transparent,
        borderRadius: MishkatRadius.brMd,
        border: isCurrent
            ? Border.all(color: colors.primary.withValues(alpha: .16))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: TextDirection.rtl,
        children: [
          _AyahNumberMedallion(
            number: words.first.authoritativeWord.ayahInSurah,
            isCurrent: isCurrent,
            isCompleted: isCompleted,
            hasMistake: hasMistake,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 8,
              textDirection: TextDirection.rtl,
              alignment: WrapAlignment.start,
              children: [
                for (final word in words)
                  _buildProgressiveMushafWord(
                    context,
                    word,
                    showWord:
                        showAll ||
                        (isCurrent &&
                            word.status != WordAlignmentStatus.upcoming),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressiveMushafWord(
    BuildContext context,
    RecitationWordAlignment word, {
    required bool showWord,
  }) {
    final colors = context.mishkat;
    if (!showWord) {
      final width = 14.0 + ((word.authoritativeWord.wordIndex % 3) * 6);
      return AnimatedContainer(
        key: ValueKey('hidden-${word.authoritativeWord.wordIndex}'),
        duration: const Duration(milliseconds: 180),
        width: width,
        height: 6,
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: colors.borderSubtle.withValues(alpha: .75),
          borderRadius: MishkatRadius.brPill,
        ),
      );
    }

    final Color foreground = switch (word.status) {
      WordAlignmentStatus.omission ||
      WordAlignmentStatus.substitution => colors.error,
      WordAlignmentStatus.uncertain => Colors.orange.shade800,
      WordAlignmentStatus.repetition => Colors.blue.shade700,
      _ => colors.textPrimary,
    };
    final isMistake =
        word.status == WordAlignmentStatus.omission ||
        word.status == WordAlignmentStatus.substitution;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: word.status == WordAlignmentStatus.upcoming
            ? null
            : () => _showDiscrepancyDetail(context, word),
        borderRadius: MishkatRadius.brXs,
        child: AnimatedContainer(
          key: ValueKey('word-${word.authoritativeWord.wordIndex}'),
          duration: const Duration(milliseconds: 180),
          padding: isMistake
              ? const EdgeInsets.symmetric(horizontal: 3)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isMistake
                ? colors.error.withValues(alpha: .09)
                : Colors.transparent,
            borderRadius: MishkatRadius.brXs,
          ),
          child: Text(
            word.authoritativeWord.uthmaniText,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: foreground,
              fontFamily: 'Amiri',
              fontSize: 22,
              height: 1.45,
              fontWeight: FontWeight.w600,
              decoration: isMistake ? TextDecoration.underline : null,
              decorationColor: colors.error,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionGateCard(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;
    final cubit = context.read<QuranOralRecitationCubit>();

    if (state.lifecycle.isRequestingPermission ||
        state.lifecycle.isInitializingSpeechEngine) {
      final isEngine = state.lifecycle.isInitializingSpeechEngine;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isEngine
                ? 'جارٍ تهيئة محرك التعرف الصوتي...'
                : 'جارٍ طلب إذن الميكروفون...',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isEngine
                ? 'يتم التحقق من جاهزية خدمات التعرف على الكلام...'
                : 'يُرجى الموافقة على طلب الإذن في نافذة النظام للمتابعة.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ],
      );
    }

    if (state.lifecycle.isPermissionPermanentlyDenied) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.settings_suggest_rounded,
              size: 36,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'إذن الميكروفون مرفوض من إعدادات الجهاز',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'إذن الميكروفون مرفوض من إعدادات الجهاز. افتح إعدادات التطبيق وفعّل الميكروفون، ثم ارجع وحاول مرة أخرى.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          MishkatPrimaryAction(
            label: 'فتح إعدادات التطبيق',
            icon: const Icon(Icons.settings_outlined),
            isFullWidth: true,
            onPressed: () => cubit.openAppSettings(),
          ),
          const SizedBox(height: 10),
          MishkatSecondaryAction(
            label: 'إعادة التحقق من الإذن',
            icon: const Icon(Icons.refresh_rounded),
            isFullWidth: true,
            onPressed: () => cubit.checkAndRefreshPermission(),
          ),
        ],
      );
    }

    if (state.lifecycle.isLanguageUnavailable) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.record_voice_over_rounded,
              size: 36,
              color: Colors.orange.shade800,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'فعّل العربية للتسميع الصوتي',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            state.errorMessage ?? 'خدمة التعرف الصوتي موجودة، لكن العربية غير مفعّلة فيها. افتح إعدادات الإدخال الصوتي واختر خدمة التعرف ثم أضف العربية أو نزّل حزمة العربية.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          MishkatPrimaryAction(
            label: 'فتح إعدادات الإدخال الصوتي',
            icon: const Icon(Icons.settings_voice_rounded),
            isFullWidth: true,
            onPressed: () => cubit.openSpeechRecognitionSettings(),
          ),
          const SizedBox(height: 10),
          MishkatSecondaryAction(
            label: 'أضفت العربية — أعد الفحص',
            icon: const Icon(Icons.refresh_rounded),
            isFullWidth: true,
            onPressed: () => cubit.checkAndRefreshPermission(),
          ),
        ],
      );
    }

    if (state.lifecycle.isRecognizerUnavailable) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 36,
              color: Colors.orange.shade700,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'خدمة التعرف الصوتي غير متاحة',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            state.errorMessage ?? 'خدمة التعرف الصوتي غير جاهزة. فعّلها أو نزّل حزمة اللغة العربية ثم أعد المحاولة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          MishkatPrimaryAction(
            label: 'فتح إعدادات الإدخال الصوتي',
            icon: const Icon(Icons.settings_voice_rounded),
            isFullWidth: true,
            onPressed: () => cubit.openSpeechRecognitionSettings(),
          ),
          const SizedBox(height: 10),
          MishkatSecondaryAction(
            label: 'إعادة المحاولة',
            icon: const Icon(Icons.refresh_rounded),
            isFullWidth: true,
            onPressed: () => cubit.requestPermissionAndInitialize(),
          ),
        ],
      );
    }

    // Default permission needed / denied state
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: colors.primarySoft,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.mic_rounded, size: 36, color: colors.primary),
        ),
        const SizedBox(height: 16),
        const Text(
          'إذن الميكروفون مطلوب',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'نحتاج إلى إذن الميكروفون حتى نتمكن من الاستماع إلى تلاوتك ومطابقة الكلمات مع الآيات. لا يحتفظ مشكاة بتسجيلك الصوتي.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        MishkatPrimaryAction(
          label: 'السماح والمتابعة',
          icon: const Icon(Icons.mic_rounded),
          isFullWidth: true,
          onPressed: () => cubit.requestPermissionAndInitialize(),
        ),
        const SizedBox(height: 10),
        MishkatSecondaryAction(
          label: 'فتح إعدادات التطبيق',
          icon: const Icon(Icons.settings_outlined),
          isFullWidth: true,
          onPressed: () => cubit.openAppSettings(),
        ),
      ],
    );
  }

  Widget _buildTranscriptTicker(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: MishkatRadius.brMd,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 16,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            'مسموع: ',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          Expanded(
            child: Text(
              state.liveTranscript,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlDock(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final cubit = context.read<QuranOralRecitationCubit>();
    final isBusy =
        state.lifecycle.isRequestingPermission ||
        state.lifecycle.isInitializingSpeechEngine;
    final isListening = state.lifecycle == OralRecitationLifecycle.listening;
    final isPaused = state.lifecycle == OralRecitationLifecycle.paused;

    final mainLabel = isListening
        ? 'إيقاف مؤقت'
        : isPaused
        ? 'متابعة'
        : isBusy
        ? 'جارٍ التجهيز...'
        : 'بدء التسميع';
    final mainIcon = isListening
        ? Icons.pause_rounded
        : isPaused
        ? Icons.mic_rounded
        : Icons.mic_none_rounded;
    final VoidCallback? mainAction = isBusy
        ? null
        : isListening
        ? cubit.pauseRecitation
        : isPaused
        ? cubit.resumeRecitation
        : cubit.startRecitation;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      decoration: BoxDecoration(
        color: context.mishkat.surface,
        border: Border(
          top: BorderSide(color: context.mishkat.borderSubtle, width: .7),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _SessionSideAction(
            icon: Icons.stop_circle_outlined,
            label: 'إنهاء',
            onTap: state.hasActiveSession ? cubit.finishSession : null,
          ),
          _SessionMicAction(
            label: mainLabel,
            icon: mainIcon,
            isBusy: isBusy,
            isListening: isListening,
            onTap: mainAction,
          ),
          _SessionSideAction(
            icon: Icons.visibility_outlined,
            label: 'كشف الآية',
            onTap: () => cubit.revealAyah(state.currentGlobalAyah),
          ),
        ],
      ),
    );
  }

  void _showDiscrepancyDetail(
    BuildContext context,
    RecitationWordAlignment word,
  ) {
    final colors = context.mishkat;
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MishkatRadius.lg),
        ),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    word.status.isMatched
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    color: word.status.isMatched
                        ? colors.primary
                        : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'تفاصيل الكلمة (${word.status.arabicLabel})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              MishkatCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'اللفظ القرآني الصحيح: ',
                          style: TextStyle(fontSize: 12),
                        ),
                        const Spacer(),
                        Text(
                          word.authoritativeWord.uthmaniText,
                          style: const TextStyle(
                            fontFamily: 'Amiri',
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (word.recognizedWord != null) ...[
                      const Divider(height: 16),
                      Row(
                        children: [
                          const Text(
                            'اللفظ المسموع: ',
                            style: TextStyle(fontSize: 12),
                          ),
                          const Spacer(),
                          Text(
                            word.recognizedWord!,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: word.status.isMatched
                                  ? colors.primary
                                  : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              MishkatPrimaryAction(
                label: 'حسناً',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompletedView(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;
    final summary = state.summary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.task_alt_rounded,
                color: colors.primary,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'اكتملت جلسة التسميع',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '${state.surahName} · الآيات ${state.startGlobalAyah} - ${state.endGlobalAyah}',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),

          // Statistics Card
          MishkatCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        'نسبة الصحة',
                        '${summary?.accuracyPercentage.toStringAsFixed(0) ?? 0}%',
                        colors.primary,
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        'الكلمات المطابقة',
                        '${summary?.matchedWords ?? 0} / ${summary?.totalWords ?? 0}',
                        colors.textPrimary,
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        'السقط والخطأ',
                        '${(summary?.omissionsCount ?? 0) + (summary?.substitutionsCount ?? 0)}',
                        (summary?.omissionsCount ?? 0) +
                                    (summary?.substitutionsCount ?? 0) >
                                0
                            ? Colors.red
                            : colors.primary,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text(
                        'التقييم المقترح: ',
                        style: TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primarySoft,
                        borderRadius: MishkatRadius.brSm,
                      ),
                      child: Text(
                        summary?.suggestedOutcome.arabicLabel ?? 'جيد',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Commit to Memorization Action
          if (state.isMemorizationCommitted)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: MishkatRadius.brMd,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: colors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'تم تسجيل النتيجة بنجاح في سجل ومراجعة الحفظ!',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            MishkatPrimaryAction(
              label: state.isCommittingToMemorization
                  ? 'جاري التسجيل...'
                  : 'اعتماد النتيجة في سجل الحفظ والمراجعة',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: state.isCommittingToMemorization
                  ? null
                  : () => context
                        .read<QuranOralRecitationCubit>()
                        .commitToMemorization(),
            ),

          const SizedBox(height: 12),
          MishkatSecondaryAction(
            label: 'إجراء جلسة تسميع جديدة',
            icon: const Icon(Icons.replay_rounded),
            onPressed: () =>
                context.read<QuranOralRecitationCubit>().prepareSession(
                  surahNumber: state.surahNumber,
                  startGlobalAyah: state.startGlobalAyah,
                  endGlobalAyah: state.endGlobalAyah,
                ),
          ),
          const SizedBox(height: 8),
          MishkatTextAction(
            label: 'العودة لمركز القرآن',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _AyahNumberMedallion extends StatelessWidget {
  const _AyahNumberMedallion({
    required this.number,
    required this.isCurrent,
    required this.isCompleted,
    required this.hasMistake,
  });

  final int number;
  final bool isCurrent;
  final bool isCompleted;
  final bool hasMistake;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final accent = hasMistake
        ? colors.error
        : isCompleted
        ? colors.success
        : colors.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        color: isCurrent || isCompleted
            ? accent.withValues(alpha: .1)
            : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: accent.withValues(alpha: isCurrent ? .7 : .35),
          width: isCurrent ? 1.4 : 1,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '$number',
            style: TextStyle(
              color: accent,
              fontFamily: 'Amiri',
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isCompleted)
            PositionedDirectional(
              end: -1,
              bottom: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 1.5),
                ),
              ),
            ),
          if (isCurrent && !isCompleted)
            PositionedDirectional(
              end: 3,
              bottom: 2,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionSideAction extends StatelessWidget {
  const _SessionSideAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final foreground = onTap == null
        ? colors.textSecondary.withValues(alpha: .42)
        : colors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: MishkatRadius.brMd,
        child: SizedBox(
          width: 70,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 23, color: foreground),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
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

class _SessionMicAction extends StatelessWidget {
  const _SessionMicAction({
    required this.label,
    required this.icon,
    required this.isBusy,
    required this.isListening,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isBusy;
  final bool isListening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: MishkatRadius.brLg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: isListening ? colors.primaryDark : colors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: .25),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: isBusy
                    ? const Center(
                        child: SizedBox(
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: 29),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: isBusy ? colors.textSecondary : colors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
