import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/home_widget_service.dart';
import '../../../../core/services/home_widget_content.dart';
import '../../../khatma/presentation/cubit/khatma_cubit.dart';
import '../../../tasbih/presentation/cubit/tasbih_cubit.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/navigation_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../../home/presentation/cubit/home_cubit.dart';
import '../../../home/presentation/cubit/home_state.dart';
import '../../../prayer_times/data/services/prayer_calculator.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../qibla/presentation/pages/qibla_page.dart';

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
  _GalleryFilter _filter = _GalleryFilter.all;

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
    if (_adding != null) return;
    if (!_pinSupported) {
      await _showManualInstructions(widget);
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

  Future<void> _showManualInstructions([MishkatHomeWidget? widget]) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheetContext) {
          final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
          return SingleChildScrollView(
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
                _InstructionStep(
                  number: '٣',
                  text: widget == null
                      ? 'ابحث عن «مشكاة»، ثم اختر الإضافة التي تريدها.'
                      : 'ابحث عن «مشكاة»، ثم اختر «${_widgetTitle(widget)}».',
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

  Future<void> _showLockScreenInstructions() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      final steps = isIOS
          ? const [
              'افتح قفل iPhone، ثم اضغط مطولًا على شاشة القفل.',
              'اختر «تخصيص» ثم «شاشة القفل».',
              'اضغط «إضافة ودجت»، ثم اختر «مشكاة» و«مواقيت الصلاة».',
              'اختر الشكل الذي يناسبك، ثم اضغط «تم».',
            ]
          : const [
              'إذا كان جهازك يدعم ودجت شاشة القفل، افتح تخصيص شاشة القفل أو لوحة الودجت من إعدادات الجهاز.',
              'اختر إضافة ودجت، ثم ابحث عن «مشكاة» و«مواقيت الصلاة».',
              'ضع الودجت في المساحة المتاحة واحفظ التخصيص. تختلف الخطوات حسب نوع الجهاز.',
            ];
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'أضف الصلاة إلى شاشة القفل',
              style: Theme.of(sheetContext).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              isIOS
                  ? 'متاحة على iPhone بنظام iOS 16 أو أحدث. يمكنك اختيار شكل مستطيل أو دائري أو سطر فوق الساعة.'
                  : 'تعتمد الإتاحة على جهازك وإصدار النظام. إذا لم تجد خيار الودجت في شاشة القفل، استخدم ودجت الشاشة الرئيسية.',
              style: TextStyle(color: sheetContext.mishkat.textSecondary),
            ),
            const SizedBox(height: 20),
            for (var index = 0; index < steps.length; index++)
              _InstructionStep(
                number: widgetDigits(index + 1),
                text: steps[index],
                isLast: index == steps.length - 1,
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
    final wird = WirdWidgetContent(context.watch<KhatmaCubit>().state.active);
    final tasbih = TasbihWidgetContent(context.watch<TasbihCubit>().state);
    final darkPreview = switch (settings.widgetTheme) {
      AppThemePreference.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      AppThemePreference.light => false,
      AppThemePreference.dark => true,
    };
    Widget preview(Widget child) => Theme(
      data: Theme.of(
        context,
      ).copyWith(brightness: darkPreview ? Brightness.dark : Brightness.light),
      child: child,
    );
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(MishkatNavigationIcons.back),
          tooltip: 'رجوع',
        ),
        title: const Text('ودجت مشكاة'),
        actions: [
          IconButton(
            onPressed: () => _showManualInstructions(),
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'طريقة الإضافة',
          ),
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
          const SizedBox(height: 20),
          _WidgetThemeSelector(value: settings.widgetTheme, isIOS: isIOS),
          const SizedBox(height: 20),
          Text(
            'اختر ما يرافق يومك',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in _GalleryFilter.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      selectedColor: context.mishkat.primarySoft,
                      backgroundColor: context.mishkat.surface,
                      checkmarkColor: context.mishkat.primary,
                      labelStyle: TextStyle(
                        color: _filter == filter
                            ? context.mishkat.primary
                            : context.mishkat.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: MishkatSpacing.lg),
          if (_filter == _GalleryFilter.all ||
              _filter == _GalleryFilter.quran) ...[
            _WidgetOptionCard(
              kind: _WidgetVisualKind.wird,
              title: 'الورد اليومي',
              description: 'وردك وتقدّم ختمتك والصفحات المتبقية في لمحة واحدة.',
              sizeLabel: 'عريضة · ٤×٢',
              installed: _installed[MishkatHomeWidget.wird] == true,
              loading: _loading || _adding != null,
              onAdd: () => _add(MishkatHomeWidget.wird),
              preview: preview(_WirdWidgetPreview(content: wird)),
            ),
            const SizedBox(height: MishkatSpacing.lg),
          ],
          if (_filter == _GalleryFilter.all ||
              _filter == _GalleryFilter.dhikr) ...[
            _WidgetOptionCard(
              kind: _WidgetVisualKind.tasbih,
              title: 'المسبحة',
              description: 'حلقة تتقدّم مع ذكرك نحو هدفك اليومي.',
              sizeLabel: 'مدمجة · ٢×٢',
              installed: _installed[MishkatHomeWidget.tasbih] == true,
              loading: _loading || _adding != null,
              onAdd: () => _add(MishkatHomeWidget.tasbih),
              preview: preview(_TasbihWidgetPreview(content: tasbih)),
            ),
            const SizedBox(height: MishkatSpacing.lg),
          ],
          if (_filter == _GalleryFilter.all ||
              _filter == _GalleryFilter.prayer) ...[
            _WidgetOptionCard(
              kind: _WidgetVisualKind.prayer,
              title: 'مواقيت الصلاة',
              description:
                  'الصلاة القادمة وعداد متبقٍ بالثواني من مواقيت تطبيقك.',
              sizeLabel: 'عريضة · ٤×٢',
              installed: _installed[MishkatHomeWidget.prayerTimes] == true,
              loading: _loading || _adding != null,
              onAdd: () => _add(MishkatHomeWidget.prayerTimes),
              preview: preview(_PrayerWidgetPreview(state: homeState)),
            ),
            const SizedBox(height: MishkatSpacing.lg),
            _LockScreenPrayerCard(
              state: homeState,
              isIOS: isIOS,
              onInstructions: _showLockScreenInstructions,
            ),
            const SizedBox(height: MishkatSpacing.lg),
            _WidgetOptionCard(
              kind: _WidgetVisualKind.qibla,
              title: 'بوصلة القبلة',
              description: 'سهم يوضح اتجاه القبلة من الشمال؛ اضغط لفتح البوصلة التي تتحرك مع جهازك.',
              sizeLabel: 'مربعة · ٢×٢',
              installed: _installed[MishkatHomeWidget.qibla] == true,
              loading: _loading || _adding != null,
              onAdd: () => _add(MishkatHomeWidget.qibla),
              preview: preview(
                Semantics(
                  button: true,
                  label: 'افتح البوصلة الحية',
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const QiblaPage()),
                    ),
                    child: _QiblaWidgetPreview(
                      latitude: settings.latitude,
                      longitude: settings.longitude,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: MishkatSpacing.lg),
          ],
          if (_filter == _GalleryFilter.all ||
              _filter == _GalleryFilter.dhikr) ...[
            _WidgetOptionCard(
              kind: _WidgetVisualKind.adhkar,
              title: 'ذِكر اليوم',
              description:
                  'يتبدّل تلقائيًا بين ذكر الصباح والنهار والمساء والنوم.',
              sizeLabel: 'عريضة · ٤×٢',
              installed: _installed[MishkatHomeWidget.adhkar] == true,
              loading: _loading || _adding != null,
              onAdd: () => _add(MishkatHomeWidget.adhkar),
              preview: preview(const _AdhkarWidgetPreview()),
            ),
            const SizedBox(height: MishkatSpacing.lg),
          ],
          _BehaviorNote(isIOS: isIOS),
          const SizedBox(height: MishkatSpacing.xxl),
        ],
      ),
    );
  }
}

