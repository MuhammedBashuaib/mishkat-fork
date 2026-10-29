import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../data/models/hifz_planning_models.dart';
import '../../data/models/memorization_plan.dart';
import '../../data/models/murajaah_models.dart';
import '../../data/models/quran_models.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_memorization_cubit.dart';
import '../cubit/quran_memorization_state.dart';
import '../widgets/oral_recitation_info_sheet.dart';
import 'memorization_plan_page.dart';
import 'memorization_session_page.dart';
import 'quran_memorization_analytics_page.dart';
import 'quran_reader_page.dart';

/// Task-first Hifz home: today's work, practice, then progress.
class QuranMemorizationPage extends StatelessWidget {
  const QuranMemorizationPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const QuranMemorizationPage());

  @override
  Widget build(BuildContext context) {
    final quranData = context.watch<QuranCubit>().state.data;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الحفظ والمراجعة',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          if (quranData != null)
            IconButton(
              tooltip: 'تحليلات الحفظ والمراجعة',
              icon: const Icon(Icons.insights_outlined),
              onPressed: () => Navigator.of(context).push(
                QuranMemorizationAnalyticsPage.route(quranData: quranData),
              ),
            ),
        ],
      ),
      body: quranData == null
          ? const Center(child: CircularProgressIndicator())
          : BlocBuilder<QuranMemorizationCubit, QuranMemorizationState>(
              builder: (context, state) {
                if (state.status == QuranMemorizationStatus.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.status == QuranMemorizationStatus.failure) {
                  return _FailureView(message: state.error);
                }
                final plan = state.activePlan;
                final journey = state.calculateDailyJourney();
                return ListView(
                  padding: MishkatSpacing.page,
                  children: [
                    _WelcomeLine(hasPlan: plan != null),
                    const SizedBox(height: MishkatSpacing.base),
                    if (plan == null)
                      _EmptyPlanCard(
                        onCreate: () => _openPlan(context, quranData),
                        onOralRecitation: () =>
                            _showFreeRecitationSetup(context, quranData),
                      )
                    else
                      _TodayCard(
                        state: state,
                        journey: journey,
                        plan: plan,
                        quranData: quranData,
                      ),
                    if (plan == null && journey.isRecoveryMode) ...[
                      const SizedBox(height: MishkatSpacing.sm),
                      _RecoveryNotice(backlog: journey.recoveryBacklogCount),
                    ],
                    const MishkatSectionHeader(title: 'اختر طريقة التدريب'),
                    if (plan != null) ...[
                      _TrainingPlanSelector(
                        plan: plan,
                        quranData: quranData,
                        canSwitch:
                            state.plans
                                .where((item) => !item.isCompleted)
                                .length >
                            1,
                        onTap: () =>
                            _showPlanSwitcher(context, state, quranData),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _PracticeMethods(state: state, quranData: quranData),
                    MishkatSectionHeader(
                      title: 'خططي',
                      trailing: MishkatTextAction(
                        label: 'خطة جديدة',
                        icon: Icons.add_rounded,
                        onPressed: () => _openPlan(context, quranData),
                      ),
                    ),
                    _PlansPanel(state: state, quranData: quranData),
                    const MishkatSectionHeader(title: 'التقدم'),
                    _ProgressSummary(
                      state: state,
                      onAnalytics: () => Navigator.of(context).push(
                        QuranMemorizationAnalyticsPage.route(
                          quranData: quranData,
                        ),
                      ),
                    ),
                    const SizedBox(height: MishkatSpacing.lg),
                    _RevisionDetails(state: state, quranData: quranData),
                  ],
                );
              },
            ),
    );
  }

  static void _openPlan(
    BuildContext context,
    QuranData quranData, {
    MemorizationPlan? plan,
  }) {
    Navigator.of(context).push(
      MemorizationPlanPage.route(quranData: quranData, existingPlan: plan),
    );
  }
}

class _WelcomeLine extends StatelessWidget {
  const _WelcomeLine({required this.hasPlan});
  final bool hasPlan;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        hasPlan ? 'ورد واحد واضح كل يوم' : 'ابدأ بخطة تناسب وقتك',
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.3),
      ),
      const SizedBox(height: 4),
      Text(
        hasPlan
            ? 'احفظ، لقّن، ثم اختبر نفسك دون تشتيت.'
            : 'هدف صغير ثابت، ثم تلقين وتسميع ومراجعة في مكان واحد.',
        style: TextStyle(color: context.mishkat.textSecondary, height: 1.45),
      ),
    ],
  );
}

