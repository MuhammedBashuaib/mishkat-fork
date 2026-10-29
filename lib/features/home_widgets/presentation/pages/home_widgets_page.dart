import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/home_widget_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../../home/presentation/cubit/home_cubit.dart';
import '../../../home/presentation/cubit/home_state.dart';
import '../../../prayer_times/data/services/prayer_calculator.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';

class HomeWidgetsPage extends StatefulWidget {
  const HomeWidgetsPage({super.key});

  @override
  State<HomeWidgetsPage> createState() => _HomeWidgetsPageState();
}

class _HomeWidgetsPageState extends State<HomeWidgetsPage>
    with WidgetsBindingObserver {
  final Map<MishkatHomeWidget, bool> _installed = {};
  bool _pinSupported = false;
  bool _loading = true;
  MishkatHomeWidget? _adding;

  HomeWidgetService get _service => context.read<HomeWidgetService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final results = await Future.wait([
      for (final widget in MishkatHomeWidget.values)
        _service.isInstalled(widget),
    ]);
    final pinSupported = await _service.isPinRequestSupported();
    if (!mounted) return;
    setState(() {
      for (var index = 0; index < MishkatHomeWidget.values.length; index++) {
        _installed[MishkatHomeWidget.values[index]] = results[index];
      }
      _pinSupported = pinSupported;
      _loading = false;
    });
  }

  Future<void> _add(MishkatHomeWidget widget) async {
    if (!_pinSupported) {
      await _showManualInstructions();
      return;
    }
    setState(() => _adding = widget);
    try {
      await _service.requestPin(widget);
      if (mounted) {
        context.showMessage('أكمل الإضافة من نافذة النظام الظاهرة أمامك.');
      }
    } on Object {
      if (mounted) {
        context.showMessage(
          'تعذّرت الإضافة المباشرة. يمكنك إضافتها يدويًا من قائمة ودجت الجهاز.',
        );
      }
    } finally {
      if (mounted) setState(() => _adding = null);
    }
  }

  Future<void> _showManualInstructions() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'أضف ودجت مشكاة',
              style: Theme.of(sheetContext).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              isIOS
                  ? 'يمنح iPhone التحكم في الإضافة للمستخدم، وتستغرق الخطوات ثوانٍ قليلة.'
                  : 'مشغّل الشاشة في جهازك لا يدعم الإضافة التلقائية؛ استخدم الخطوات التالية.',
              style: TextStyle(color: sheetContext.mishkat.textSecondary),
            ),
            const SizedBox(height: 20),
            _InstructionStep(
              number: '١',
              text: 'اضغط مطولًا على مساحة فارغة في الشاشة الرئيسية.',
            ),
            _InstructionStep(
              number: '٢',
              text: isIOS
                  ? 'اضغط «تعديل» ثم «إضافة ودجت» أو علامة +.'
                  : 'اختر «الأدوات» أو «Widgets» من القائمة.',
            ),
            const _InstructionStep(
              number: '٣',
              text: 'ابحث عن «مشكاة»، ثم اختر المقاس الذي يعجبك.',
            ),
            const _InstructionStep(
              number: '٤',
              text: 'اضغط «إضافة» وضعها حيث تريد.',
              isLast: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('فهمت'),
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state.settings;
    final homeState = context.watch<HomeCubit>().state;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_forward_rounded),
          tooltip: 'رجوع',
        ),
        title: const Text('ودجت مشكاة'),
        actions: [
          IconButton(
            onPressed: _refreshStatus,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث الحالة',
          ),
        ],
      ),
      body: ListView(
        padding: MishkatSpacing.page,
        children: [
          _WidgetsIntro(isIOS: isIOS),
          const SizedBox(height: MishkatSpacing.xl),
          _WidgetOptionCard(
            kind: _WidgetVisualKind.prayer,
            title: 'مواقيت الصلاة',
            description: 'الصلاة القادمة، وقتها، ولمحة سريعة عن بقية اليوم.',
            sizeLabel: 'عريضة · ٤×٢',
            installed: _installed[MishkatHomeWidget.prayerTimes] == true,
            loading: _loading || _adding == MishkatHomeWidget.prayerTimes,
            onAdd: () => _add(MishkatHomeWidget.prayerTimes),
            preview: _PrayerWidgetPreview(state: homeState),
          ),
          const SizedBox(height: MishkatSpacing.lg),
          _WidgetOptionCard(
            kind: _WidgetVisualKind.qibla,
            title: 'بوصلة القبلة',
            description: 'اتجاه القبلة من الشمال، والضغط يفتح البوصلة الحية.',
            sizeLabel: 'مربعة · ٢×٢',
            installed: _installed[MishkatHomeWidget.qibla] == true,
            loading: _loading || _adding == MishkatHomeWidget.qibla,
            onAdd: () => _add(MishkatHomeWidget.qibla),
            preview: _QiblaWidgetPreview(
              latitude: settings.latitude,
              longitude: settings.longitude,
            ),
          ),
          const SizedBox(height: MishkatSpacing.lg),
          _WidgetOptionCard(
            kind: _WidgetVisualKind.adhkar,
            title: 'ذِكر اليوم',
            description:
                'يتبدّل تلقائيًا بين ذكر الصباح والنهار والمساء والنوم.',
            sizeLabel: 'عريضة · ٤×٢',
            installed: _installed[MishkatHomeWidget.adhkar] == true,
            loading: _loading || _adding == MishkatHomeWidget.adhkar,
            onAdd: () => _add(MishkatHomeWidget.adhkar),
            preview: const _AdhkarWidgetPreview(),
          ),
          const SizedBox(height: MishkatSpacing.lg),
          _BehaviorNote(isIOS: isIOS),
          const SizedBox(height: MishkatSpacing.xxl),
        ],
      ),
    );
  }
}