class _WidgetThemeSelector extends StatelessWidget {
  const _WidgetThemeSelector({required this.value, required this.isIOS});

  final AppThemePreference value;
  final bool isIOS;

  @override
  Widget build(BuildContext context) => MishkatCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isIOS ? 'مظهر ودجت الشاشة الرئيسية' : 'مظهر الودجت',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          isIOS
              ? 'اختر حسب النظام أو مظهرًا ثابتًا للشاشة الرئيسية. ودجت شاشة القفل تتبع مظهر شاشة القفل.'
              : 'يتبع مظهر جهازك تلقائيًا، أو اختر مظهرًا ثابتًا للودجت.',
          style: TextStyle(
            color: context.mishkat.textSecondary,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preference in AppThemePreference.values)
              ChoiceChip(
                key: ValueKey('widget-theme-${preference.name}'),
                avatar: Icon(switch (preference) {
                  AppThemePreference.system => Icons.brightness_auto_outlined,
                  AppThemePreference.light => Icons.light_mode_outlined,
                  AppThemePreference.dark => Icons.dark_mode_outlined,
                }, size: 16),
                label: Text(switch (preference) {
                  AppThemePreference.system => 'حسب النظام',
                  AppThemePreference.light => 'فاتح',
                  AppThemePreference.dark => 'داكن',
                }),
                selected: value == preference,
                selectedColor: context.mishkat.primarySoft,
                backgroundColor: context.mishkat.surface,
                checkmarkColor: context.mishkat.primary,
                labelStyle: TextStyle(
                  color: value == preference
                      ? context.mishkat.primary
                      : context.mishkat.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) =>
                    context.read<SettingsCubit>().setWidgetTheme(preference),
              ),
          ],
        ),
      ],
    ),
  );
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
                'مشكاة على شاشتك',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isIOS
                    ? 'الصلاة والقرآن والذكر على شاشتك، والصلاة القادمة على شاشة القفل.'
                    : 'وردك وذكرك وصلاتك، أقرب إليك. خمس إضافات تعمل ببياناتك المحفوظة.',
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

