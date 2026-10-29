import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/memorization_session.dart';
import '../../data/models/memorization_status.dart';
import '../../data/models/murajaah_models.dart';
import '../../data/models/quran_models.dart';
import '../../data/repositories/mushaf_layout_repository.dart';
import '../../domain/models/audio_repeat_config.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_memorization_cubit.dart';
import '../cubit/quran_memorization_state.dart';
import '../cubit/quran_state.dart';
import '../widgets/tafsir_knowledge_sheet.dart';
import 'quran_reader_page.dart';

/// Distraction-free interactive practice and recall drill page for Quran memorization.
class MemorizationSessionPage extends StatefulWidget {
  const MemorizationSessionPage({
    super.key,
    required this.quranData,
    this.initialRepeatCount = 3,
    this.initialDelaySeconds = 3,
    this.startWithAudio = false,
  });

  final QuranData quranData;
  final int initialRepeatCount;
  final int initialDelaySeconds;
  final bool startWithAudio;

  static Route<void> route({
    required QuranData quranData,
    int initialRepeatCount = 3,
    int initialDelaySeconds = 3,
    bool startWithAudio = false,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => MemorizationSessionPage(
        quranData: quranData,
        initialRepeatCount: initialRepeatCount,
        initialDelaySeconds: initialDelaySeconds,
        startWithAudio: startWithAudio,
      ),
    );
  }

  @override
  State<MemorizationSessionPage> createState() =>
      _MemorizationSessionPageState();
}

class _MemorizationSessionPageState extends State<MemorizationSessionPage> {
  late int _sessionRepeatCount;
  late int _sessionDelaySeconds;