class _EmptyPlanCard extends StatelessWidget {
  const _EmptyPlanCard({
    required this.onCreate,
    required this.onOralRecitation,
  });
  final VoidCallback onCreate;
  final VoidCallback onOralRecitation;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return MishkatCard(
      color: colors.primarySoft.withValues(alpha: .5),
      borderColor: colors.primary.withValues(alpha: .2),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: MishkatRadius.brLg,
            ),
            child: const Icon(
              Icons.route_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'أنشئ مسارك الأول',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'اختر السورة ومقداراً يومياً مثل 5 آيات أو صفحة، وسنرتب لك الحفظ والمراجعة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, height: 1.55),
          ),
          const SizedBox(height: 18),
          MishkatPrimaryAction(
            label: 'إنشاء خطة حفظ',
            icon: const Icon(Icons.add_rounded),
            isFullWidth: true,
            onPressed: onCreate,
          ),
          const SizedBox(height: 8),
          MishkatTextAction(
            label: 'أو ابدأ تسميعاً حراً',
            icon: Icons.mic_none_rounded,
            onPressed: onOralRecitation,
          ),
        ],
      ),
    );
  }
}

class _RecoveryNotice extends StatelessWidget {
  const _RecoveryNotice({required this.backlog});
  final int backlog;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.accentGoldSoft,
        borderRadius: MishkatRadius.brMd,
      ),
      child: Row(
        children: [
          Icon(Icons.spa_outlined, color: colors.gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'وضع التعويض الهادئ',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$backlog آية تنتظر مراجعة لطيفة',
                  style: TextStyle(color: colors.textSecondary, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.state,
    required this.journey,
    required this.plan,
    required this.quranData,
  });
  final QuranMemorizationState state;
  final DailyHifzJourney journey;
  final MemorizationPlan plan;
  final QuranData quranData;

  @override
  Widget build(BuildContext context) {
    final progress = state.planProgress(plan);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardTop = isDark ? const Color(0xFF18312A) : const Color(0xFF2D6256);
    final cardBottom = isDark
        ? const Color(0xFF0D1D19)
        : const Color(0xFF1C453C);
    final actionBackground = isDark
        ? const Color(0xFF9AD8C0)
        : const Color(0xFFF4F7F2);
    const actionForeground = Color(0xFF163C33);

    return Container(
      decoration: BoxDecoration(
        borderRadius: MishkatRadius.brXl,
        boxShadow: MishkatShadows.elevated(context),
      ),
      child: ClipRRect(
        borderRadius: MishkatRadius.brXl,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [cardTop, cardBottom],
            ),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF41685C)
                  : Colors.white.withValues(alpha: .12),
            ),
            borderRadius: MishkatRadius.brXl,
          ),
          child: Stack(
            children: [
              PositionedDirectional(
                top: -58,
                end: -46,
                child: Container(
                  width: 154,
                  height: 154,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFDDBE72).withValues(alpha: .11),
                      width: 18,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.auto_awesome_rounded,
                                    color: Color(0xFFE5C679),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    'وردك اليومي المقترح',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: .72,
                                      ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                plan.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .08),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFE5C679)
                                  .withValues(alpha: .42),
                            ),
                          ),
                          child: Text(
                            '${(progress.percentage * 100).round()}٪',
                            style: const TextStyle(
                              color: Color(0xFFF4D891),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (journey.isRecoveryMode) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5C679).withValues(alpha: .12),
                          borderRadius: MishkatRadius.brPill,
                        ),
                        child: const Text(
                          'وضع التعويض الهادئ',
                          style: TextStyle(
                            color: Color(0xFFF0D690),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        for (
                          var index = 0;
                          index < journey.segments.length;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(width: 7),
                          Expanded(
                            child: _SegmentStat(
                              segment: journey.segments[index],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    MishkatPrimaryAction(
                      label: journey.isEmpty
                          ? 'أتممت ورد اليوم'
                          : 'ابدأ ورد اليوم المتكامل (${journey.totalAyahs} آية)',
                      icon: Icon(
                        journey.isEmpty
                            ? Icons.done_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      isFullWidth: true,
                      backgroundColor: actionBackground,
                      foregroundColor: actionForeground,
                      disabledBackgroundColor: Colors.white.withValues(
                        alpha: .08,
                      ),
                      disabledForegroundColor: Colors.white.withValues(
                        alpha: .46,
                      ),
                      onPressed: journey.isEmpty
                          ? null
                          : () => _showPracticeModeSheet(
                              context,
                              title: 'ورد اليوم المتكامل',
                              queue: journey.allAyahs,
                              quranData: quranData,
                              planId: plan.id,
                              startTraditional: () => context
                                  .read<QuranMemorizationCubit>()
                                  .startDailyJourneySession(journey: journey),
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

class _SegmentStat extends StatelessWidget {
  const _SegmentStat({required this.segment});
  final HifzJourneySegment segment;

  IconData get _icon => switch (segment.type) {
    HifzJourneySegmentType.dueMurajaah => Icons.history_rounded,
    HifzJourneySegmentType.weakConsolidation => Icons.shield_outlined,
    HifzJourneySegmentType.newHifz => Icons.menu_book_rounded,
  };

  Color get _accent => switch (segment.type) {
    HifzJourneySegmentType.dueMurajaah => const Color(0xFF9BD5C0),
    HifzJourneySegmentType.weakConsolidation => const Color(0xFFE7C878),
    HifzJourneySegmentType.newHifz => const Color(0xFFB5C8EC),
  };

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${segment.title}: ${segment.count}',
    child: Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .065),
        borderRadius: MishkatRadius.brMd,
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_icon, color: _accent, size: 15),
              const SizedBox(width: 5),
              Text(
                '${segment.count}',
                style: TextStyle(
                  color: _accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            segment.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .72),
              fontSize: 9.5,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TrainingPlanSelector extends StatelessWidget {
  const _TrainingPlanSelector({
    required this.plan,
    required this.quranData,
    required this.canSwitch,
    required this.onTap,
  });

  final MemorizationPlan plan;
  final QuranData quranData;
  final bool canSwitch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Material(
      color: colors.primarySoft.withValues(alpha: .55),
      borderRadius: MishkatRadius.brMd,
      child: InkWell(
        onTap: canSwitch ? onTap : null,
        borderRadius: MishkatRadius.brMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.bookmark_added_outlined,
                  color: colors.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'التدريب الآن على: ${plan.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _planRangeLabel(plan, quranData),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (canSwitch) ...[
                const SizedBox(width: 8),
                Text(
                  'تبديل',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more_rounded,
                  color: colors.primary,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeMethods extends StatelessWidget {
  const _PracticeMethods({required this.state, required this.quranData});
  final QuranMemorizationState state;
  final QuranData quranData;

  @override
  Widget build(BuildContext context) {
    final plan = state.activePlan;
    return Column(
      children: [
        _MethodTile(
          icon: Icons.headphones_rounded,
          title: 'التلقين والتكرار',
          subtitle: 'استمع للآية وردّدها، خطوة بخطوة.',
          onTap: plan == null
              ? () => _showNeedPlan(context)
              : () => _showTutorSetup(context, plan, quranData),
        ),
        const SizedBox(height: 10),
        _MethodTile(
          icon: Icons.mic_rounded,
          title: 'التسميع الذكي',
          subtitle: 'سمّع من خطتك الحالية أو اختر سورة ونطاقاً حراً.',
          badge: 'استماع مباشر',
          onTap: () => _showOralRecitationSourceSheet(
            context,
            plan: plan,
            quranData: quranData,
          ),
        ),
        const SizedBox(height: 10),
        _MethodTile(
          icon: Icons.menu_book_rounded,
          title: 'التسميع البصري',
          subtitle: 'التسميع والاستحضار البصري في المصحف',
          onTap: plan == null
              ? () => _showNeedPlan(context)
              : () {
                  final queue = state.todayTargetAyahs(plan);
                  if (queue.isEmpty) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => QuranReaderPage(
                        initialGlobalAyah: queue.first,
                        visualRecallInitialQueue: queue,
                        visualRecallPlanId: plan.id,
                      ),
                    ),
                  );
                },
        ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return MishkatCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: MishkatRadius.brMd,
            ),
            child: Icon(icon, color: colors.primary, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primarySoft,
                          borderRadius: MishkatRadius.brPill,
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded, color: colors.textMuted),
        ],
      ),
    );
  }
}

class _PlansPanel extends StatelessWidget {
  const _PlansPanel({required this.state, required this.quranData});
  final QuranMemorizationState state;
  final QuranData quranData;

  @override
  Widget build(BuildContext context) {
    if (state.plans.isEmpty) {
      return MishkatCard(
        padding: const EdgeInsets.all(14),
        child: Text(
          'لا توجد خطط بعد. أنشئ خطة واحدة واضحة وابدأ بخطوة صغيرة.',
          style: TextStyle(color: context.mishkat.textSecondary, height: 1.5),
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < state.plans.length; index++) ...[
          _PlanTile(
            plan: state.plans[index],
            state: state,
            quranData: quranData,
          ),
          if (index != state.plans.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.state,
    required this.quranData,
  });
  final MemorizationPlan plan;
  final QuranMemorizationState state;
  final QuranData quranData;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final progress = state.planProgress(plan);
    return MishkatCard(
      onTap: !plan.isCompleted && !plan.isActive
          ? () => context.read<QuranMemorizationCubit>().resumePlan(plan.id)
          : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      borderColor: plan.isActive
          ? colors.primary.withValues(alpha: .35)
          : colors.border,
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress.percentage,
                  strokeWidth: 4,
                  backgroundColor: colors.surfaceVariant,
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                ),
                Text(
                  '${(progress.percentage * 100).round()}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        plan.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (plan.isActive) ...[
                      const SizedBox(width: 6),
                      Text(
                        'مستخدمة الآن',
                        style: TextStyle(
                          color: colors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${plan.dailyTarget} آيات يومياً · ${progress.remaining} متبقية',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'خيارات الخطة',
            onSelected: (value) async {
              final cubit = context.read<QuranMemorizationCubit>();
              if (value == 'edit') {
                QuranMemorizationPage._openPlan(context, quranData, plan: plan);
              } else if (value == 'activate') {
                await cubit.resumePlan(plan.id);
              } else if (value == 'pause') {
                await cubit.pausePlan(plan.id);
              } else if (value == 'delete') {
                final approved = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('حذف الخطة؟'),
                    content: const Text(
                      'سيتم حذف الخطة فقط، مع إبقاء سجل الحفظ والمراجعة.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('إلغاء'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('حذف'),
                      ),
                    ],
                  ),
                );
                if (approved == true) await cubit.deletePlan(plan.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('تعديل الخطة')),
              PopupMenuItem(
                value: plan.isActive ? 'pause' : 'activate',
                child: Text(plan.isActive ? 'إيقاف مؤقت' : 'تفعيل الخطة'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('حذف الخطة')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.state, required this.onAnalytics});
  final QuranMemorizationState state;
  final VoidCallback onAnalytics;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return MishkatCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'إحصائيات الحفظ الكلية',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              MishkatTextAction(
                label: 'التفاصيل',
                icon: Icons.arrow_back_rounded,
                onPressed: onAnalytics,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Metric(
                label: 'المحفوظ',
                value: state.totalMemorizedCount,
                color: colors.success,
              ),
              _Metric(
                label: 'قيد الحفظ',
                value: state.totalLearningCount,
                color: colors.gold,
              ),
              _Metric(
                label: 'تحتاج مراجعة',
                value: state.totalNeedsRevisionCount,
                color: colors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.mishkat.textSecondary),
        ),
      ],
    ),
  );
}

class _RevisionDetails extends StatelessWidget {
  const _RevisionDetails({required this.state, required this.quranData});
  final QuranMemorizationState state;
  final QuranData quranData;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final suggestedCount = state
        .generateAdaptiveQueue(
          category: AdaptiveMurajaahCategory.all,
          limit: 20,
        )
        .length;
    return MishkatCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.refresh_rounded, color: colors.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'المراجعة الذكية والتثبيت',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'يرتّب لك التطبيق الآيات التي تحتاجها الآن اعتماداً على موعد آخر مراجعة وأخطائك السابقة.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          MishkatPrimaryAction(
            label: suggestedCount == 0
                ? 'لا توجد مراجعة مستحقة الآن'
                : 'ابدأ المراجعة المقترحة · $suggestedCount آية',
            icon: Icon(
              suggestedCount == 0
                  ? Icons.check_circle_outline_rounded
                  : Icons.play_arrow_rounded,
            ),
            isFullWidth: true,
            onPressed: suggestedCount == 0
                ? null
                : () => _startRevision(
                    context,
                    quranData,
                    AdaptiveMurajaahCategory.all,
                  ),
          ),
          const SizedBox(height: 8),
          MishkatSecondaryAction(
            label: 'اختيار نوع المراجعة',
            icon: const Icon(Icons.tune_rounded),
            isFullWidth: true,
            onPressed: () => _showReviewTypesSheet(
              context,
              state: state,
              quranData: quranData,
            ),
          ),
        ],
      ),
    );
  }
}

void _showReviewTypesSheet(
  BuildContext context, {
  required QuranMemorizationState state,
  required QuranData quranData,
}) {
  final options =
      <
        ({
          AdaptiveMurajaahCategory category,
          IconData icon,
          String description,
          int count,
        })
      >[
        (
          category: AdaptiveMurajaahCategory.dueToday,
          icon: Icons.today_outlined,
          description: 'حان موعدها اليوم حسب جدول مراجعتك.',
          count: state.dueTodayAyahs().length,
        ),
        (
          category: AdaptiveMurajaahCategory.overdue,
          icon: Icons.history_rounded,
          description: 'فات موعدها وتحتاج أن تبدأ بها أولاً.',
          count: state.overdueAyahs().length,
        ),
        (
          category: AdaptiveMurajaahCategory.weak,
          icon: Icons.build_circle_outlined,
          description: 'تكررت فيها الأخطاء أو تحتاج تثبيتاً.',
          count: state.weakAyahs().length,
        ),
        (
          category: AdaptiveMurajaahCategory.recentlyDifficult,
          icon: Icons.psychology_alt_outlined,
          description: 'كانت صعبة في آخر جلسات التسميع.',
          count: state.recentlyDifficultAyahs().length,
        ),
        (
          category: AdaptiveMurajaahCategory.all,
          icon: Icons.auto_awesome_rounded,
          description: 'مزيج ذكي مرتب من الأهم فالأقل أولوية.',
          count: state
              .generateAdaptiveQueue(
                category: AdaptiveMurajaahCategory.all,
                limit: 20,
              )
              .length,
        ),
      ];

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(MishkatRadius.xl),
      ),
    ),
    builder: (sheetContext) {
      final colors = sheetContext.mishkat;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textMuted.withValues(alpha: .35),
                    borderRadius: MishkatRadius.brPill,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'اختر نوع المراجعة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'إن لم تكن متأكداً، اختر «شاملة».',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var index = 0; index < options.length; index++) ...[
                        _ReviewOption(
                          title: options[index].category.label,
                          description: options[index].description,
                          icon: options[index].icon,
                          count: options[index].count,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _startRevision(
                              context,
                              quranData,
                              options[index].category,
                            );
                          },
                        ),
                        if (index != options.length - 1)
                          const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ReviewOption extends StatelessWidget {
  const _ReviewOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.count,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Material(
      color: colors.surfaceVariant,
      borderRadius: MishkatRadius.brMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: MishkatRadius.brMd,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: MishkatRadius.brSm,
                ),
                child: Icon(icon, color: colors.primary, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 34),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: count == 0
                      ? colors.surface
                      : colors.primary.withValues(alpha: .12),
                  borderRadius: MishkatRadius.brPill,
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: count == 0 ? colors.textMuted : colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 46,
            color: context.mishkat.error,
          ),
          const SizedBox(height: 12),
          Text(
            message ?? 'تعذّر تحميل بيانات الحفظ.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          MishkatPrimaryAction(
            label: 'إعادة المحاولة',
            onPressed: () => context.read<QuranMemorizationCubit>().load(),
          ),
        ],
      ),
    ),
  );
}

