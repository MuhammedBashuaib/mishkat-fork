import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/navigation_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onComplete});

  final Future<void> Function() onComplete;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _pages = <_OnboardingData>[
    _OnboardingData(
      eyebrow: 'من نور الآية جاء الاسم',
      title: 'مِشكاة',
      description: 'رفيقك اليومي للقرآن والصلاة والذكر، في مساحة تحفظ هدوءك.',
      kind: _VisualKind.welcome,
    ),
    _OnboardingData(
      eyebrow: 'القرآن الكريم',
      title: 'وردٌ يبقى قريبًا',
      description: 'اقرأ واستمع واحفظ، ثم عُد إلى موضعك متى شئت.',
      kind: _VisualKind.quran,
    ),
    _OnboardingData(
      eyebrow: 'صلاتك وذكرك',
      title: 'يومك مرتب بهدوء',
      description: 'مواقيت واضحة، وقبلة، وأذكار ترافق صباحك ومساءك.',
      kind: _VisualKind.prayer,
    ),
    _OnboardingData(
      eyebrow: 'كل شيء جاهز',
      title: 'عبادة بهدوء، كل يوم',
      description: 'ابدأ بخطوة صغيرة اليوم، ودع مِشكاة يحفظ لك ما وصلت إليه.',
      kind: _VisualKind.journey,
    ),
  ];

  final PageController _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    HapticFeedback.lightImpact();
    try {
      await widget.onComplete();
    } catch (_) {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _next() async {
    if (_isLast) return _finish();
    HapticFeedback.selectionClick();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    await _controller.nextPage(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _isLast ? 0 : 1,
                    duration: const Duration(milliseconds: 160),
                    child: IgnorePointer(
                      ignoring: _isLast,
                      child: TextButton(
                        key: const ValueKey('onboarding-skip'),
                        onPressed: _finishing ? null : _finish,
                        child: Text(
                          'تخطّي',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: const ValueKey('onboarding-pages'),
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) => _OnboardingSlide(
                  data: _pages[index],
                  isActive: index == _index,
                ),
              ),
            ),
            _OnboardingFooter(
              index: _index,
              count: _pages.length,
              isLast: _isLast,
              finishing: _finishing,
              onNext: _next,
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.data, required this.isActive});

  final _OnboardingData data;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 700;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      namesRoute: true,
      label: '${data.title}. ${data.description}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final topPadding = compact ? 8.0 : 20.0;
          final availableHeight = constraints.maxHeight - topPadding - 12;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, topPadding, 24, 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: availableHeight.clamp(0, double.infinity),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: data.kind == _VisualKind.welcome
                    ? [_WelcomeIntroduction(data: data, compact: compact)]
                    : [
                        AnimatedSlide(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 360),
                          curve: Curves.easeOutCubic,
                          offset: isActive ? Offset.zero : const Offset(.04, 0),
                          child: AnimatedOpacity(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 280),
                            opacity: isActive ? 1 : .72,
                            child: _OnboardingVisual(
                              kind: data.kind,
                              compact: compact,
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 20 : 32),
                        Text(
                          data.eyebrow,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: context.mishkat.gold,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: MishkatSpacing.sm),
                        Text(
                          data.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(
                                fontSize: compact ? 25 : 30,
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                                letterSpacing: -.6,
                              ),
                        ),
                        const SizedBox(height: MishkatSpacing.md),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 350),
                          child: Text(
                            data.description,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: context.mishkat.textSecondary,
                                  height: 1.75,
                                ),
                          ),
                        ),
                      ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WelcomeIntroduction extends StatelessWidget {
  const _WelcomeIntroduction({required this.data, required this.compact});

  final _OnboardingData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        children: [
          Container(
            width: compact ? 62 : 72,
            height: compact ? 72 : 84,
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(40),
                bottom: Radius.circular(16),
              ),
            ),
            child: Center(child: BrandMark(size: compact ? 31 : 36)),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            data.title,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              color: colors.brandDeep,
              fontSize: compact ? 36 : 42,
              fontWeight: FontWeight.w900,
              height: 1.2,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: MishkatSpacing.xs),
          Text(
            data.eyebrow,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: colors.gold, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: compact ? 16 : 24),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 20,
              vertical: compact ? 14 : 18,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: MishkatRadius.brLg,
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Column(
              children: [
                Text(
                  '﴿ اللَّهُ نُورُ السَّمَاوَاتِ وَالْأَرْضِ ۚ\nمَثَلُ نُورِهِ كَمِشْكَاةٍ فِيهَا مِصْبَاحٌ ﴾',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: compact ? 16 : 19,
                    fontWeight: FontWeight.w600,
                    height: 1.9,
                  ),
                ),
                const SizedBox(height: MishkatSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 20, height: 1, color: colors.gold),
                    const SizedBox(width: MishkatSpacing.sm),
                    Text(
                      'سورة النور · 35',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(width: MishkatSpacing.sm),
                    Container(width: 20, height: 1, color: colors.gold),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 14 : 20),
          Text(
            data.description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.textSecondary, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _OnboardingFooter extends StatelessWidget {
  const _OnboardingFooter({
    required this.index,
    required this.count,
    required this.isLast,
    required this.finishing,
    required this.onNext,
  });

  final int index;
  final int count;
  final bool isLast;
  final bool finishing;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...List.generate(
                count,
                (item) => AnimatedContainer(
                  key: ValueKey('onboarding-dot-$item'),
                  duration: const Duration(milliseconds: 220),
                  width: item == index ? 20 : 6,
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: item == index ? colors.primary : colors.border,
                    borderRadius: MishkatRadius.brPill,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.base),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              key: const ValueKey('onboarding-primary-action'),
              onPressed: finishing ? null : onNext,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: finishing
                    ? const SizedBox.square(
                        key: ValueKey('finishing'),
                        dimension: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        key: ValueKey(isLast),
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLast
                                ? 'ابدأ رحلتك'
                                : index == 0
                                ? 'اكتشف مِشكاة'
                                : 'التالي',
                          ),
                          const SizedBox(width: MishkatSpacing.sm),
                          Icon(
                            isLast
                                ? Icons.check_rounded
                                : MishkatNavigationIcons.forward,
                            size: 19,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingVisual extends StatelessWidget {
  const _OnboardingVisual({required this.kind, required this.compact});

  final _VisualKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: 350,
        minHeight: compact ? 148 : 214,
        maxHeight: compact ? 168 : 230,
      ),
      padding: EdgeInsets.all(compact ? 16 : 24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: MishkatRadius.brXl,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: switch (kind) {
        _VisualKind.welcome => const SizedBox.shrink(),
        _VisualKind.quran => const _QuranPreview(),
        _VisualKind.prayer => const _PrayerPreview(),
        _VisualKind.journey => const _JourneyPreview(),
      },
    );
  }
}

class _QuranPreview extends StatelessWidget {
  const _QuranPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _PreviewRow(
          icon: Icons.menu_book_outlined,
          title: 'تابع تلاوتك',
          subtitle: 'من موضعك الأخير',
          trailing: 'فتح',
          emphasized: true,
        ),
        Divider(height: 1, indent: 48, color: colors.borderSubtle),
        const _PreviewRow(
          icon: Icons.headphones_outlined,
          title: 'استمع بتدبّر',
          subtitle: 'تلاوة هادئة بين يديك',
          trailing: 'استماع',
        ),
      ],
    );
  }
}