  @override
  void initState() {
    super.initState();
    _sessionRepeatCount = widget.initialRepeatCount.clamp(1, 10);
    _sessionDelaySeconds = widget.initialDelaySeconds.clamp(0, 10);
    if (widget.startWithAudio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final memorizationCubit = context.read<QuranMemorizationCubit>();
        final session = memorizationCubit.state.activeSession;
        final currentAyah = session?.currentGlobalAyah;
        if (session == null || currentAyah == null) return;
        memorizationCubit.revealText();
        _startTutorPlayback(currentAyah);
      });
    }
  }

  void _startTutorPlayback(int globalAyah) {
    context.read<QuranCubit>().startRepeatPlayback(
      AudioRepeatConfig(
        mode: AudioRepeatMode.singleAyah,
        startGlobalAyah: globalAyah,
        endGlobalAyah: globalAyah,
        ayahRepeatCount: _sessionRepeatCount,
        delaySeconds: _sessionDelaySeconds,
      ),
      initialGlobalAyah: globalAyah,
      autoScroll: false,
    );
  }

  Future<void> _completeTutorAyah({
    required int globalAyah,
    required MemorizationSession session,
  }) async {
    final quranCubit = context.read<QuranCubit>();
    final memorizationCubit = context.read<QuranMemorizationCubit>();
    await quranCubit.stopAudio();
    await memorizationCubit.recordReviewOutcome(
      globalAyah: globalAyah,
      outcome: ReviewOutcome.good,
      sessionId: session.id,
    );
    if (!mounted) return;

    final nextAyah = memorizationCubit.state.activeSession?.currentGlobalAyah;
    if (nextAyah != null) {
      memorizationCubit.revealText();
      _startTutorPlayback(nextAyah);
    }
  }

  Future<void> _confirmExit() async {
    final cubit = context.read<QuranMemorizationCubit>();
    final session = cubit.state.activeSession;

    if (session == null || session.isFinished) {
      if (widget.startWithAudio) {
        await context.read<QuranCubit>().stopAudio();
      }
      cubit.endSession();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنهاء جلسة الحفظ'),
        content: const Text(
          'هل تريد إنهاء الجلسة الآن؟ يتم حفظ تقدمك والآيات التي راجعتها تلقائيًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('متابعة الجلسة'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: ctx.mishkat.error),
            child: const Text('إنهاء وحفظ'),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      if (widget.startWithAudio) {
        await context.read<QuranCubit>().stopAudio();
        if (!mounted) return;
      }
      cubit.endSession();
      Navigator.of(context).pop();
    }
  }

  Future<void> _openTafsir(int globalAyah) async {
    final layoutRepo = MushafLayoutRepository.instance;
    if (!layoutRepo.isLoaded) {
      await layoutRepo.load();
    }
    final bounds = layoutRepo.getAyah(globalAyah);
    if (bounds != null && mounted) {
      await TafsirKnowledgeSheet.show(
        context: context,
        ayah: bounds,
        quranData: widget.quranData,
      );
    }
  }

  Future<void> _openInMushaf(int globalAyah) async {
    final page = widget.quranData.pageForGlobal(globalAyah);
    final point = widget.quranData.pointForGlobal(globalAyah);
    await context.read<QuranCubit>().openPage(page, point: point);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuranReaderPage(initialGlobalAyah: globalAyah),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final theme = Theme.of(context);

    return BlocBuilder<QuranMemorizationCubit, QuranMemorizationState>(
      builder: (context, memState) {
        final session = memState.activeSession;

        if (session == null || session.queue.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('جلسة الحفظ والمراجعة'),
              centerTitle: true,
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 64,
                    color: colors.primary,
                  ),
                  const SizedBox(height: MishkatSpacing.md),
                  const Text(
                    'لا توجد جلسة نشطة حالياً',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: MishkatSpacing.sm),
                  Text(
                    'اختر خطة أو ابدأ مراجعة من لوحة الحفظ.',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                  const SizedBox(height: MishkatSpacing.xl),
                  MishkatPrimaryAction(
                    onPressed: () => Navigator.of(context).pop(),
                    label: 'العودة للوحة الحفظ',
                  ),
                ],
              ),
            ),
          );
        }

        if (session.isFinished) {
          if (widget.startWithAudio) {
            return _buildTutorFinishedView(context, session);
          }
          return _buildFinishedView(context, memState, session);
        }

        final globalAyah = session.currentGlobalAyah;
        if (globalAyah == null) {
          if (widget.startWithAudio) {
            return _buildTutorFinishedView(context, session);
          }
          return _buildFinishedView(context, memState, session);
        }
        final point = widget.quranData.pointForGlobal(globalAyah);
        final chapter = widget.quranData.chapter(point.surah);
        final ayahIndex = (point.ayah - 1).clamp(0, chapter.ayahs.length - 1);
        final ayahText = chapter.ayahs.isNotEmpty
            ? chapter.ayahs[ayahIndex]
            : '';
        final pageNumber = widget.quranData.pageForGlobal(globalAyah);
        final item = memState.getItem(globalAyah);

        if (widget.startWithAudio) {
          return _buildTutorView(
            context: context,
            session: session,
            globalAyah: globalAyah,
            chapter: chapter,
            point: point,
            ayahText: ayahText,
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'إنهاء الجلسة',
              onPressed: _confirmExit,
            ),
            title: Column(
              children: [
                Text(
                  session.sessionType == MemorizationSessionType.revision
                      ? 'جلسة مراجعة وتثبيت'
                      : 'جلسة حفظ الورد',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'الآية ${session.currentIndex + 1} من ${session.queue.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: LinearProgressIndicator(
                value: session.progress,
                backgroundColor: colors.border.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: MishkatSpacing.page,
              children: [
                // Context Card: Surah, Ayah, Page, and Status Badge
                MishkatCard(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.menu_book_rounded,
                          color: colors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: MishkatSpacing.md),
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
                              'الآية ${point.ayah} · صفحة $pageNumber · الجزء ${((pageNumber - 1) ~/ 20) + 1}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusChip(status: item.status),
                    ],
                  ),
                ),
                const SizedBox(height: MishkatSpacing.lg),

                // Quran Text Recall Card
                _buildRecallCard(
                  context: context,
                  session: session,
                  ayahText: ayahText,
                  point: point,
                ),
                const SizedBox(height: MishkatSpacing.base),

                // Companion Action Tools (Listen, Tafsir, Mushaf, Bookmark)
                _buildCompanionTools(context: context, globalAyah: globalAyah),
                const SizedBox(height: MishkatSpacing.xl),

                // Self-Assessment Heading
                Text(
                  'تقييم الحفظ لهذه الآية',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: MishkatSpacing.sm),

                // 4-Level Self-Assessment Outcome Evaluation
                Column(
                  children: [
                    // Upper Row: Success Outcomes (Easy & Good)
                    Row(
                      children: [
                        // Easy Button
                        Expanded(
                          child: Material(
                            color: colors.primarySoft,
                            borderRadius: BorderRadius.circular(
                              MishkatRadius.md,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                MishkatRadius.md,
                              ),
                              onTap: () {
                                context
                                    .read<QuranMemorizationCubit>()
                                    .recordReviewOutcome(
                                      globalAyah: globalAyah,
                                      outcome: ReviewOutcome.easy,
                                      sessionId: session.id,
                                    );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.sentiment_very_satisfied_rounded,
                                      color: colors.primary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'سهل',
                                      style: TextStyle(
                                        color: colors.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: MishkatSpacing.sm),

                        // Good / Knows Button
                        Expanded(
                          child: Material(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(
                              MishkatRadius.md,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                MishkatRadius.md,
                              ),
                              onTap: () {
                                context
                                    .read<QuranMemorizationCubit>()
                                    .recordReviewOutcome(
                                      globalAyah: globalAyah,
                                      outcome: ReviewOutcome.good,
                                      sessionId: session.id,
                                    );
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'أعرفها ومحفوظة',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MishkatSpacing.sm),

                    // Lower Row: Review Needed Outcomes (Difficult & Failed)
                    Row(
                      children: [
                        // Difficult / Needs Revision Button
                        Expanded(
                          child: Material(
                            color: colors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                              MishkatRadius.md,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                MishkatRadius.md,
                              ),
                              onTap: () {
                                context
                                    .read<QuranMemorizationCubit>()
                                    .recordReviewOutcome(
                                      globalAyah: globalAyah,
                                      outcome: ReviewOutcome.difficult,
                                      sessionId: session.id,
                                    );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.replay_rounded,
                                      color: colors.warning,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'أحتاج مراجعة',
                                      style: TextStyle(
                                        color: colors.warning,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: MishkatSpacing.sm),

                        // Failed Button
                        Expanded(
                          child: Material(
                            color: colors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              MishkatRadius.md,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                MishkatRadius.md,
                              ),
                              onTap: () {
                                context
                                    .read<QuranMemorizationCubit>()
                                    .recordReviewOutcome(
                                      globalAyah: globalAyah,
                                      outcome: ReviewOutcome.failed,
                                      sessionId: session.id,
                                    );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.close_rounded,
                                      color: colors.error,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'لم أتذكر',
                                      style: TextStyle(
                                        color: colors.error,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: MishkatSpacing.base),

                // Navigation Row: Previous & Skip
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (session.currentIndex > 0)
                      TextButton.icon(
                        onPressed: () {
                          context
                              .read<QuranMemorizationCubit>()
                              .previousSessionAyah();
                        },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('الآية السابقة'),
                      )
                    else
                      const SizedBox.shrink(),
                    if (session.currentIndex < session.queue.length - 1)
                      TextButton.icon(
                        onPressed: () {
                          context
                              .read<QuranMemorizationCubit>()
                              .advanceSession();
                        },
                        icon: const Icon(Icons.skip_next_rounded, size: 18),
                        label: const Text('تخطي للآية التالية'),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTutorView({
    required BuildContext context,
    required MemorizationSession session,
    required int globalAyah,
    required QuranChapter chapter,
    required QuranPoint point,
    required String ayahText,
  }) {
    final colors = context.mishkat;
    final theme = Theme.of(context);
    final isLastAyah = session.currentIndex == session.queue.length - 1;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'إنهاء الجلسة',
          onPressed: _confirmExit,
        ),
        title: Column(
          children: [
            Text(
              'جلسة حفظ الورد',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'الآية ${session.currentIndex + 1} من ${session.queue.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: session.progress,
            backgroundColor: colors.border.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              'سورة ${chapter.name} · الآية ${point.ayah}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: MishkatSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: MishkatRadius.brMd,
              ),
              child: Row(
                children: [
                  _TutorStepNumber(number: '1', color: colors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'استمع للآية',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  _TutorStepNumber(number: '2', color: colors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'ردّد في وقت الصمت',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MishkatSpacing.base),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: MishkatRadius.brXl,
                border: Border.all(color: colors.borderSubtle),
                boxShadow: MishkatShadows.subtle(context),
              ),
              child: Column(
                children: [
                  Text(
                    ayahText,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontFamily: 'Amiri',
                      fontSize: 25,
                      height: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: MishkatSpacing.sm),
                  Text(
                    '﴿ ${point.ayah} ﴾',
                    style: TextStyle(
                      fontFamily: 'Amiri',
                      color: colors.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MishkatSpacing.base),
            _buildTutorPlaybackControl(
              context: context,
              globalAyah: globalAyah,
            ),
            const SizedBox(height: MishkatSpacing.xl),
            MishkatPrimaryAction(
              onPressed: () =>
                  _completeTutorAyah(globalAyah: globalAyah, session: session),
              label: isLastAyah
                  ? 'أتقنتها، إنهاء الجلسة'
                  : 'أتقنتها، الآية التالية',
              icon: const Icon(Icons.check_rounded),
              isFullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            ),
            const SizedBox(height: MishkatSpacing.sm),
            MishkatSecondaryAction(
              onPressed: () => _startTutorPlayback(globalAyah),
              label: 'أعد التلقين',
              icon: const Icon(Icons.replay_rounded),
              isFullWidth: true,
            ),
            const SizedBox(height: MishkatSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _openSessionRepeatSettings(context),
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  label: const Text('الإعدادات'),
                ),
                TextButton.icon(
                  onPressed: () => _openInMushaf(globalAyah),
                  icon: const Icon(Icons.auto_stories_outlined, size: 17),
                  label: const Text('فتح المصحف'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTutorPlaybackControl({
    required BuildContext context,
    required int globalAyah,
  }) {
    final colors = context.mishkat;
    return BlocBuilder<QuranCubit, QuranState>(
      builder: (context, quranState) {
        final repeat = quranState.repeatState;
        final ownsCurrentAyah =
            quranState.audioGlobalAyah == globalAyah ||
            (repeat.currentAyah == globalAyah && repeat.isActive);
        final isLoading =
            ownsCurrentAyah &&
            quranState.audioStatus == QuranAudioStatus.loading;
        final isActive = ownsCurrentAyah && repeat.isActive;
        final isPaused = isActive && repeat.isPaused;
        final isDelaying = isActive && repeat.isDelaying;

        final String title;
        final String subtitle;
        if (isLoading) {
          title = 'جارٍ تحضير التلاوة...';
          subtitle = 'ستبدأ خلال لحظة';
        } else if (isDelaying) {
          title = 'ردّد الآن';
          subtitle = '${repeat.remainingDelaySeconds} ثوانٍ قبل التكرار';
        } else if (isPaused) {
          title = 'متوقف مؤقتًا';
          subtitle = 'اضغط للمتابعة';
        } else if (isActive) {
          title = 'استمع الآن';
          subtitle =
              'المرة ${repeat.currentAyahRepeat} من $_sessionRepeatCount';
        } else if (quranState.audioStatus == QuranAudioStatus.failure) {
          title = 'تعذر التشغيل';
          subtitle = 'اضغط للمحاولة مرة أخرى';
        } else {
          title = 'استمع وردّد';
          subtitle =
              '$_sessionRepeatCount مرات · $_sessionDelaySeconds ثوانٍ للترديد';
        }

        return Material(
          color: isDelaying ? colors.primarySoft : colors.surfaceVariant,
          borderRadius: MishkatRadius.brLg,
          child: InkWell(
            borderRadius: MishkatRadius.brLg,
            onTap: isLoading
                ? null
                : () {
                    if (isActive) {
                      context.read<QuranCubit>().toggleAudio(continuous: false);
                    } else {
                      _startTutorPlayback(globalAyah);
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            isActive && !isPaused
                                ? Icons.pause_rounded
                                : isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
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
      },
    );
  }

  Widget _buildRecallCard({
    required BuildContext context,
    required MemorizationSession session,
    required String ayahText,
    required QuranPoint point,
  }) {
    final colors = context.mishkat;
    final cubit = context.read<QuranMemorizationCubit>();

    if (session.isTextHidden) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        decoration: BoxDecoration(
          color: colors.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(MishkatRadius.xl),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.15),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.visibility_off_outlined,
              size: 48,
              color: colors.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: MishkatSpacing.md),
            const Text(
              'استحضر الآية الكريمة غيباً',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'اقرأ الآية من حفظك، ثم اضغط لإظهار النص والتأكد من صحتها.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: MishkatSpacing.xl),
            MishkatPrimaryAction(
              onPressed: () => cubit.revealText(),
              label: 'إظهار نص الآية للتأكد',
              icon: const Icon(Icons.visibility_rounded),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(MishkatRadius.xl),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(MishkatRadius.sm),
                ),
                child: Text(
                  'نص الآية الكريمة',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colors.primary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.visibility_off_rounded, size: 20),
                tooltip: 'إخفاء النص للتدرب ثانية',
                onPressed: () => cubit.toggleTextHidden(),
              ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.md),
          Text(
            ayahText,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontFamily: 'Amiri',
              fontSize: 24,
              height: 2.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: MishkatSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: colors.gold.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(MishkatRadius.pill),
            ),
            child: Text(
              '﴿ ${point.ayah} ﴾',
              style: TextStyle(
                fontFamily: 'Amiri',
                fontWeight: FontWeight.bold,
                color: colors.gold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanionTools({
    required BuildContext context,
    required int globalAyah,
  }) {
    final colors = context.mishkat;

    return BlocBuilder<QuranCubit, QuranState>(
      builder: (context, quranState) {
        final isPlaying =
            quranState.audioStatus == QuranAudioStatus.playing &&
            quranState.audioGlobalAyah == globalAyah;
        final isBookmarked = quranState.isAyahBookmarked(globalAyah);

        return Row(
          children: [
            // Play Audio
            Expanded(
              child: Material(
                color: isPlaying ? colors.primary : colors.surfaceVariant,
                borderRadius: BorderRadius.circular(MishkatRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(MishkatRadius.md),
                  onTap: () {
                    final cubit = context.read<QuranCubit>();
                    if (isPlaying) {
                      if (quranState.repeatState.isDelaying) {
                        cubit.skipDelay();
                      } else {
                        cubit.toggleAudio(continuous: false);
                      }
                    } else {
                      final config = AudioRepeatConfig(
                        mode: AudioRepeatMode.singleAyah,
                        startGlobalAyah: globalAyah,
                        endGlobalAyah: globalAyah,
                        ayahRepeatCount: _sessionRepeatCount,
                        delaySeconds: _sessionDelaySeconds,
                      );
                      cubit.startRepeatPlayback(
                        config,
                        initialGlobalAyah: globalAyah,
                      );
                    }
                  },
                  onLongPress: () => _openSessionRepeatSettings(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.volume_up_rounded,
                          color: isPlaying ? Colors.white : colors.primary,
                          size: 20,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPlaying
                              ? (quranState.repeatState.isDelaying
                                    ? 'ترديد (${quranState.repeatState.remainingDelaySeconds}ث)'
                                    : 'تكرار ${quranState.repeatState.currentAyahRepeat}/$_sessionRepeatCount')
                              : 'استماع ($_sessionRepeatCount×)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPlaying
                                ? Colors.white
                                : colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Tafsir
            Expanded(
              child: Material(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(MishkatRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(MishkatRadius.md),
                  onTap: () => _openTafsir(globalAyah),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          color: colors.primary,
                          size: 20,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'التفسير',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Open in Mushaf
            Expanded(
              child: Material(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(MishkatRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(MishkatRadius.md),
                  onTap: () => _openInMushaf(globalAyah),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_stories_outlined,
                          color: colors.primary,
                          size: 20,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'في المصحف',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Bookmark for retention
            Expanded(
              child: Material(
                color: isBookmarked
                    ? colors.primarySoft
                    : colors.surfaceVariant,
                borderRadius: BorderRadius.circular(MishkatRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(MishkatRadius.md),
                  onTap: () {
                    context.read<QuranCubit>().toggleAyahBookmark(
                      globalAyah,
                      label: 'آية تحتاج تثبيت',
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isBookmarked
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: isBookmarked
                              ? colors.primary
                              : colors.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isBookmarked ? 'محفوظة' : 'علامة',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isBookmarked
                                ? colors.primary
                                : colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openSessionRepeatSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final theme = Theme.of(ctx);
            return Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'إعدادات التلقين',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'اختر ما يناسبك، ثم ابدأ الآية من جديد.',
                        style: TextStyle(
                          color: ctx.mishkat.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'كم مرة تُقرأ الآية؟',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [1, 2, 3, 5, 7, 10].map((count) {
                          return ChoiceChip(
                            label: Text('$count'),
                            selected: _sessionRepeatCount == count,
                            onSelected: (_) {
                              setState(() => _sessionRepeatCount = count);
                              setSheetState(() {});
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'وقت الترديد بعدها',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [0, 2, 3, 5, 7, 10].map((seconds) {
                          return ChoiceChip(
                            label: Text(
                              seconds == 0 ? 'بدون' : '$seconds ثوانٍ',
                            ),
                            selected: _sessionDelaySeconds == seconds,
                            onSelected: (_) {
                              setState(() => _sessionDelaySeconds = seconds);
                              setSheetState(() {});
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      MishkatPrimaryAction(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          final ayah = context
                              .read<QuranMemorizationCubit>()
                              .state
                              .activeSession
                              ?.currentGlobalAyah;
                          if (widget.startWithAudio && ayah != null) {
                            _startTutorPlayback(ayah);
                          }
                        },
                        label: 'تطبيق والبدء من جديد',
                        icon: const Icon(Icons.play_arrow_rounded),
                        isFullWidth: true,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTutorFinishedView(
    BuildContext context,
    MemorizationSession session,
  ) {
    final colors = context.mishkat;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('اكتمل الورد'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                child: Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 48,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(height: MishkatSpacing.xl),
              Text(
                'أتممت وردك',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: MishkatSpacing.sm),
              Text(
                'لقّنت ${session.completedCount} آيات اليوم. بارك الله في حفظك.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: MishkatSpacing.xxl),
              MishkatPrimaryAction(
                onPressed: () {
                  context.read<QuranMemorizationCubit>().endSession();
                  Navigator.of(context).pop();
                },
                label: 'العودة للحفظ',
                icon: const Icon(Icons.arrow_back_rounded),
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinishedView(
    BuildContext context,
    QuranMemorizationState state,
    MemorizationSession session,
  ) {
    final colors = context.mishkat;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('اكتملت الجلسة'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: MishkatSpacing.page,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.stars_rounded, size: 80, color: colors.gold),
              const SizedBox(height: MishkatSpacing.lg),
              Text(
                'تم إكمال الجلسة بنجاح!',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: MishkatSpacing.xs),
              Text(
                'تقبّل الله منك وثبّت القرآن العظيم في قلبك وذاكرتك.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: MishkatSpacing.xl),
              MishkatCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          '${session.completedCount}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'الآيات المراجعة',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 36, color: colors.border),
                    Column(
                      children: [
                        Text(
                          '${state.totalMemorizedCount}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إجمالي المحفوظ',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 36, color: colors.border),
                    Column(
                      children: [
                        Text(
                          '${state.totalNeedsRevisionCount}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: colors.warning,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'تحتاج تثبيت',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MishkatSpacing.xxl),
              MishkatPrimaryAction(
                onPressed: () {
                  context.read<QuranMemorizationCubit>().endSession();
                  Navigator.of(context).pop();
                },
                label: 'العودة إلى لوحة الحفظ',
                icon: const Icon(Icons.arrow_back_rounded),
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TutorStepNumber extends StatelessWidget {
  const _TutorStepNumber({required this.number, required this.color});

  final String number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        number,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final MemorizationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;

    Color bg;
    Color fg;
    switch (status) {
      case MemorizationStatus.memorized:
        bg = colors.primarySoft;
        fg = colors.primary;
      case MemorizationStatus.learning:
        bg = colors.surfaceVariant;
        fg = colors.textPrimary;
      case MemorizationStatus.needsRevision:
        bg = colors.warning.withValues(alpha: 0.15);
        fg = colors.warning;
      case MemorizationStatus.notStarted:
        bg = colors.border.withValues(alpha: 0.3);
        fg = colors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MishkatRadius.pill),
      ),
      child: Text(
        status.arabicLabel,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
