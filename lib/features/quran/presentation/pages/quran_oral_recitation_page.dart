import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/audio_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/quran_text_style.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/cubit/settings_state.dart';
import '../../data/models/oral_recitation_models.dart';
import '../../data/repositories/quran_repository.dart';
import '../cubit/quran_memorization_cubit.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_oral_recitation_cubit.dart';
import '../cubit/quran_oral_recitation_state.dart';
import '../services/speech_recognition_service.dart';
import '../services/offline_speech_recognition_service.dart';
import '../services/arabic_speech_model_service.dart';
import '../services/recitation_feedback_controller.dart';
import '../widgets/arabic_speech_model_sheet.dart';
import '../widgets/oral_recitation_mushaf.dart';
import '../widgets/recitation_feedback_settings.dart';

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
    this.feedbackOutput,
  });

  final int surahNumber;
  final int? startGlobalAyah;
  final int? endGlobalAyah;
  final String? planId;
  final SpeechRecognitionService? speechService;
  final QuranOralRecitationCubit? cubit;
  final QuranRepository? quranRepository;
  final RecitationFeedbackOutput? feedbackOutput;

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider<QuranOralRecitationCubit>.value(
        value: cubit!,
        child: _QuranOralRecitationView(feedbackOutput: feedbackOutput),
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
            resolvedSpeech = OfflineSpeechRecognitionService();
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
      child: _QuranOralRecitationView(feedbackOutput: feedbackOutput),
    );
  }
}

class _QuranOralRecitationView extends StatefulWidget {
  const _QuranOralRecitationView({this.feedbackOutput});

  final RecitationFeedbackOutput? feedbackOutput;

  @override
  State<_QuranOralRecitationView> createState() =>
      _QuranOralRecitationViewState();
}