void _showNeedPlan(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('أنشئ خطة أولاً لتحديد آيات جلسة اليوم.'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

String _planRangeLabel(MemorizationPlan plan, QuranData quranData) {
  final start = quranData.pointForGlobal(plan.startGlobalAyah);
  final end = quranData.pointForGlobal(plan.endGlobalAyah);
  final startChapter = quranData.chapter(start.surah);
  if (start.surah == end.surah) {
    return 'سورة ${startChapter.name} · الآيات ${start.ayah}–${end.ayah}';
  }
  final endChapter = quranData.chapter(end.surah);
  return '${startChapter.name} ${start.ayah} – ${endChapter.name} ${end.ayah}';
}

void _showPlanSwitcher(
  BuildContext context,
  QuranMemorizationState state,
  QuranData quranData,
) {
  final plans = state.plans.where((plan) => !plan.isCompleted).toList();
  if (plans.length < 2) return;
  final colors = context.mishkat;
  final sheetHeight = (150 + (plans.length * 72)).clamp(280, 540).toDouble();

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(MishkatRadius.xl),
      ),
    ),
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textMuted.withValues(alpha: .35),
                    borderRadius: MishkatRadius.brPill,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'اختر خطة التدريب',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'ستعمل طرق التدريب الثلاث على الخطة التي تختارها.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: plans.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final plan = plans[index];
                    return _PlanSwitchChoice(
                      plan: plan,
                      rangeLabel: _planRangeLabel(plan, quranData),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (!plan.isActive) {
                          context.read<QuranMemorizationCubit>().resumePlan(
                            plan.id,
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _showOralRecitationSourceSheet(
  BuildContext context, {
  required MemorizationPlan? plan,
  required QuranData quranData,
}) {
  if (plan == null) {
    _showFreeRecitationSetup(context, quranData);
    return;
  }

  final colors = context.mishkat;
  final startPoint = quranData.pointForGlobal(plan.startGlobalAyah);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(MishkatRadius.xl),
      ),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted.withValues(alpha: .35),
                  borderRadius: MishkatRadius.brPill,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'ماذا تريد أن تسمّع؟',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'اختر الخطة الحالية أو ابدأ جلسة مستقلة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _SheetChoice(
              icon: Icons.bookmark_added_outlined,
              title: plan.title,
              subtitle: _planRangeLabel(plan, quranData),
              onTap: () {
                Navigator.pop(sheetContext);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  OralRecitationInfoSheet.show(
                    context,
                    surahNumber: plan.surah ?? startPoint.surah,
                    startGlobalAyah: plan.startGlobalAyah,
                    endGlobalAyah: plan.endGlobalAyah,
                    planId: plan.id,
                  );
                });
              },
            ),
            const SizedBox(height: 8),
            _SheetChoice(
              icon: Icons.tune_rounded,
              title: 'تسميع حر',
              subtitle: 'اختر سورة كاملة أو نطاقاً محدداً من الآيات.',
              onTap: () {
                Navigator.pop(sheetContext);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  _showFreeRecitationSetup(
                    context,
                    quranData,
                    initialSurah: plan.surah ?? startPoint.surah,
                  );
                });
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void _showFreeRecitationSetup(
  BuildContext context,
  QuranData quranData, {
  int initialSurah = 1,
}) {
  var selectedSurah = initialSurah.clamp(1, quranData.chapters.length);
  var startAyah = 1;
  var endAyah = quranData.chapter(selectedSurah).ayahs.length > 5
      ? 5
      : quranData.chapter(selectedSurah).ayahs.length;
  var wholeSurah = false;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(MishkatRadius.xl),
      ),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final colors = sheetContext.mishkat;
        final chapter = quranData.chapter(selectedSurah);
        final totalAyahs = chapter.ayahs.length;
        final selectedCount = wholeSurah ? totalAyahs : endAyah - startAyah + 1;

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              18,
              12,
              18,
              20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textMuted.withValues(alpha: .35),
                      borderRadius: MishkatRadius.brPill,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'تسميع حر',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'اختر ما تريد تسميعه دون ربط النتيجة بخطة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<int>(
                  key: ValueKey('free-surah-$selectedSurah'),
                  initialValue: selectedSurah,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'السورة',
                    prefixIcon: Icon(Icons.menu_book_outlined),
                  ),
                  items: quranData.chapters
                      .map(
                        (item) => DropdownMenuItem<int>(
                          value: item.number,
                          child: Text(
                            '${item.number}. سورة ${item.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    final ayahCount = quranData.chapter(value).ayahs.length;
                    setSheetState(() {
                      selectedSurah = value;
                      startAyah = 1;
                      endAyah = ayahCount > 5 ? 5 : ayahCount;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceVariant.withValues(alpha: .6),
                    borderRadius: MishkatRadius.brMd,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'السورة كاملة',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'أو عطّل الخيار وحدد بداية ونهاية.',
                              style: TextStyle(fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: wholeSurah,
                        onChanged: (value) {
                          setSheetState(() {
                            wholeSurah = value;
                            if (value) {
                              startAyah = 1;
                              endAyah = totalAyahs;
                            } else {
                              endAyah = totalAyahs > 5 ? 5 : totalAyahs;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
                if (!wholeSurah) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('free-start-$selectedSurah-$startAyah'),
                          initialValue: startAyah,
                          decoration: const InputDecoration(
                            labelText: 'من الآية',
                          ),
                          items: List.generate(totalAyahs, (index) => index + 1)
                              .map(
                                (value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() {
                              startAyah = value;
                              if (endAyah < value) endAyah = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey(
                            'free-end-$selectedSurah-$startAyah-$endAyah',
                          ),
                          initialValue: endAyah,
                          decoration: const InputDecoration(
                            labelText: 'إلى الآية',
                          ),
                          items:
                              List.generate(
                                    totalAyahs - startAyah + 1,
                                    (index) => startAyah + index,
                                  )
                                  .map(
                                    (value) => DropdownMenuItem<int>(
                                      value: value,
                                      child: Text('$value'),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setSheetState(() => endAyah = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  '$selectedCount آية محددة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                MishkatPrimaryAction(
                  label: 'متابعة إلى التسميع',
                  icon: const Icon(Icons.mic_rounded),
                  isFullWidth: true,
                  onPressed: () {
                    final resolvedStart = wholeSurah ? 1 : startAyah;
                    final resolvedEnd = wholeSurah ? totalAyahs : endAyah;
                    final startGlobal = chapter.globalStart + resolvedStart - 1;
                    final endGlobal = chapter.globalStart + resolvedEnd - 1;
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!context.mounted) return;
                      OralRecitationInfoSheet.show(
                        context,
                        surahNumber: selectedSurah,
                        startGlobalAyah: startGlobal,
                        endGlobalAyah: endGlobal,
                      );
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _PlanSwitchChoice extends StatelessWidget {
  const _PlanSwitchChoice({
    required this.plan,
    required this.rangeLabel,
    required this.onTap,
  });

  final MemorizationPlan plan;
  final String rangeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Material(
      color: plan.isActive
          ? colors.primarySoft
          : colors.surfaceVariant.withValues(alpha: .55),
      borderRadius: MishkatRadius.brMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: MishkatRadius.brMd,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Icon(
                plan.isActive
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: plan.isActive ? colors.primary : colors.textMuted,
                size: 22,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rangeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (plan.isActive)
                Text(
                  'الحالية',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 10.5,
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

void _startRevision(
  BuildContext context,
  QuranData quranData,
  AdaptiveMurajaahCategory category,
) {
  final cubit = context.read<QuranMemorizationCubit>();
  cubit.startAdaptiveRevisionSession(category: category, limit: 20);
  if (cubit.state.activeSession == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('لا توجد آيات في هذه الفئة حالياً.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  Navigator.of(context)
      .push(MemorizationSessionPage.route(quranData: quranData));
}

void _showPracticeModeSheet(
  BuildContext context, {
  required String title,
  required List<int> queue,
  required QuranData quranData,
  required String? planId,
  required VoidCallback startTraditional,
}) {
  final colors = context.mishkat;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(MishkatRadius.xl),
      ),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted.withValues(alpha: .35),
                  borderRadius: MishkatRadius.brPill,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${queue.length} آية · اختر أسلوب الجلسة',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _SheetChoice(
              icon: Icons.menu_book_rounded,
              title: 'التسميع في المصحف (بصري)',
              subtitle: 'حجب الآيات وكشفها داخل صفحة المصحف.',
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => QuranReaderPage(
                      initialGlobalAyah: queue.first,
                      visualRecallInitialQueue: queue,
                      visualRecallPlanId: planId,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _SheetChoice(
              icon: Icons.style_outlined,
              title: 'التسميع بالبطاقات (تقليدي)',
              subtitle: 'بطاقة هادئة لكل آية مع تقييم ذاتي.',
              onTap: () {
                Navigator.pop(sheetContext);
                startTraditional();
                Navigator.of(context)
                    .push(MemorizationSessionPage.route(quranData: quranData));
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _SheetChoice extends StatelessWidget {
  const _SheetChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Material(
      color: colors.surfaceVariant.withValues(alpha: .55),
      borderRadius: MishkatRadius.brMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: MishkatRadius.brMd,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

void _showTutorSetup(
  BuildContext context,
  MemorizationPlan plan,
  QuranData quranData,
) {
  var reciterId = context.read<QuranCubit>().reciter;
  var repetitions = 3;
  var pauseSeconds = 3;
  var showAdvancedSettings = false;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(MishkatRadius.xl),
      ),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final colors = sheetContext.mishkat;
        final reciterName = AppConstants.findReciter(reciterId).name;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textMuted.withValues(alpha: .35),
                      borderRadius: MishkatRadius.brPill,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ابدأ التلقين',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'سنقرأ كل آية، ثم نترك لك وقتًا لترديدها.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: MishkatRadius.brMd,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.headphones_rounded,
                        color: colors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$repetitions مرات لكل آية',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$reciterName · $pauseSeconds ثوانٍ للترديد',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setSheetState(
                      () => showAdvancedSettings = !showAdvancedSettings,
                    ),
                    icon: Icon(
                      showAdvancedSettings
                          ? Icons.expand_less_rounded
                          : Icons.tune_rounded,
                      size: 18,
                    ),
                    label: Text(
                      showAdvancedSettings
                          ? 'إخفاء الإعدادات'
                          : 'تعديل القارئ والتكرار',
                    ),
                  ),
                ),
                if (showAdvancedSettings) ...[
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: reciterId,
                    decoration: const InputDecoration(
                      labelText: 'القارئ',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    items: AppConstants.reciters
                        .map(
                          (reciter) => DropdownMenuItem(
                            value: reciter.id,
                            child: Text(reciter.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => reciterId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _StepperSetting(
                    label: 'تكرار كل آية',
                    value: repetitions,
                    suffix: 'مرات',
                    onMinus: repetitions > 1
                        ? () => setSheetState(() => repetitions--)
                        : null,
                    onPlus: repetitions < 10
                        ? () => setSheetState(() => repetitions++)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  _StepperSetting(
                    label: 'وقت الترديد',
                    value: pauseSeconds,
                    suffix: 'ثوانٍ',
                    onMinus: pauseSeconds > 0
                        ? () => setSheetState(() => pauseSeconds--)
                        : null,
                    onPlus: pauseSeconds < 10
                        ? () => setSheetState(() => pauseSeconds++)
                        : null,
                  ),
                ],
                const SizedBox(height: 20),
                MishkatPrimaryAction(
                  label: 'ابدأ الآن',
                  icon: const Icon(Icons.play_arrow_rounded),
                  isFullWidth: true,
                  onPressed: () {
                    context.read<QuranCubit>().updateReciter(reciterId);
                    try {
                      context.read<SettingsCubit>().setReciter(reciterId);
                    } catch (_) {
                      // The session still works when embedded without Settings.
                    }
                    context.read<QuranMemorizationCubit>().startPlanSession(
                      plan,
                    );
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MemorizationSessionPage.route(
                        quranData: quranData,
                        initialRepeatCount: repetitions,
                        initialDelaySeconds: pauseSeconds,
                        startWithAudio: true,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _StepperSetting extends StatelessWidget {
  const _StepperSetting({
    required this.label,
    required this.value,
    required this.suffix,
    this.onMinus,
    this.onPlus,
  });
  final String label;
  final int value;
  final String suffix;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: .55),
        borderRadius: MishkatRadius.brMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$value $suffix',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(onPressed: onPlus, icon: const Icon(Icons.add_rounded)),
        ],
      ),
    );
  }
}
