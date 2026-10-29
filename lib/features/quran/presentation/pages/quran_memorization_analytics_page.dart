import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/memorization_analytics_models.dart';
import '../../data/models/murajaah_models.dart';
import '../../data/models/quran_models.dart';
import '../../data/repositories/mushaf_layout_repository.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_memorization_cubit.dart';
import '../cubit/quran_memorization_state.dart';
import '../widgets/tafsir_knowledge_sheet.dart';
import 'memorization_session_page.dart';
import 'quran_reader_page.dart';

/// Dedicated analytics and progress intelligence page for Quran memorization and Muraja'ah.
class QuranMemorizationAnalyticsPage extends StatefulWidget {
  const QuranMemorizationAnalyticsPage({super.key, required this.quranData});

  final QuranData quranData;

  static Route<void> route({required QuranData quranData}) {
    return MaterialPageRoute<void>(
      builder: (_) => QuranMemorizationAnalyticsPage(quranData: quranData),
    );
  }

  @override
  State<QuranMemorizationAnalyticsPage> createState() =>
      _QuranMemorizationAnalyticsPageState();
}

class _QuranMemorizationAnalyticsPageState
    extends State<QuranMemorizationAnalyticsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _surahSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToAyah(int globalAyah) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuranReaderPage(initialGlobalAyah: globalAyah),
      ),
    );
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

  void _playAyah(int globalAyah) {
    context.read<QuranCubit>().playAyah(globalAyah, continuous: false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('بدأ الاستماع للآية الكريمة'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _startRevision(AdaptiveMurajaahCategory category) {
    context.read<QuranMemorizationCubit>().startAdaptiveRevisionSession(
      category: category,
      limit: 20,
    );
    Navigator.of(context)
        .push(MemorizationSessionPage.route(quranData: widget.quranData));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'تحليلات الحفظ والمراجعة',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: BlocBuilder<QuranMemorizationCubit, QuranMemorizationState>(
        builder: (context, state) {
          final analytics = state.computeAnalytics(widget.quranData);

          return ListView(
            padding: MishkatSpacing.page,
            children: [
              // Calm Intro Header
              _buildHeader(context, analytics),
              const SizedBox(height: MishkatSpacing.lg),

              // 1. Overall Coverage
              _buildOverallCard(context, analytics.overall),
              const SizedBox(height: MishkatSpacing.lg),

              // 2. Upcoming Workload Forecast & Quick Action
              _buildWorkloadCard(context, analytics.forecast),
              const SizedBox(height: MishkatSpacing.lg),

              // 3. Active Plan Progress (if exists)
              if (analytics.plan != null) ...[
                _buildActivePlanCard(context, analytics.plan!),
                const SizedBox(height: MishkatSpacing.lg),
              ],

              // 4. Review Retention & Performance
              _buildRetentionCard(
                context,
                analytics.retention,
                analytics.trend,
              ),
              const SizedBox(height: MishkatSpacing.lg),

              // 5. Weak Ayahs Needing Consolidation
              _buildWeakAyahsSection(context, analytics.weakAyahs),
              const SizedBox(height: MishkatSpacing.xl),

              // 6. Detailed Surah & Juz Breakdowns
              _buildDetailedBreakdownSection(context, analytics),
              const SizedBox(height: MishkatSpacing.xxl),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ComprehensiveMemorizationAnalytics analytics,
  ) {
    final colors = context.mishkat;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_graph_rounded, color: colors.gold, size: 22),
            const SizedBox(width: MishkatSpacing.sm),
            Text(
              'ذكاء التقدم القرآني',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.gold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'نظرة هادئة على محفوظاتك وأولويات المراجعة لتثبيت كتاب الله.',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildOverallCard(
    BuildContext context,
    OverallMemorizationAnalytics overall,
  ) {
    final colors = context.mishkat;

    return MishkatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'تغطية الحفظ الكلية',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: colors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(MishkatRadius.pill),
                ),
                child: Text(
                  overall.formattedPercentage,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(MishkatRadius.pill),
            child: LinearProgressIndicator(
              value: overall.coveragePercentage,
              backgroundColor: colors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: MishkatSpacing.md),
          Text(
            'تم حفظ ${overall.memorized} من أصل ${overall.totalAyahs} آية',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: MishkatSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'المحفوظ',
                  value: '${overall.memorized}',
                  color: colors.primary,
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
              const SizedBox(width: MishkatSpacing.sm),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'قيد الحفظ',
                  value: '${overall.learning}',
                  color: colors.textPrimary,
                  icon: Icons.edit_note_rounded,
                ),
              ),
              const SizedBox(width: MishkatSpacing.sm),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'يحتاج تثبيتاً',
                  value: '${overall.needsRevision}',
                  color: colors.warning,
                  icon: Icons.replay_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkloadCard(
    BuildContext context,
    ReviewWorkloadForecast forecast,
  ) {
    final colors = context.mishkat;

    final (badgeColor, badgeText) = switch (forecast.workloadLevel) {
      WorkloadLevel.light => (colors.primary, 'خفيف وميسر'),
      WorkloadLevel.moderate => (colors.warning, 'متوسط'),
      WorkloadLevel.heavy => (colors.error, 'مرتفع — يحتاج تركيزاً'),
    };

    return MishkatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 18,
                    color: colors.gold,
                  ),
                  const SizedBox(width: MishkatSpacing.sm),
                  Text(
                    'عبء المراجعة المتوقع',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(MishkatRadius.pill),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildSimpleMetricBox(
                  context,
                  title: 'مستحقة اليوم',
                  value: '${forecast.dueTodayCount}',
                  subtitle: 'آية',
                  highlight: forecast.dueTodayCount > 0,
                ),
              ),
              const SizedBox(width: MishkatSpacing.sm),
              Expanded(
                child: _buildSimpleMetricBox(
                  context,
                  title: 'غداً',
                  value: '${forecast.dueTomorrowCount}',
                  subtitle: 'آية',
                ),
              ),
              const SizedBox(width: MishkatSpacing.sm),
              Expanded(
                child: _buildSimpleMetricBox(
                  context,
                  title: 'خلال 7 أيام',
                  value: '${forecast.dueNext7DaysCount}',
                  subtitle: 'آية',
                ),
              ),
            ],
          ),
          if (forecast.dueTodayCount > 0) ...[
            const SizedBox(height: MishkatSpacing.md),
            SizedBox(
              width: double.infinity,
              child: MishkatPrimaryAction(
                label: 'ابدأ مراجعة اليوم (${forecast.dueTodayCount} آية)',
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () =>
                    _startRevision(AdaptiveMurajaahCategory.dueToday),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivePlanCard(
    BuildContext context,
    PlanProgressAnalytics planAnalytics,
  ) {
    final colors = context.mishkat;
    final plan = planAnalytics.plan;

    final (paceColor, paceIcon) = switch (planAnalytics.paceStatus) {
      PlanPaceStatus.ahead => (colors.primary, Icons.trending_up_rounded),
      PlanPaceStatus.onTrack => (
        colors.primary,
        Icons.check_circle_outline_rounded,
      ),
      PlanPaceStatus.needsAttention => (
        colors.warning,
        Icons.priority_high_rounded,
      ),
      PlanPaceStatus.insufficientData => (
        colors.textSecondary,
        Icons.hourglass_top_rounded,
      ),
    };

    return MishkatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  plan.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: paceColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(MishkatRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(paceIcon, size: 13, color: paceColor),
                    const SizedBox(width: 4),
                    Text(
                      planAnalytics.paceStatus.arabicLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: paceColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.sm),
          Text(
            planAnalytics.paceMessage,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: MishkatSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(MishkatRadius.pill),
            child: LinearProgressIndicator(
              value: planAnalytics.completionPercentage,
              backgroundColor: colors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation<Color>(colors.gold),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: MishkatSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${planAnalytics.memorizedCount} من ${planAnalytics.totalAyahs} آية (${(planAnalytics.completionPercentage * 100).toStringAsFixed(0)}%)',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
              Text(
                'المتبقي: ${planAnalytics.remainingCount} آية (${planAnalytics.estimatedDaysRemaining} يوم)',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRetentionCard(
    BuildContext context,
    ReviewRetentionAnalytics retention,
    MurajaahTrendAnalytics trend,
  ) {
    final colors = context.mishkat;

    return MishkatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: colors.gold),
              const SizedBox(width: MishkatSpacing.sm),
              Text(
                'أداء المراجعة والاحتفاظ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.md),
          // Frequency counts
          Row(
            children: [
              Expanded(
                child: _buildSimpleMetricBox(
                  context,
                  title: 'اليوم',
                  value: '${retention.reviewsToday}',
                  subtitle: 'مراجعة',
                ),
              ),
              const SizedBox(width: MishkatSpacing.sm),
              Expanded(
                child: _buildSimpleMetricBox(
                  context,
                  title: 'هذا الأسبوع',
                  value: '${retention.reviewsThisWeek}',
                  subtitle: 'مراجعة',
                ),
              ),
              const SizedBox(width: MishkatSpacing.sm),
              Expanded(
                child: _buildSimpleMetricBox(
                  context,
                  title: 'هذا الشهر',
                  value: '${retention.reviewsThisMonth}',
                  subtitle: 'مراجعة',
                ),
              ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.md),

          // Retention ratios if data sufficient
          if (retention.hasSufficientData) ...[
            Container(
              padding: const EdgeInsets.all(MishkatSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(MishkatRadius.md),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'معدل الاستذكار الناجح',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        '${((retention.successRate ?? 0) * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MishkatSpacing.sm),
                  Row(
                    children: [
                      Text(
                        'سهل: ${retention.easyCount}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('•', style: TextStyle(color: colors.textSecondary)),
                      const SizedBox(width: 8),
                      Text(
                        'جيد: ${retention.goodCount}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('•', style: TextStyle(color: colors.textSecondary)),
                      const SizedBox(width: 8),
                      Text(
                        'صعب: ${retention.difficultCount}',
                        style: TextStyle(fontSize: 11, color: colors.warning),
                      ),
                      const SizedBox(width: 8),
                      Text('•', style: TextStyle(color: colors.textSecondary)),
                      const SizedBox(width: 8),
                      Text(
                        'لم أتذكر: ${retention.failedCount}',
                        style: TextStyle(fontSize: 11, color: colors.error),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(MishkatSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(MishkatRadius.md),
              ),
              child: Text(
                'لا توجد بيانات مراجعة كافية بعد لحساب معدل الاحتفاظ الدقيق (يلزم 5 مراجعات على الأقل).',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ),
          ],

          const SizedBox(height: MishkatSpacing.sm),
          // Trend note
          Row(
            children: [
              Icon(
                trend.direction == TrendDirection.increasing
                    ? Icons.trending_up_rounded
                    : (trend.direction == TrendDirection.decreasing
                          ? Icons.trending_down_rounded
                          : Icons.info_outline_rounded),
                size: 14,
                color: colors.gold,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  trend.description,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeakAyahsSection(
    BuildContext context,
    List<WeakAyahInsight> weakAyahs,
  ) {
    final colors = context.mishkat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: colors.warning),
                const SizedBox(width: MishkatSpacing.sm),
                Text(
                  'مواضع تحتاج تثبيتاً',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            if (weakAyahs.isNotEmpty)
              TextButton(
                onPressed: () => _startRevision(AdaptiveMurajaahCategory.weak),
                child: const Text('مراجعة الكل'),
              ),
          ],
        ),
        const SizedBox(height: MishkatSpacing.sm),
        if (weakAyahs.isEmpty) ...[
          MishkatCard(
            child: Row(
              children: [
                Icon(Icons.verified_outlined, color: colors.primary, size: 24),
                const SizedBox(width: MishkatSpacing.md),
                Expanded(
                  child: Text(
                    'لا توجد حالياً مواضع تحتاج تثبيتاً — ثبّتك الله وبارك في حفظك.',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: weakAyahs.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: MishkatSpacing.sm),
            itemBuilder: (context, index) {
              final item = weakAyahs[index];
              return _buildWeakAyahTile(context, item);
            },
          ),
        ],
      ],
    );
  }

  Widget _buildWeakAyahTile(BuildContext context, WeakAyahInsight item) {
    final colors = context.mishkat;

    return MishkatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primarySoft,
                      borderRadius: BorderRadius.circular(MishkatRadius.pill),
                    ),
                    child: Text(
                      'سورة ${item.surahName}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'الآية ${item.ayahNumber}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(MishkatRadius.sm),
                ),
                child: Text(
                  item.scheduleState.arabicLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: colors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.history_toggle_off_rounded,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'الأخطاء المسجلة: ${item.mistakeCount}',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
              const Spacer(),
              // Actions
              IconButton(
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                tooltip: 'فتح في المصحف',
                onPressed: () => _navigateToAyah(item.globalAyah),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.auto_stories_rounded, size: 18),
                tooltip: 'التفسير',
                onPressed: () => _openTafsir(item.globalAyah),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.volume_up_rounded, size: 18),
                tooltip: 'استماع',
                onPressed: () => _playAyah(item.globalAyah),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedBreakdownSection(
    BuildContext context,
    ComprehensiveMemorizationAnalytics analytics,
  ) {
    final colors = context.mishkat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.pie_chart_outline_rounded, size: 18, color: colors.gold),
            const SizedBox(width: MishkatSpacing.sm),
            Text(
              'تغطية السور والأجزاء',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: MishkatSpacing.sm),
        TabBar(
          controller: _tabController,
          labelColor: colors.primary,
          unselectedLabelColor: colors.textSecondary,
          indicatorColor: colors.primary,
          tabs: const [
            Tab(text: 'السور (114)'),
            Tab(text: 'الأجزاء (30)'),
          ],
        ),
        const SizedBox(height: MishkatSpacing.md),
        SizedBox(
          height: 380,
          child: TabBarView(
            controller: _tabController,
            children: [
              // Surahs list
              _buildSurahsTab(context, analytics.surahs),
              // Juzs list
              _buildJuzsTab(context, analytics.juzs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSurahsTab(
    BuildContext context,
    List<SurahMemorizationAnalytics> surahs,
  ) {
    final colors = context.mishkat;

    final filtered = _surahSearchQuery.isEmpty
        ? surahs
        : surahs.where((s) => s.name.contains(_surahSearchQuery)).toList();

    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: 'ابحث عن سورة...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MishkatRadius.md),
              borderSide: BorderSide(color: colors.border),
            ),
          ),
          onChanged: (val) {
            setState(() {
              _surahSearchQuery = val.trim();
            });
          },
        ),
        const SizedBox(height: MishkatSpacing.sm),
        Expanded(
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final surah = filtered[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${surah.surahNumber}. سورة ${surah.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  '${surah.memorizedCount} / ${surah.totalAyahs} آية',
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (surah.weakCount > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            MishkatRadius.pill,
                          ),
                        ),
                        child: Text(
                          '${surah.weakCount} يحتاج تثبيتاً',
                          style: TextStyle(fontSize: 9, color: colors.warning),
                        ),
                      ),
                    Text(
                      '${(surah.completionPercentage * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: surah.isCompleted
                            ? colors.primary
                            : colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  final chapter = widget.quranData.chapter(surah.surahNumber);
                  _navigateToAyah(chapter.globalStart);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildJuzsTab(
    BuildContext context,
    List<JuzMemorizationAnalytics> juzs,
  ) {
    final colors = context.mishkat;

    return ListView.separated(
      itemCount: juzs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final juz = juzs[index];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'الجزء ${juz.juzNumber}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Text(
            '${juz.memorizedCount} / ${juz.totalAyahs} آية',
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (juz.weakCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(MishkatRadius.pill),
                  ),
                  child: Text(
                    '${juz.weakCount} يحتاج تثبيتاً',
                    style: TextStyle(fontSize: 9, color: colors.warning),
                  ),
                ),
              Text(
                '${(juz.completionPercentage * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: juz.isCompleted ? colors.primary : colors.textPrimary,
                ),
              ),
            ],
          ),
          onTap: () => _navigateToAyah(juz.startGlobalAyah),
        );
      },
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final colors = context.mishkat;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MishkatSpacing.sm,
        vertical: MishkatSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(MishkatRadius.md),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleMetricBox(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    bool highlight = false,
  }) {
    final colors = context.mishkat;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MishkatSpacing.sm,
        vertical: MishkatSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: highlight
            ? colors.primary.withValues(alpha: 0.08)
            : colors.surfaceMuted,
        borderRadius: BorderRadius.circular(MishkatRadius.sm),
        border: highlight
            ? Border.all(color: colors.primary.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: highlight ? colors.primary : colors.textPrimary,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