class _PrayerPreview extends StatelessWidget {
  const _PrayerPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: dark ? colors.surfaceVariant : colors.brandDeep,
        borderRadius: MishkatRadius.brLg,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.heroBorder.withValues(alpha: .75),
              borderRadius: MishkatRadius.brMd,
            ),
            child: Icon(
              Icons.nights_stay_outlined,
              color: colors.heroLabel,
              size: 22,
            ),
          ),
          const SizedBox(width: MishkatSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الصلاة القادمة',
                  style: TextStyle(
                    color: colors.heroLabel,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'المغرب',
                  style: TextStyle(
                    color: dark ? colors.textPrimary : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '6:18',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: dark ? colors.textPrimary : Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyPreview extends StatelessWidget {
  const _JourneyPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _PreviewRow(
          icon: Icons.wb_sunny_outlined,
          title: 'أذكار الصباح',
          subtitle: 'ابدأ يومك بذكر هادئ',
          trailingIcon: MishkatNavigationIcons.forward,
          emphasized: true,
        ),
        Divider(height: 1, indent: 48, color: colors.borderSubtle),
        const _PreviewRow(
          icon: Icons.explore_outlined,
          title: 'اتجاه القبلة',
          subtitle: 'واضح حين تحتاجه',
          trailingIcon: MishkatNavigationIcons.forward,
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.trailingIcon,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
  final IconData? trailingIcon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: emphasized ? colors.primarySoft : colors.surfaceMuted,
              borderRadius: MishkatRadius.brMd,
            ),
            child: Icon(icon, size: 20, color: colors.primary),
          ),
          const SizedBox(width: MishkatSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                color: colors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (trailingIcon != null)
            Icon(trailingIcon, size: 17, color: colors.textMuted),
        ],
      ),
    );
  }
}

enum _VisualKind { welcome, quran, prayer, journey }

class _OnboardingData {
  const _OnboardingData({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.kind,
  });

  final String eyebrow;
  final String title;
  final String description;
  final _VisualKind kind;
}