enum _GalleryFilter {
  all('الكل'),
  quran('القرآن'),
  dhikr('الذكر والتسبيح'),
  prayer('الصلاة والقبلة');

  const _GalleryFilter(this.label);
  final String label;
}

String _widgetTitle(MishkatHomeWidget widget) => switch (widget) {
  MishkatHomeWidget.prayerTimes => 'مواقيت الصلاة',
  MishkatHomeWidget.qibla => 'بوصلة القبلة',
  MishkatHomeWidget.adhkar => 'ذِكر اليوم',
  MishkatHomeWidget.wird => 'الورد اليومي',
  MishkatHomeWidget.tasbih => 'المسبحة',
};

enum _WidgetVisualKind { prayer, qibla, adhkar, wird, tasbih }

extension on _WidgetVisualKind {
  IconData get icon => switch (this) {
    _WidgetVisualKind.prayer => Icons.mosque_rounded,
    _WidgetVisualKind.qibla => Icons.explore_rounded,
    _WidgetVisualKind.adhkar => Icons.auto_awesome_rounded,
    _WidgetVisualKind.wird => Icons.menu_book_rounded,
    _WidgetVisualKind.tasbih => Icons.blur_circular_rounded,
  };

  Color accent(bool isDark) => switch (this) {
    _WidgetVisualKind.wird =>
      isDark ? const Color(0xFFA9D9CC) : const Color(0xFF486B65),
    _WidgetVisualKind.tasbih =>
      isDark ? const Color(0xFFD7B8EE) : const Color(0xFF725387),
    _WidgetVisualKind.prayer =>
      isDark ? const Color(0xFF8ED9BD) : const Color(0xFF276C5D),
    _WidgetVisualKind.qibla =>
      isDark ? const Color(0xFFF0CE7D) : const Color(0xFF8A6726),
    _WidgetVisualKind.adhkar =>
      isDark ? const Color(0xFFE5BFA4) : const Color(0xFF8B5D43),
  };

  Color soft(bool isDark) => switch (this) {
    _WidgetVisualKind.wird =>
      isDark ? const Color(0xFF213B33) : const Color(0xFFE3EEE7),
    _WidgetVisualKind.tasbih =>
      isDark ? const Color(0xFF37283F) : const Color(0xFFF0E6F7),
    _WidgetVisualKind.prayer =>
      isDark ? const Color(0xFF1C3830) : const Color(0xFFE3F0EB),
    _WidgetVisualKind.qibla =>
      isDark ? const Color(0xFF3A3020) : const Color(0xFFF4ECD9),
    _WidgetVisualKind.adhkar =>
      isDark ? const Color(0xFF392A25) : const Color(0xFFF4E8E0),
  };