class _WidgetsIntro extends StatelessWidget {
  const _WidgetsIntro({required this.isIOS});
  final bool isIOS;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [context.mishkat.brandDeep, const Color(0xFF183D34)],
      ),
      borderRadius: MishkatRadius.brXl,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: MishkatRadius.brMd,
          ),
          child: const Icon(
            Icons.widgets_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'روح مشكاة، أقرب إليك',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isIOS
                    ? 'معاينات حيّة تتبع مظهر iPhone وتفتح مشكاة بلمسة واحدة.'
                    : 'أضف ما تحتاجه الآن؛ جميع البيانات محلية وتعمل دون إنترنت.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.74),
                  height: 1.5,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

enum _WidgetVisualKind { prayer, qibla, adhkar }

extension on _WidgetVisualKind {
  IconData get icon => switch (this) {
    _WidgetVisualKind.prayer => Icons.mosque_rounded,
    _WidgetVisualKind.qibla => Icons.explore_rounded,
    _WidgetVisualKind.adhkar => Icons.auto_awesome_rounded,
  };

  Color accent(bool isDark) => switch (this) {
    _WidgetVisualKind.prayer =>
      isDark ? const Color(0xFF8ED9BD) : const Color(0xFF276C5D),
    _WidgetVisualKind.qibla =>
      isDark ? const Color(0xFFF0CE7D) : const Color(0xFF8A6726),
    _WidgetVisualKind.adhkar =>
      isDark ? const Color(0xFFE5BFA4) : const Color(0xFF8B5D43),
  };

  Color soft(bool isDark) => switch (this) {
    _WidgetVisualKind.prayer =>
      isDark ? const Color(0xFF1C3830) : const Color(0xFFE3F0EB),
    _WidgetVisualKind.qibla =>
      isDark ? const Color(0xFF3A3020) : const Color(0xFFF4ECD9),
    _WidgetVisualKind.adhkar =>
      isDark ? const Color(0xFF392A25) : const Color(0xFFF4E8E0),
  };

  List<Color> stageGradient(bool isDark) => switch (this) {
    _WidgetVisualKind.prayer =>
      isDark
          ? const [Color(0xFF101C18), Color(0xFF152A24)]
          : const [Color(0xFFF1F7F4), Color(0xFFE8F2EE)],
    _WidgetVisualKind.qibla =>
      isDark
          ? const [Color(0xFF151C19), Color(0xFF20251D)]
          : const [Color(0xFFF4F3EC), Color(0xFFEAEDE5)],
    _WidgetVisualKind.adhkar =>
      isDark
          ? const [Color(0xFF1E1817), Color(0xFF2A211E)]
          : const [Color(0xFFFBF5EF), Color(0xFFF4EAE3)],
  };
}

class _WidgetOptionCard extends StatelessWidget {
  const _WidgetOptionCard({
    required this.kind,
    required this.title,
    required this.description,
    required this.sizeLabel,
    required this.installed,
    required this.loading,
    required this.onAdd,
    required this.preview,
  });

  final _WidgetVisualKind kind;
  final String title;
  final String description;
  final String sizeLabel;
  final bool installed;
  final bool loading;
  final VoidCallback onAdd;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = kind.accent(isDark);

    return MishkatCard(
      padding: EdgeInsets.zero,
      borderColor: isDark
          ? accent.withValues(alpha: .2)
          : accent.withValues(alpha: .13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kind.soft(isDark),
                    borderRadius: MishkatRadius.brMd,
                  ),
                  child: Icon(kind.icon, color: accent, size: 21),
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
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (installed) ...[
                            const SizedBox(width: 8),
                            _InstalledBadge(accent: accent),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          height: 1.45,
                          fontSize: 12,
                          color: context.mishkat.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: kind.soft(isDark),
                    borderRadius: MishkatRadius.brPill,
                  ),
                  child: Text(
                    sizeLabel,
                    style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: kind.stageGradient(isDark),
              ),
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: accent.withValues(alpha: isDark ? .13 : .09),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: preview),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _AddWidgetButton(
              accent: accent,
              softColor: kind.soft(isDark),
              installed: installed,
              loading: loading,
              onPressed: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstalledBadge extends StatelessWidget {
  const _InstalledBadge({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .12),
      borderRadius: MishkatRadius.brPill,
    ),
    child: Text(
      'مضافة',
      style: TextStyle(
        color: accent,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _AddWidgetButton extends StatelessWidget {
  const _AddWidgetButton({
    required this.accent,
    required this.softColor,
    required this.installed,
    required this.loading,
    required this.onPressed,
  });

  final Color accent;
  final Color softColor;
  final bool installed;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = installed
        ? accent
        : (isDark ? const Color(0xFF0D211B) : Colors.white);
    final background = installed
        ? softColor
        : (isDark ? accent : accent.withValues(alpha: .96));

    return Semantics(
      button: true,
      enabled: !loading,
      label: installed ? 'أضف نسخة أخرى' : 'أضف للشاشة الرئيسية',
      child: SizedBox(
        height: 50,
        child: Material(
          color: loading ? context.mishkat.surfaceVariant : background,
          borderRadius: MishkatRadius.brMd,
          child: InkWell(
            onTap: loading ? null : onPressed,
            borderRadius: MishkatRadius.brMd,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: MishkatRadius.brMd,
                border: Border.all(
                  color: loading
                      ? context.mishkat.border
                      : installed
                      ? accent.withValues(alpha: .36)
                      : Colors.white.withValues(alpha: isDark ? .10 : .16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: accent,
                      ),
                    )
                  else
                    Icon(
                      installed
                          ? Icons.add_rounded
                          : Icons.add_to_home_screen_rounded,
                      color: foreground,
                      size: 20,
                    ),
                  const SizedBox(width: 9),
                  Text(
                    loading
                        ? 'جارٍ التحقق…'
                        : installed
                        ? 'أضف نسخة أخرى'
                        : 'أضف للشاشة الرئيسية',
                    style: TextStyle(
                      color: loading
                          ? context.mishkat.textSecondary
                          : foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
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

class _PrayerWidgetPreview extends StatelessWidget {
  const _PrayerWidgetPreview({required this.state});
  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final schedule = state.schedule;
    final next = schedule?.next;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF91DDC0) : const Color(0xFF276C5D);
    final primaryText = isDark
        ? const Color(0xFFF3F8F5)
        : const Color(0xFF17362F);
    final secondaryText = isDark
        ? const Color(0xFFADBBB5)
        : const Color(0xFF60716B);
    final backgroundTop = isDark
        ? const Color(0xFF172A24)
        : const Color(0xFFF7FBF9);
    final backgroundBottom = isDark
        ? const Color(0xFF10201B)
        : const Color(0xFFEAF3EF);
    final city = context.watch<SettingsCubit>().state.settings.city;
    final upcoming =
        schedule?.moments
            .where((moment) => moment.at.isAfter(state.now))
            .take(3)
            .toList() ??
        const [];
    return AspectRatio(
      aspectRatio: 2.08,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [backgroundTop, backgroundBottom],
          ),
          borderRadius: MishkatRadius.brXl,
          border: Border.all(color: accent.withValues(alpha: .2)),
          boxShadow: MishkatShadows.elevated(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            PositionedDirectional(
              top: -48,
              start: -30,
              child: Container(
                width: 138,
                height: 138,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: isDark ? .055 : .07),
                  border: Border.all(
                    color: accent.withValues(alpha: .08),
                    width: 14,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .12),
                          borderRadius: MishkatRadius.brPill,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mosque_rounded, color: accent, size: 12),
                            const SizedBox(width: 5),
                            Text(
                              'مِشكاة • الصلاة',
                              style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 105),
                        child: Text(
                          city.isEmpty ? 'موقعك' : city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .09),
                          borderRadius: MishkatRadius.brMd,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              next == null ? 'حدّد موقعك' : 'الوقت المتبقي',
                              style: TextStyle(
                                color: secondaryText,
                                fontSize: 9,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              next == null
                                  ? '—'
                                  : AppFormatters.duration(
                                      next.at.difference(state.now),
                                    ).substring(0, 5),
                              style: TextStyle(
                                color: accent,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'الصلاة القادمة',
                            style: TextStyle(color: secondaryText, fontSize: 9),
                          ),
                          Text(
                            next?.name ?? '—',
                            style: TextStyle(
                              color: primaryText,
                              fontSize: 23,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            AppFormatters.time(next?.at),
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    upcoming.isEmpty
                        ? 'تظهر المواقيت بعد تحديد الموقع'
                        : upcoming
                              .map(
                                (moment) =>
                                    '${moment.name} ${AppFormatters.time(moment.at)}',
                              )
                              .join('  •  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: secondaryText,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QiblaWidgetPreview extends StatelessWidget {
  const _QiblaWidgetPreview({this.latitude, this.longitude});
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context) {
    final result = latitude == null || longitude == null
        ? null
        : const PrayerCalculator().qibla(latitude!, longitude!);
    final bearing = result?.bearing ?? 45;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gold = isDark ? const Color(0xFFF1D38A) : const Color(0xFFE8C984);
    return SizedBox.square(
      dimension: 190,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: isDark
                ? const [Color(0xFF17382F), Color(0xFF0C211B)]
                : const [Color(0xFF2D6256), Color(0xFF173B32)],
          ),
          borderRadius: MishkatRadius.brXl,
          border: Border.all(color: gold.withValues(alpha: .2)),
          boxShadow: MishkatShadows.elevated(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .09),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: .08),
                        border: Border.all(color: gold.withValues(alpha: .15)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          'ش',
                          style: TextStyle(
                            color: Color(0xFFAFCBC1),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'مِشكاة • القبلة',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: Color(0xFFC8DDD5),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Transform.rotate(
                    angle: bearing * math.pi / 180,
                    child: Icon(
                      Icons.navigation_rounded,
                      color: gold,
                      size: 48,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    result == null
                        ? 'حدّد موقعك'
                        : '${result.bearing.round()}° من الشمال',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result == null
                        ? 'افتح مشكاة للبوصلة الحية'
                        : '${result.distanceKm.round()} كم إلى الكعبة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB7D0C7),
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdhkarWidgetPreview extends StatelessWidget {
  const _AdhkarWidgetPreview();

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFFE8C19F) : const Color(0xFF8B5D43);
    final text = isDark ? const Color(0xFFF7EEE8) : const Color(0xFF3E2C24);
    final secondary = isDark
        ? const Color(0xFFC2ACA0)
        : const Color(0xFF7A6559);
    final category = hour >= 16 && hour < 22
        ? 'أذكار المساء'
        : hour >= 22 || hour < 5
        ? 'أذكار النوم'
        : hour >= 5 && hour < 12
        ? 'أذكار الصباح'
        : 'ذِكر اليوم';
    return AspectRatio(
      aspectRatio: 2.08,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: isDark
                ? const [Color(0xFF2C221F), Color(0xFF1D1816)]
                : const [Color(0xFFFFFAF5), Color(0xFFF6ECE4)],
          ),
          borderRadius: MishkatRadius.brXl,
          border: Border.all(color: accent.withValues(alpha: .2)),
          boxShadow: MishkatShadows.elevated(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            PositionedDirectional(
              bottom: -42,
              start: -18,
              child: Icon(
                Icons.format_quote_rounded,
                size: 124,
                color: accent.withValues(alpha: .06),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .12),
                          borderRadius: MishkatRadius.brSm,
                        ),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        category,
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .11),
                          borderRadius: MishkatRadius.brPill,
                        ),
                        child: Text(
                          '٣ مرات',
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'رَضِيتُ بِاللَّهِ رَبًّا، وَبِالإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ ﷺ نَبِيًّا.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: text,
                      fontSize: 15,
                      height: 1.55,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_back_rounded,
                        size: 13,
                        color: secondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'اضغط للمتابعة داخل مشكاة',
                        style: TextStyle(color: secondary, fontSize: 9.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BehaviorNote extends StatelessWidget {
  const _BehaviorNote({required this.isIOS});
  final bool isIOS;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.mishkat.primarySoft,
      borderRadius: MishkatRadius.brLg,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.auto_awesome_rounded, color: context.mishkat.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            isIOS
                ? 'تتبع الودجت المظهر الفاتح والداكن، وتحدّث محتواها عبر Timeline من النظام.'
                : 'تتحدّث الصلاة والأذكار في أوقاتها تلقائيًا دون تشغيل مستشعر دائم أو استهلاك ملحوظ للبطارية.',
            style: TextStyle(
              color: context.mishkat.primary,
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({
    required this.number,
    required this.text,
    this.isLast = false,
  });

  final String number;
  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: context.mishkat.primarySoft,
              child: Text(
                number,
                style: TextStyle(
                  color: context.mishkat.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!isLast)
              Expanded(
                child: Container(
                  width: 1,
                  color: context.mishkat.border,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 20),
            child: Text(text, style: const TextStyle(height: 1.5)),
          ),
        ),
      ],
    ),
  );
}