class _QuranOralRecitationViewState extends State<_QuranOralRecitationView>
    with WidgetsBindingObserver {
  final _arabicModel = ArabicSpeechModelService.instance;
  QuranOralRecitationCubit? _pageCubit;
  RecitationFeedbackController? _feedback;
  SettingsCubit? _settingsCubit;
  StreamSubscription<SettingsState>? _settingsSubscription;
  final _feedbackMode = ValueNotifier(RecitationFeedbackMode.sound);
  bool? _previousWakeLock;
  bool _wantsWakeLock = false;
  Future<void> _wakeLockOperation = Future<void>.value();
  int? _peekedGlobalAyah;

  void _startPeek() {
    final cubit = _pageCubit;
    if (cubit == null || cubit.isClosed || cubit.state.isDraining) return;
    final state = cubit.state;
    final global = state.isOfflineEngine && state.targetWords.isNotEmpty
        ? state
              .targetWords[state.currentWordIndex.clamp(
                0,
                state.targetWords.length - 1,
              )]
              .globalAyah
        : state.currentGlobalAyah;
    if (cubit.state.revealedGlobals.contains(global)) return;
    _peekedGlobalAyah = global;
    cubit.revealAyah(global);
  }

  void _endPeek() {
    final global = _peekedGlobalAyah;
    _peekedGlobalAyah = null;
    final cubit = _pageCubit;
    if (global != null && cubit != null && !cubit.isClosed) {
      cubit.hideAyah(global);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SettingsCubit? settings;
    try {
      settings = context.read<SettingsCubit>();
    } catch (_) {
      // Standalone previews can use the same controls without persisted settings.
    }
    if (!identical(settings, _settingsCubit)) {
      unawaited(_settingsSubscription?.cancel());
      _settingsCubit = settings;
      _settingsSubscription = settings?.stream.listen((state) {
        if (mounted) _applyFeedbackMode(state.settings.recitationFeedbackMode);
      });
    }
    if (settings != null) {
      _applyFeedbackMode(settings.state.settings.recitationFeedbackMode);
    }
    final cubit = context.read<QuranOralRecitationCubit>();
    if (!identical(cubit, _pageCubit)) {
      _feedback?.setForeground(false);
      unawaited(_feedback?.dispose());
      _pageCubit = cubit;
      _bindFeedback();
    }
    _syncWakeLock(_pageCubit!.state.isListening);
  }

  void _applyFeedbackMode(RecitationFeedbackMode mode) {
    _feedbackMode.value = mode;
    _feedback?.setMode(mode);
  }

  void _changeFeedbackMode(RecitationFeedbackMode mode) {
    _applyFeedbackMode(mode);
    final settings = _settingsCubit;
    if (settings != null) {
      unawaited(settings.setRecitationFeedbackMode(mode));
    }
  }

  void _bindFeedback() {
    final cubit = _pageCubit;
    if (cubit == null) return;
    _feedback = RecitationFeedbackController(
      cubit: cubit,
      mode: _feedbackMode.value,
      output: widget.feedbackOutput,
    );
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _feedback!.setForeground(
      lifecycle == null || lifecycle == AppLifecycleState.resumed,
    );
  }

  @override
  void didUpdateWidget(covariant _QuranOralRecitationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cubit = context.read<QuranOralRecitationCubit>();
    if (!identical(cubit, _pageCubit) ||
        !identical(oldWidget.feedbackOutput, widget.feedbackOutput)) {
      _feedback?.setForeground(false);
      unawaited(_feedback?.dispose());
      _pageCubit = cubit;
      _bindFeedback();
    }
  }

  // Restore the user's existing keep-awake preference after this session.
  void _syncWakeLock(bool enabled) {
    _wantsWakeLock = enabled;
    _wakeLockOperation = _wakeLockOperation.then((_) async {
      try {
        if (_wantsWakeLock) {
          _previousWakeLock ??= await WakelockPlus.enabled;
          if (_wantsWakeLock) await WakelockPlus.enable();
        } else if (_previousWakeLock != null) {
          final previous = _previousWakeLock!;
          _previousWakeLock = null;
          await WakelockPlus.toggle(enable: previous);
        }
      } catch (_) {
        // Wakelock is optional on unsupported platforms and in widget tests.
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arabicModel.setForeground(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feedback?.setForeground(false);
    unawaited(_feedback?.dispose());
    unawaited(_settingsSubscription?.cancel());
    _feedbackMode.dispose();
    _endPeek();
    _syncWakeLock(false);
    unawaited(_pageCubit?.pauseRecitation());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _feedback?.setForeground(state == AppLifecycleState.resumed);
    _arabicModel.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<QuranOralRecitationCubit>().checkAndRefreshPermission();
      if (!_pageCubit!.state.isOfflineEngine) unawaited(_arabicModel.refresh());
    } else if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached ||
            state == AppLifecycleState.hidden) &&
        mounted) {
      final cubit = context.read<QuranOralRecitationCubit>();
      _endPeek();
      _syncWakeLock(false);
      unawaited(cubit.pauseRecitation());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final paper = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF111C18)
        : const Color(0xFFF6F3EB);

    return BlocConsumer<QuranOralRecitationCubit, QuranOralRecitationState>(
      buildWhen: (previous, current) =>
          previous.copyWith(audioLevel: current.audioLevel) != current,
      listenWhen: (previous, current) =>
          previous.isListening != current.isListening ||
          (previous.errorMessage != current.errorMessage &&
              current.errorMessage != null &&
              !current.lifecycle.isPermissionDenied &&
              !current.lifecycle.isPermissionPermanentlyDenied &&
              !current.lifecycle.isRecognizerUnavailable &&
              !current.lifecycle.isLanguageUnavailable),
      listener: (context, state) {
        _syncWakeLock(state.isListening);
        if (state.errorMessage != null &&
            !state.lifecycle.isPermissionDenied &&
            !state.lifecycle.isPermissionPermanentlyDenied &&
            !state.lifecycle.isRecognizerUnavailable &&
            !state.lifecycle.isLanguageUnavailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: Colors.red.shade800,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: paper,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: MediaQuery.textScalerOf(context)
                .scale(36)
                .clamp(64.0, 120.0),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.isCompleted ? 'نتيجة التسميع' : state.surahName,
                  key: const ValueKey('recitation-screen-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (!state.isCompleted)
                  Text(
                    state.targetWords.isEmpty
                        ? 'التسميع من الحفظ'
                        : 'تسميع · الآيات ${state.targetWords.first.ayahInSurah}–${state.targetWords.last.ayahInSurah}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
            centerTitle: true,
            actions: [
              if (!state.isCompleted)
                IconButton(
                  key: const ValueKey('recitation-display-options'),
                  tooltip: 'طريقة العرض',
                  onPressed: _showDisplayOptions,
                  icon: const Icon(Icons.tune_rounded),
                ),
            ],
          ),
          backgroundColor: paper,
          body: SafeArea(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: state.lifecycle.isCompleted
                  ? _buildCompletedView(context, state)
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: LinearProgressIndicator(
                            key: const ValueKey('recitation-session-progress'),
                            value: (state.coveragePercentage / 100).clamp(0, 1),
                            minHeight: 2,
                            color: colors.primary.withValues(alpha: .65),
                            backgroundColor: colors.borderSubtle.withValues(
                              alpha: .4,
                            ),
                            borderRadius: MishkatRadius.brPill,
                            semanticsLabel: 'تقدم التسميع',
                          ),
                        ),
                        Expanded(child: _buildRecitationCanvas(context, state)),
                        _buildControlDock(context, state),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildArabicModelButton(QuranOralRecitationState state) {
    if (state.isOfflineEngine) {
      final colors = context.mishkat;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.offline_pin_outlined,
            color: colors.textSecondary,
            size: 16,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              state.lifecycle.isInitializingSpeechEngine
                  ? 'تجهيز نموذج التسميع على جهازك'
                  : 'معالجة محلية · دون إنترنت · لا يُحفظ صوتك',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11.5,
                height: 1.6,
              ),
            ),
          ),
        ],
      );
    }
    return AnimatedBuilder(
      animation: _arabicModel,
      builder: (context, _) => TextButton.icon(
        onPressed: _showArabicModel,
        icon: Icon(
          _arabicModel.status.isInstalled
              ? Icons.offline_pin_outlined
              : Icons.download_rounded,
          size: 19,
        ),
        label: Text(
          _arabicModel.status.isInstalled
              ? 'العربية جاهزة دون إنترنت'
              : _arabicModel.status.isPending
              ? 'حزمة العربية قيد التنزيل'
              : 'تحميل حزمة العربية · التسميع دون إنترنت',
        ),
      ),
    );
  }

  Future<void> _showArabicModel() async {
    final cubit = context.read<QuranOralRecitationCubit>();
    // Model selection changes take effect on a fresh capture session.
    await cubit.pauseRecitation();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ArabicSpeechModelSheet(
        service: _arabicModel,
        openSettings: cubit.openSpeechRecognitionSettings,
      ),
    );
  }

  Future<void> _showSessionDetails() async {
    final cubit = context.read<QuranOralRecitationCubit>();
    final colors = context.mishkat;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: colors.surface,
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<QuranOralRecitationCubit, QuranOralRecitationState>(
          buildWhen: (before, after) =>
              before.copyWith(audioLevel: after.audioLevel) != after,
          builder: (context, state) => Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'تفاصيل التسميع',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _buildHeaderBanner(context, state),
                  if (state.targetWords.isNotEmpty)
                    _buildCurrentAyahGuide(context, state),
                  if (state.liveTranscript.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildTranscriptTicker(context, state),
                  ],
                  const SizedBox(height: 18),
                  _buildArabicModelButton(state),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('العودة إلى المصحف'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
      OralRecitationLifecycle.listening =>
        state.isDraining
            ? 'تثبيت آخر ما قرأت...'
            : state.isProcessingSpeech
            ? 'مطابقة التلاوة...'
            : 'جارٍ الاستماع...',
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
      OralRecitationLifecycle.processing => 'تثبيت آخر ما قرأت...',
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
              value: (state.coveragePercentage / 100.0).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: colors.borderSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
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
                  Flexible(
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '${state.coveragePercentage.toStringAsFixed(0)}٪ من المقطع',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
              if (state.hintCount > 0)
                Text(
                  'تلميحات: ${state.hintCount}',
                  style: TextStyle(color: colors.warning, fontSize: 11),
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

    if (state.targetWords.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // The Quran text scrolls within its own viewport. Keep page navigation
        // visible even when a correction or landscape reduces that viewport.
        return Column(
          children: [
            Expanded(child: OralRecitationMushaf(state: state)),
            if (state.correctionWordIndex != null &&
                !state.isCorrectionProvisional)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .42,
                ),
                child: SingleChildScrollView(
                  child: _buildCorrectionCard(context, state),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showDisplayOptions() async {
    final cubit = context.read<QuranOralRecitationCubit>();
    final colors = context.mishkat;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colors.surface,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: BlocProvider.value(
          value: cubit,
          child:
              BlocBuilder<QuranOralRecitationCubit, QuranOralRecitationState>(
                buildWhen: (previous, current) =>
                    previous.mode != current.mode ||
                    previous.canChangeMode != current.canChangeMode ||
                    previous.isListening != current.isListening ||
                    previous.isDraining != current.isDraining ||
                    previous.isOfflineEngine != current.isOfflineEngine ||
                    previous.lifecycle.isInitializingSpeechEngine !=
                        current.lifecycle.isInitializingSpeechEngine,
                builder: (context, state) => SingleChildScrollView(
                  key: const ValueKey('recitation-display-sheet-scroll'),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'طريقة عرض المصحف',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'اختر ما يظهر لك أثناء التسميع.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildModeSelector(context, state),
                      if (!state.canChangeMode)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Icon(
                                  Icons.lock_outline_rounded,
                                  size: 16,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'يبقى الوضع ثابتاً لهذه المحاولة. يمكنك تغييره عند بدء محاولة جديدة.',
                                  key: const ValueKey(
                                    'recitation-mode-locked-note',
                                  ),
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                    height: 1.7,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      Divider(height: 1, color: colors.borderSubtle),
                      const SizedBox(height: 20),
                      ValueListenableBuilder<RecitationFeedbackMode>(
                        valueListenable: _feedbackMode,
                        builder: (context, mode, _) =>
                            RecitationFeedbackSettings(
                              mode: mode,
                              onChanged: _changeFeedbackMode,
                              canPreview:
                                  !state.isListening && !state.isDraining,
                              onPreview: () => unawaited(_feedback?.preview()),
                            ),
                      ),
                      const SizedBox(height: 20),
                      _buildArabicModelButton(state),
                      const SizedBox(height: 14),
                      TextButton(
                        key: const ValueKey('recitation-display-sheet-close'),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: colors.primaryStrong,
                          backgroundColor: colors.surfaceVariant,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('العودة إلى المصحف'),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildCurrentAyahGuide(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;
    final cubit = context.read<QuranOralRecitationCubit>();
    final index =
        (state.isOfflineEngine
                ? state.currentWordIndex
                : state.correctionWordIndex ?? state.currentWordIndex)
            .clamp(0, state.targetWords.length - 1);
    final word = state.targetWords[index];
    final ayahWords = state.targetWords
        .where((item) => item.globalAyah == word.globalAyah)
        .toList(growable: false);
    final isRevealed = state.revealedGlobals.contains(word.globalAyah);
    final cue = state.unresolvedMistakeWordIndices.contains(index)
        ? null
        : state.hintedWordIndices.contains(index) ||
              state.mode == OralRecitationMode.reading
        ? word
        : state.mode == OralRecitationMode.firstWord
        ? ayahWords.first
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${state.mode.arabicLabel} · الآية ${word.ayahInSurah} · الكلمة ${ayahWords.indexOf(word) + 1} من ${ayahWords.length}',
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ),
          if (cue != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  cue.uthmaniText,
                  key: const ValueKey('recitation-word-cue'),
                  textDirection: TextDirection.rtl,
                  locale: const Locale('ar'),
                  style: QuranTextStyle.ayah(
                    fontSize: 21,
                    height: 1.6,
                    color: colors.primaryStrong,
                  ),
                ),
              ),
            ),
          IconButton(
            key: const ValueKey('recitation-reveal-current-ayah-details'),
            tooltip: isRevealed ? 'إخفاء الآية' : 'كشف الآية',
            visualDensity: VisualDensity.compact,
            onPressed: state.isDraining
                ? null
                : () => isRevealed
                      ? cubit.hideAyah(word.globalAyah)
                      : cubit.revealAyah(word.globalAyah),
            icon: Icon(
              isRevealed
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_outlined,
              size: 20,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;
    final editable = state.canChangeMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        for (final mode in const [
          OralRecitationMode.hidden,
          OralRecitationMode.firstWord,
          OralRecitationMode.reading,
        ])
          Builder(
            builder: (context) {
              final selected = state.mode == mode;
              final description = switch (mode) {
                OralRecitationMode.hidden =>
                  'تبقى الآيات مخفية حتى تُتمّ تلاوتها.',
                OralRecitationMode.firstWord =>
                  'تظهر أول كلمة لمساعدتك على البدء.',
                OralRecitationMode.reading =>
                  'تظهر الآيات كاملة مع تتبّع التلاوة.',
              };
              final onSelect = editable
                  ? () => context.read<QuranOralRecitationCubit>().setMode(mode)
                  : null;
              final borderRadius = BorderRadius.circular(16);
              return Semantics(
                key: ValueKey('recitation-mode-${mode.name}'),
                label: '${mode.arabicLabel}. $description',
                selected: selected,
                inMutuallyExclusiveGroup: true,
                enabled: editable,
                button: true,
                onTap: onSelect,
                excludeSemantics: true,
                child: Material(
                  color: selected ? colors.primarySoft : colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: borderRadius,
                    side: BorderSide(
                      color: selected ? colors.primary : colors.borderSubtle,
                      width: selected ? 1.2 : 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: onSelect,
                    excludeFromSemantics: true,
                    borderRadius: borderRadius,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            switch (mode) {
                              OralRecitationMode.reading =>
                                Icons.menu_book_outlined,
                              OralRecitationMode.firstWord =>
                                Icons.lightbulb_outline_rounded,
                              OralRecitationMode.hidden =>
                                Icons.visibility_off_outlined,
                            },
                            size: 22,
                            color: selected
                                ? colors.primaryStrong
                                : colors.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mode.arabicLabel,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  description,
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            selected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: selected ? colors.primary : colors.textMuted,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildListeningFeedback(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;
    final elapsed = Duration(seconds: state.durationSeconds);
    final clock = elapsed.inHours > 0
        ? '${elapsed.inHours}:${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}'
        : '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    final status = state.isDraining
        ? 'تثبيت التلاوة'
        : state.isListening
        ? 'جارٍ الاستماع'
        : state.lifecycle.isRequestingPermission ||
              state.lifecycle.isInitializingSpeechEngine
        ? 'جارٍ التجهيز'
        : state.isPaused
        ? 'متوقف مؤقتًا'
        : 'جاهز للتسميع';
    return Row(
      children: [
        if (state.isListening || state.isDraining) ...[
          SizedBox(
            width: 26,
            child:
                BlocSelector<
                  QuranOralRecitationCubit,
                  QuranOralRecitationState,
                  double
                >(
                  selector: (value) => value.audioLevel,
                  builder: (_, level) => LinearProgressIndicator(
                    key: const ValueKey('recitation-audio-level'),
                    value: state.isDraining ? null : level.clamp(0.0, 1.0),
                    minHeight: 3,
                    borderRadius: MishkatRadius.brPill,
                    color: colors.primary,
                    backgroundColor: colors.borderSubtle,
                    semanticsLabel: 'مستوى صوت الميكروفون',
                  ),
                ),
          ),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary, fontSize: 10.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          clock,
          textDirection: TextDirection.ltr,
          style: TextStyle(color: colors.textSecondary, fontSize: 10),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.keyboard_arrow_up_rounded,
          size: 15,
          color: colors.textSecondary,
        ),
      ],
    );
  }

  Widget _buildCorrectionCard(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;
    final cubit = context.read<QuranOralRecitationCubit>();
    final index = state.correctionWordIndex!;
    final definite = state.unresolvedMistakeWordIndices.contains(index);
    final color = definite ? colors.error : colors.warning;
    return Container(
      key: const ValueKey('recitation-correction'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: MishkatRadius.brSm,
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            definite ? 'الصحيح:' : 'لم تتضح كلمة في المقطع الأخير',
            style: TextStyle(color: color, fontSize: 12),
          ),
          if (definite) ...[
            Text(
              state.targetWords[index].uthmaniText,
              key: const ValueKey('recitation-correct-word'),
              textDirection: TextDirection.rtl,
              locale: const Locale('ar'),
              style: QuranTextStyle.ayah(
                fontSize: 22,
                height: 1.6,
                color: color,
              ),
            ),
            Text(
              'أعد الكلمة أو واصل التلاوة.',
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ] else ...[
            TextButton(
              onPressed: state.isDraining ? null : cubit.hintCurrentWord,
              child: const Text('تلميح الكلمة', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: state.isDraining ? null : cubit.skipCurrentWord,
              child: const Text(
                'أتجاوزها وأراجعها لاحقاً',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionGateCard(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;
    final cubit = context.read<QuranOralRecitationCubit>();

    if (state.isOfflineEngine &&
        (state.lifecycle.isLanguageUnavailable ||
            state.lifecycle.isRecognizerUnavailable)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.offline_bolt_outlined, size: 48, color: colors.warning),
          const SizedBox(height: 16),
          const Text(
            'تعذّر تجهيز التسميع دون إنترنت',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 10),
          Text(
            state.errorMessage ?? 'نموذج التسميع المضمّن غير جاهز. حاول مجدداً، أو أعد تثبيت نسخة التطبيق الكاملة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 20),
          MishkatPrimaryAction(
            label: 'إعادة التجهيز',
            icon: const Icon(Icons.refresh_rounded),
            isFullWidth: true,
            onPressed: cubit.requestPermissionAndInitialize,
          ),
        ],
      );
    }

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
                ? state.isOfflineEngine
                      ? 'جارٍ تجهيز التسميع على جهازك...'
                      : 'جارٍ تهيئة محرك التعرف الصوتي...'
                : 'جارٍ طلب إذن الميكروفون...',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isEngine
                ? state.isOfflineEngine
                      ? 'نفتح النموذج المضمّن. لا يحتاج اتصالاً بالإنترنت.'
                      : 'يتم التحقق من جاهزية خدمات التعرف على الكلام...'
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: MishkatRadius.brMd,
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
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
        state.lifecycle.isInitializingSpeechEngine ||
        state.isDraining ||
        state.lifecycle == OralRecitationLifecycle.processing;
    final isListening = state.isListening;
    final isPaused = state.isPaused;
    final mainLabel = state.isDraining
        ? 'تثبيت التلاوة...'
        : isListening
        ? 'إيقاف مؤقت'
        : isPaused
        ? 'متابعة'
        : isBusy
        ? 'جارٍ التجهيز...'
        : 'بدء التسميع';
    final VoidCallback? mainAction = isBusy
        ? null
        : isListening
        ? cubit.pauseRecitation
        : isPaused
        ? cubit.resumeRecitation
        : cubit.startRecitation;
    final activeAyah = state.targetWords.isEmpty
        ? null
        : state
              .targetWords[state.currentWordIndex.clamp(
                0,
                state.targetWords.length - 1,
              )]
              .globalAyah;
    final revealed = state.revealedGlobals.contains(activeAyah);

    return Padding(
      key: const ValueKey('recitation-control-dock'),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 86,
            child: _SessionMicAction(
              label: mainLabel,
              icon: isListening ? Icons.pause_rounded : Icons.mic_rounded,
              isBusy: isBusy,
              isListening: isListening,
              onTap: mainAction,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'تفاصيل التسميع',
                  child: InkWell(
                    key: const ValueKey('recitation-session-details'),
                    onTap: _showSessionDetails,
                    borderRadius: MishkatRadius.brMd,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: _buildListeningFeedback(context, state),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SessionSideAction(
                      icon: Icons.lightbulb_outline_rounded,
                      label: 'تلميح',
                      onTap: isBusy || state.targetWords.isEmpty
                          ? null
                          : cubit.hintCurrentWord,
                      onLongPressStart: isBusy ? null : _startPeek,
                      onLongPressEnd: _endPeek,
                      tooltip: 'تلميح كلمة، أو اضغط مطولًا لكشف الآية',
                    ),
                    _SessionSideAction(
                      key: const ValueKey('recitation-reveal-current-ayah'),
                      icon: revealed
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_outlined,
                      label: revealed ? 'إخفاء' : 'كشف',
                      onTap: isBusy || activeAyah == null
                          ? null
                          : () => revealed
                                ? cubit.hideAyah(activeAyah)
                                : cubit.revealAyah(activeAyah),
                      tooltip: revealed ? 'إخفاء الآية' : 'كشف الآية الحالية',
                    ),
                    _SessionSideAction(
                      icon: Icons.stop_circle_outlined,
                      label: 'إنهاء',
                      onTap:
                          !isBusy &&
                              state.hasActiveSession &&
                              (state.liveTranscript.trim().isNotEmpty ||
                                  state.alignedWords.any(
                                    (word) => !word.status.isUpcoming,
                                  ))
                          ? cubit.finishSession
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedView(
    BuildContext context,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;
    final summary = state.summary;
    final cubit = context.read<QuranOralRecitationCubit>();
    final first = state.targetWords.firstOrNull;
    final last = state.targetWords.lastOrNull;
    final weakAyahs = <int, List<RecitationWordAlignment>>{};
    final ayahWords = <int, List<RecitationWordAlignment>>{};
    for (final word in state.alignedWords) {
      ayahWords
          .putIfAbsent(word.authoritativeWord.globalAyah, () => [])
          .add(word);
    }
    for (final entry in ayahWords.entries) {
      if (state.hintedGlobalAyahs.contains(entry.key) ||
          entry.value.any(
            (word) =>
                !word.status.isMatched ||
                state.assistedWordIndices.contains(
                  word.authoritativeWord.wordIndex,
                ),
          )) {
        weakAyahs[entry.key] = entry.value;
      }
    }
    final hasAttempt = (summary?.attemptedWords ?? 0) > 0;
    final hasSaveableAyah = ayahWords.values.any(
      (words) => words.every((word) => !word.status.isUpcoming),
    );
    final coverage = summary?.coveragePercentage ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Icon(
            coverage >= 100
                ? Icons.task_alt_rounded
                : Icons.bookmark_added_outlined,
            color: colors.primary,
            size: 46,
          ),
          const SizedBox(height: 12),
          Text(
            coverage >= 100
                ? 'أتممت المقطع، بارك الله فيك'
                : 'نتيجة جلسة التسميع',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            '${state.surahName} · الآيات ${first?.ayahInSurah ?? 1} - ${last?.ayahInSurah ?? 1}',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 5),
          Text(
            '${state.mode.arabicLabel} · ${AppFormatters.duration(Duration(seconds: summary?.durationSeconds ?? 0))}',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 20),
          MishkatCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        'تغطية المقطع',
                        '${coverage.toStringAsFixed(0)}٪',
                        colors.primary,
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        'مطابقة المسموع',
                        hasAttempt
                            ? '${summary!.accuracyPercentage.toStringAsFixed(0)}٪'
                            : '—',
                        colors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: (coverage / 100).clamp(0.0, 1.0),
                  color: colors.primary,
                  backgroundColor: colors.borderSubtle,
                  borderRadius: MishkatRadius.brPill,
                  minHeight: 6,
                ),
                const SizedBox(height: 12),
                Text(
                  '${summary?.matchedWords ?? 0} كلمة مطابقة من ${summary?.attemptedWords ?? 0} كلمة تمت متابعتها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
                if ((summary?.detectedMistakesCount ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'صحّحت ${summary!.correctedMistakesCount} من ${summary.detectedMistakesCount} مواضع خطأ أثناء التلاوة. تبقى ضمن المراجعة.',
                      key: const ValueKey('recitation-mistake-history-summary'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ),
                const Divider(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      'مواضع اختلاف',
                      '${(summary?.omissionsCount ?? 0) + (summary?.substitutionsCount ?? 0)}',
                      colors.error,
                    ),
                    _buildStatItem(
                      'تحتاج إعادة سماع',
                      '${summary?.uncertainCount ?? 0}',
                      colors.warning,
                    ),
                    _buildStatItem(
                      'لم تُقرأ بعد',
                      '${summary?.unrecitedWords ?? 0}',
                      colors.textSecondary,
                    ),
                    _buildStatItem(
                      'التلميحات',
                      '${summary?.hintCount ?? 0}',
                      colors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'النتيجة تتابع مطابقة الكلمات، ولا تقيس أحكام التجويد. المواضع غير الواضحة والتلميحات تُؤخذ في الاعتبار عند تسجيل المراجعة.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 20),
          if (state.isMemorizationCommitted)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: MishkatRadius.brMd,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: colors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'تم حفظ النتيجة في سجل الحفظ والمراجعة.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (hasSaveableAyah)
            MishkatPrimaryAction(
              label: state.isCommittingToMemorization
                  ? 'جارٍ التسجيل...'
                  : 'اعتماد النتيجة في سجل الحفظ والمراجعة',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: state.isCommittingToMemorization
                  ? null
                  : cubit.commitToMemorization,
              isFullWidth: true,
            ),
          if (hasAttempt && !hasSaveableAyah)
            Text(
              'أكمل تسميع آية واحدة لتسجيلها في سجل الحفظ. يمكنك إعادة المواضع أدناه.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          if (weakAyahs.isNotEmpty) ...[
            const SizedBox(height: 12),
            MishkatSecondaryAction(
              label: 'إعادة مواضع المراجعة',
              icon: const Icon(Icons.replay_rounded),
              onPressed: state.isCommittingToMemorization
                  ? null
                  : () => cubit.retrySession(onlyWeakAyahs: true),
              isFullWidth: true,
            ),
            const SizedBox(height: 22),
            Text(
              'خطوتك التالية',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'راجع هذه الآيات ثم أعد تسميعها بهدوء.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final entry in weakAyahs.entries.take(10))
              _buildReviewAyah(context, entry.key, entry.value, state),
            if (weakAyahs.length > 10)
              Text(
                'و${weakAyahs.length - 10} آيات أخرى ضمن «إعادة مواضع المراجعة».',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
          ],
          const SizedBox(height: 14),
          MishkatSecondaryAction(
            label: 'إعادة المقطع كاملاً',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: state.isCommittingToMemorization
                ? null
                : () => cubit.retrySession(),
            isFullWidth: true,
          ),
          const SizedBox(height: 8),
          MishkatTextAction(
            label: 'العودة للحفظ والمراجعة',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewAyah(
    BuildContext context,
    int globalAyah,
    List<RecitationWordAlignment> words,
    QuranOralRecitationState state,
  ) {
    final colors = context.mishkat;
    final uncertain = words.any((word) => word.status.isUncertain);
    final unread = words.every((word) => word.status.isUpcoming);
    final assisted =
        state.hintedGlobalAyahs.contains(globalAyah) ||
        words.any(
          (word) => state.assistedWordIndices.contains(
            word.authoritativeWord.wordIndex,
          ),
        );
    final discrepancies = state.discrepancies
        .where((item) => item.globalAyah == globalAyah)
        .toList();
    final label = unread
        ? 'لم تُقرأ بعد'
        : uncertain
        ? 'أعد سماع هذا الموضع'
        : assisted
        ? 'تدرّب عليها دون تلميح'
        : 'تحتاج تثبيتاً';
    return Container(
      key: ValueKey('review-ayah-$globalAyah'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: MishkatRadius.brMd,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'الآية ${words.first.authoritativeWord.ayahInSurah}',
                style: TextStyle(
                  color: colors.primaryStrong,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: TextStyle(color: colors.warning, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            words.map((word) => word.authoritativeWord.uthmaniText).join(' '),
            textDirection: TextDirection.rtl,
            locale: const Locale('ar'),
            style: QuranTextStyle.ayah(
              color: colors.textPrimary,
              fontSize: 21,
              height: 1.8,
            ),
          ),
          if (discrepancies.isNotEmpty) ...[
            const SizedBox(height: 7),
            for (final discrepancy in discrepancies.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  discrepancy.status.isUncertain
                      ? 'لم تتضح كلمة «${discrepancy.expectedUthmani}» للمحرك.'
                      : discrepancy.recognizedWord?.isNotEmpty == true
                      ? 'المتوقع «${discrepancy.expectedUthmani}» · التقط المحرك «${discrepancy.recognizedWord}»'
                      : 'راجع موضع «${discrepancy.expectedUthmani}».',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: ValueKey('retry-ayah-$globalAyah'),
              onPressed: state.isCommittingToMemorization
                  ? null
                  : () => context.read<QuranOralRecitationCubit>().retrySession(
                      globalAyah: globalAyah,
                    ),
              icon: const Icon(Icons.mic_none_rounded, size: 18),
              label: const Text('إعادة الآية'),
            ),
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

class _SessionSideAction extends StatelessWidget {
  const _SessionSideAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final foreground = onTap == null
        ? colors.textSecondary.withValues(alpha: .42)
        : colors.textSecondary;

    return Tooltip(
      message: tooltip ?? label,
      child: GestureDetector(
        onLongPressStart: onLongPressStart == null
            ? null
            : (_) => onLongPressStart!(),
        onLongPressEnd: onLongPressEnd == null
            ? null
            : (_) => onLongPressEnd!(),
        onLongPressCancel: onLongPressEnd,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: MishkatRadius.brMd,
            child: Container(
              width: 52,
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 21, color: foreground),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
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
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF10261D)
        : Colors.white;
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
                  color: colors.primaryStrong,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: .12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: isBusy
                    ? Center(
                        child: SizedBox(
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              foreground,
                            ),
                          ),
                        ),
                      )
                    : Icon(icon, color: foreground, size: 28),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isBusy ? colors.textSecondary : colors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