  List<Color> stageGradient(bool isDark) => switch (this) {
    _WidgetVisualKind.wird =>
      isDark
          ? const [Color(0xFF14251F), Color(0xFF21352D)]
          : const [Color(0xFFEDF3EE), Color(0xFFE2ECE5)],
    _WidgetVisualKind.tasbih =>
      isDark
          ? const [Color(0xFF211A29), Color(0xFF30223B)]
          : const [Color(0xFFF7F0FC), Color(0xFFEEE4F5)],
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
    final compact = kind == _WidgetVisualKind.tasbih;

    if (compact) {
      return MishkatCard(
        padding: const EdgeInsets.all(12),
        borderColor: accent.withValues(alpha: isDark ? .2 : .13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                preview,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(kind.icon, color: accent, size: 19),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.mishkat.textSecondary,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        sizeLabel,
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (installed) ...[
                        const SizedBox(height: 8),
                        _InstalledBadge(accent: accent),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _AddWidgetButton(
              accent: accent,
              softColor: kind.soft(isDark),
              installed: installed,
              loading: loading,
              onPressed: onAdd,
            ),
          ],
        ),
      );
    }

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
                      const SizedBox(height: 8),
                      Text(
                        sizeLabel,
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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

class _LockScreenPrayerCard extends StatelessWidget {
  const _LockScreenPrayerCard({
    required this.state,
    required this.isIOS,
    required this.onInstructions,
  });

  final HomeState state;
  final bool isIOS;
  final VoidCallback onInstructions;

  @override
  Widget build(BuildContext context) {
    final next = state.schedule?.next;
    final preference = context
        .watch<SettingsCubit>()
        .state
        .settings
        .widgetTheme;
    final isDark = isIOS || preference == AppThemePreference.system
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : preference == AppThemePreference.dark;
    final foreground = isDark
        ? const Color(0xFFF3F8F5)
        : const Color(0xFF24463B);
    return MishkatCard(
      key: const ValueKey('lock-screen-prayer-card'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: context.mishkat.primary,
                size: 21,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'الصلاة على شاشة القفل',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            isIOS
                ? 'الصلاة القادمة ووقتها دون فتح التطبيق. اختر الشكل المستطيل للعداد المتبقي بالثواني.'
                : 'الصلاة القادمة من مواقيت تطبيقك، على الأجهزة التي تدعم ودجت شاشة القفل.',
            style: TextStyle(
              color: context.mishkat.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            key: const ValueKey('lock-screen-prayer-preview'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF20392F) : const Color(0xFFECF2EF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: foreground.withValues(alpha: .16)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        next == null ? 'حدّد موقعك في مشكاة' : 'الصلاة القادمة',
                        style: TextStyle(
                          color: foreground.withValues(alpha: .7),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        next?.name ?? '—',
                        style: TextStyle(
                          color: foreground,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        AppFormatters.time(next?.at),
                        style: TextStyle(
                          color: foreground.withValues(alpha: .8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'متبقي',
                        style: TextStyle(
                          color: foreground.withValues(alpha: .7),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (next == null)
                        Text(
                          '—',
                          style: TextStyle(color: foreground, fontSize: 20),
                        )
                      else
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: NextPrayerCountdown(
                              key: const ValueKey(
                                'lock-screen-prayer-countdown',
                              ),
                              targetTime: next.at,
                              textStyle: TextStyle(
                                color: foreground,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isIOS
                ? 'المظهر يتبع شاشة القفل'
                : 'معاينة مختصرة · المظهر حسب اختيارك للودجت',
            style: TextStyle(
              color: context.mishkat.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('lock-screen-prayer-instructions'),
            onPressed: onInstructions,
            icon: const Icon(Icons.add_to_photos_outlined, size: 18),
            label: const Text(
              'طريقة الإضافة إلى شاشة القفل',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
    return SizedBox(
      key: const ValueKey('prayer-wide-preview'),
      height: 180,
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
                            if (next == null)
                              Text('—', style: TextStyle(color: accent))
                            else
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: NextPrayerCountdown(
                                  key: const ValueKey(
                                    'widget-prayer-countdown',
                                  ),
                                  targetTime: next.at,
                                  textStyle: TextStyle(
                                    color: accent,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
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
    final bearing = result?.bearing ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gold = isDark ? const Color(0xFFF1D38A) : const Color(0xFF926C24);
    final primaryText = isDark
        ? const Color(0xFFF4FAF7)
        : const Color(0xFF17362F);
    final secondaryText = isDark
        ? const Color(0xFFB7D0C7)
        : const Color(0xFF60716B);
    return SizedBox.square(
      dimension: 190,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: isDark
                ? const [Color(0xFF17382F), Color(0xFF0C211B)]
                : const [Color(0xFFF7FBF9), Color(0xFFEAF3EF)],
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
                      color: secondaryText.withValues(alpha: .2),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: gold.withValues(alpha: .07),
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
                          color: secondaryText.withValues(alpha: .1),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          'ش',
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'مِشكاة • القبلة',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: secondaryText,
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
                        ? 'الشمال'
                        : '${result.bearing.round()}° من الشمال',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result == null
                        ? 'افتح مشكاة لتحديد موقعك'
                        : '${result.distanceKm.round()} كم · اضغط للبوصلة الحية',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: secondaryText, fontSize: 9.5),
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
    return SizedBox(
      height: 180,
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
                        MishkatNavigationIcons.forward,
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

class _WirdWidgetPreview extends StatelessWidget {
  const _WirdWidgetPreview({required this.content});
  final WirdWidgetContent content;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = isDark ? const Color(0xFF6CD6A0) : const Color(0xFF278859);
    final primary = isDark ? const Color(0xFFF3F8F5) : const Color(0xFF17362F);
    final secondary = isDark
        ? const Color(0xFFADBBB5)
        : const Color(0xFF60716B);
    final hasPlan = content.completedPages + content.remainingPages > 0;
    return SizedBox(
      key: const ValueKey('wird-wide-preview'),
      height: 180,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF152923) : const Color(0xFFF2F7F3),
          borderRadius: MishkatRadius.brXl,
          border: Border.all(color: green.withValues(alpha: .2)),
          boxShadow: MishkatShadows.elevated(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_rounded, size: 14, color: green),
                const SizedBox(width: 6),
                Text(
                  'مِشكاة • الختمة',
                  style: TextStyle(
                    color: green,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    content.name,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: secondary,
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasPlan ? 'وردك الحالي' : 'رحلتك مع القرآن',
                        style: TextStyle(color: secondary, fontSize: 9),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          content.pages,
                          maxLines: 1,
                          style: TextStyle(
                            color: primary,
                            fontSize: 22,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        content.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: secondary, fontSize: 9),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Semantics(
                  label: content.progressLabel,
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        hasPlan
                            ? '${widgetDigits((content.progress * 100).round())}٪'
                            : 'ابدأ',
                        style: TextStyle(
                          color: green,
                          fontSize: hasPlan ? 34 : 27,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasPlan ? 'من الختمة' : 'ختمتك اليوم',
                        style: TextStyle(color: secondary, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    key: const ValueKey('widget-wird-progress'),
                    value: content.progress,
                    minHeight: 5,
                    backgroundColor: green.withValues(alpha: .16),
                    color: green,
                    semanticsLabel: 'تقدم الختمة',
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        hasPlan ? content.completedLabel : 'خطوة صغيرة كل يوم',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: secondary, fontSize: 10),
                      ),
                    ),
                    if (hasPlan)
                      Text(
                        content.remainingLabel,
                        style: TextStyle(
                          color: green,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TasbihWidgetPreview extends StatelessWidget {
  const _TasbihWidgetPreview({required this.content});
  final TasbihWidgetContent content;

  @override
  Widget build(BuildContext context) {
    final accent = _WidgetVisualKind.tasbih.accent(
      Theme.of(context).brightness == Brightness.dark,
    );
    return _CompactWidgetFrame(
      key: const ValueKey('tasbih-compact-preview'),
      kind: _WidgetVisualKind.tasbih,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            content.dhikr,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
          SizedBox.square(
            dimension: 83,
            child: CustomPaint(
              painter: _TasbihRingPainter(
                progress: content.progress,
                color: accent,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          content.count,
                          style: const TextStyle(
                            fontSize: 29,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        content.target,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 8, height: 1.2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Text(
            content.today,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: accent.withValues(alpha: .8)),
          ),
        ],
      ),
    );
  }
}

class _TasbihRingPainter extends CustomPainter {
  const _TasbihRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 4;
    final track = Paint()..color = color.withValues(alpha: .18);
    for (var bead = 0; bead < 33; bead++) {
      final angle = -math.pi / 2 + bead / 33 * math.pi * 2;
      canvas.drawCircle(
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        1.6,
        track,
      );
    }
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress.clamp(0, 1) * math.pi * 2,
      false,
      Paint()
        ..color = color
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_TasbihRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _CompactWidgetFrame extends StatelessWidget {
  const _CompactWidgetFrame({
    super.key,
    required this.kind,
    required this.child,
  });
  final _WidgetVisualKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWird = kind == _WidgetVisualKind.wird;
    final accent = kind.accent(isDark);
    return Container(
      width: 156,
      height: 156,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark
            ? (isWird ? const Color(0xFF152923) : const Color(0xFF271E30))
            : (isWird ? const Color(0xFFF2F7F3) : const Color(0xFFF8F3FC)),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: accent.withValues(alpha: .17)),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: accent, fontFamily: 'Cairo'),
        child: child,
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
                ? 'يعمل عداد الصلاة بالثواني، ويتولى النظام تحديث المحتوى. سهم القبلة ثابت بالنسبة للشمال؛ البوصلة الحية متاحة بلمسة داخل التطبيق.'
                : 'يعمل عداد الصلاة بالثواني وتتجدد المواقيت تلقائيًا. سهم القبلة ثابت بالنسبة للشمال؛ اضغط لفتح البوصلة الحية داخل التطبيق.',
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
