import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/navigation_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/cubit/settings_state.dart';
import '../cubit/qibla_cubit.dart';
import '../cubit/qibla_state.dart';
import '../widgets/mishkat_compass_widget.dart';

/// Redesigned Production-Grade Qibla Experience for Mishkat.
///
/// Features:
/// - Distinctive visual identity with serene Islamic styling.
/// - Clear distinction between North and Qibla direction.
/// - Dynamic turn guidance, shortest-arc smooth compass rotation.
/// - Real-time alignment haptic and visual celebration.
/// - Comprehensive handling for missing location, loading, missing sensor, and calibration.
/// - Lifecycle-aware sensor management to prevent battery drain and memory leaks.
class QiblaPage extends StatefulWidget {
  const QiblaPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<QiblaPage> createState() => _QiblaPageState();
}

class _QiblaPageState extends State<QiblaPage> with WidgetsBindingObserver {
  bool _wasAligned = false;
  late final QiblaCubit _cubit;
  bool _isResumed = true;
  bool _isCurrentRoute = true;
  bool _compassSuspended = false;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<QiblaCubit>();
    _isResumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);

    // Auto-start compass on page load if location is already set
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCompass();
    });
  }

  @override
  void didUpdateWidget(covariant QiblaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) _syncCompass();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current != _isCurrentRoute) {
      _isCurrentRoute = current;
      _syncCompass();
    }
  }

  void _syncCompass() {
    if (!widget.isActive || !_isResumed || !_isCurrentRoute) {
      _wasAligned = false;
      _compassSuspended = true;
      unawaited(_cubit.stop());
    } else if (_cubit.state.bearing != null &&
        (_compassSuspended || _cubit.state.status == QiblaStatus.ready)) {
      _compassSuspended = false;
      unawaited(_cubit.start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    _isResumed = lifecycleState == AppLifecycleState.resumed;
    _syncCompass();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cubit.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<QiblaCubit, QiblaState>(
      listener: (context, state) {
        if (!widget.isActive || !_isResumed || !_isCurrentRoute) return;
        // Haptic feedback once upon entering alignment
        if (state.aligned && !_wasAligned) {
          HapticFeedback.mediumImpact();
        }
        _wasAligned = state.aligned;
      },
      builder: (context, state) {
        final settings = context.watch<SettingsCubit>().state.settings;
        final settingsStatus = context.watch<SettingsCubit>().state.status;
        final isLocating = settingsStatus == SettingsStatus.locating;

        final isPushedRoute = Navigator.canPop(context);

        final content = SafeArea(
          bottom: false,
          child: ListView(
            key: const PageStorageKey('qibla_scroll_view'),
            padding: const EdgeInsets.fromLTRB(
              MishkatSpacing.base,
              MishkatSpacing.sm,
              MishkatSpacing.base,
              100, // Bottom padding to clear floating nav bar
            ),
            children: [
              // ─────────────────────────────────────────────────────────────
              // 1. Header (الترويسة)
              // ─────────────────────────────────────────────────────────────
              _QiblaHeader(
                settings: settings,
                state: state,
                isLocating: isLocating,
                isPushedRoute: isPushedRoute,
              ),

              const SizedBox(height: MishkatSpacing.md),

              // ─────────────────────────────────────────────────────────────
              // 2. State-Specific Content
              // ─────────────────────────────────────────────────────────────
              if (!settings.hasLocation ||
                  state.status == QiblaStatus.noLocation)
                _NoLocationCard(isLocating: isLocating)
              else ...[
                // Guidance Banner
                _GuidanceBanner(state: state),

                const SizedBox(height: MishkatSpacing.md),

                // Main Compass View
                MishkatCompassWidget(
                  heading: state.heading,
                  bearing: state.bearing,
                  aligned: state.aligned,
                  accuracy: state.accuracy,
                  isListening: state.status == QiblaStatus.listening,
                ),

                const SizedBox(height: MishkatSpacing.md),

                // Metrics Row (Angle, Heading, Distance)
                _MetricsRow(state: state),

                const SizedBox(height: MishkatSpacing.base),

                // Controls: Start / Stop Compass
                _ControlsSection(state: state),

                // Sensor Unavailable Notice (if platform lacks magnetometer)
                if (state.status == QiblaStatus.unavailable ||
                    state.status == QiblaStatus.failure)
                  _SensorUnavailableCard(state: state),

                const SizedBox(height: MishkatSpacing.md),

                // Calibration & Best Practice Advice Card
                _CalibrationTipCard(state: state),
              ],
            ],
          ),
        );

        // If opened as a pushed standalone route, provide Scaffold with clean background
        if (isPushedRoute) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: content,
          );
        }

        return Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: content,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header Widget (الترويسة)
// ─────────────────────────────────────────────────────────────────────────────
class _QiblaHeader extends StatelessWidget {
  const _QiblaHeader({
    required this.settings,
    required this.state,
    required this.isLocating,
    required this.isPushedRoute,
  });

  final dynamic settings;
  final QiblaState state;
  final bool isLocating;
  final bool isPushedRoute;

  @override
  Widget build(BuildContext context) {
    final hasLoc = settings.hasLocation;
    final colors = context.mishkat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Navigation row (Back button if pushed)
        if (isPushedRoute)
          Padding(
            padding: const EdgeInsets.only(bottom: MishkatSpacing.xs),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(MishkatNavigationIcons.back),
                  tooltip: 'رجوع',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Text(
                  'رجوع',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.mishkat.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'اتجاه القبلة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: MishkatSpacing.sm),

            // Live Compass Quality Badge
            _StatusBadge(state: state),
          ],
        ),

        const SizedBox(height: 3),
        Text(
          'وجّه أعلى الهاتف نحو الكعبة المشرفة في مكة.',
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),

        const SizedBox(height: MishkatSpacing.sm),

        if (hasLoc)
          Material(
            color: colors.surfaceMuted,
            borderRadius: MishkatRadius.brMd,
            child: InkWell(
              onTap: isLocating
                  ? null
                  : context.read<SettingsCubit>().useCurrentLocation,
              borderRadius: MishkatRadius.brMd,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: MishkatRadius.brMd,
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        settings.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (isLocating)
                      SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.7,
                          color: colors.primary,
                        ),
                      )
                    else ...[
                      Text(
                        'تحديث الموقع',
                        style: TextStyle(
                          color: colors.primary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.refresh_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dynamic Guidance Banner
// ─────────────────────────────────────────────────────────────────────────────
class _GuidanceBanner extends StatelessWidget {
  const _GuidanceBanner({required this.state});
  final QiblaState state;

  @override
  Widget build(BuildContext context) {
    final delta = state.delta;
    final aligned = state.aligned;
    final isListening = state.status == QiblaStatus.listening;

    late final String title;
    late final String subtitle;
    late final IconData icon;

    if (aligned) {
      title = 'أنت الآن باتجاه القبلة مباشرة';
      subtitle = 'وجّه صلاتك ودعاءك نحو المسجد الحرام الشريف';
      icon = Icons.check_circle_rounded;
    } else if (!isListening) {
      title = 'شغّل البوصلة للبدء';
      subtitle = 'اضغط «تشغيل البوصلة» ثم أدر هاتفك حتى تتطابق الإبرة';
      icon = Icons.explore_rounded;
    } else if (delta == null) {
      title = 'جارٍ قراءة المستشعر...';
      subtitle = 'حرّك الهاتف قليلاً لمعايرة الاتجاه';
      icon = Icons.screen_rotation_alt_rounded;
    } else {
      final deg = delta.abs().round();
      if (delta > 0) {
        title = 'استدر يمينًا بمقدار $deg°';
        subtitle = 'وجّه أعلى الهاتف نحو مؤشر الكعبة المشرفة';
        icon = Icons.turn_right_rounded;
      } else {
        title = 'استدر يسارًا بمقدار $deg°';
        subtitle = 'وجّه أعلى الهاتف نحو مؤشر الكعبة المشرفة';
        icon = Icons.turn_left_rounded;
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark
        ? context.mishkat.primaryDark
        : context.mishkat.primary;
    final activeTextColor = Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(
        horizontal: MishkatSpacing.md,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: aligned ? activeBg : context.mishkat.primarySoft,
        borderRadius: BorderRadius.circular(MishkatRadius.lg),
        border: Border.all(
          color: aligned ? activeBg : context.mishkat.border,
          width: aligned ? 1.5 : 1.0,
        ),
        boxShadow: aligned
            ? [
                BoxShadow(
                  color: context.mishkat.primary.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: aligned
                  ? Colors.white.withValues(alpha: 0.2)
                  : context.mishkat.surfaceMuted,
            ),
            child: Icon(
              icon,
              size: 21,
              color: aligned ? activeTextColor : context.mishkat.primary,
            ),
          ),
          const SizedBox(width: MishkatSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: aligned
                        ? activeTextColor
                        : context.mishkat.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: aligned
                        ? activeTextColor.withValues(alpha: 0.85)
                        : context.mishkat.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metrics Row (Angle, Current Heading, Distance)
// ─────────────────────────────────────────────────────────────────────────────
class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.state});
  final QiblaState state;

  @override
  Widget build(BuildContext context) {
    final bearingText = state.bearing != null
        ? '${state.bearing!.round()}°'
        : '—';
    final headingText = state.heading != null
        ? '${state.heading!.round()}°'
        : '—';
    final distanceText = state.distanceKm != null
        ? '${state.distanceKm!.round()} كم'
        : '—';

    return MishkatCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'زاوية القبلة',
                value: bearingText,
                sublabel: 'من الشمال',
                icon: Icons.navigation_rounded,
              ),
            ),
            VerticalDivider(width: 1, color: context.mishkat.borderSubtle),
            Expanded(
              child: _MetricCard(
                label: 'اتجاه هاتفك',
                value: headingText,
                sublabel: state.status == QiblaStatus.listening
                    ? 'قراءة مباشرة'
                    : 'متوقف',
                icon: Icons.smartphone_rounded,
              ),
            ),
            VerticalDivider(width: 1, color: context.mishkat.borderSubtle),
            Expanded(
              child: _MetricCard(
                label: 'المسافة للكعبة',
                value: distanceText,
                sublabel: 'تقريبية',
                icon: Icons.place_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.sublabel,
    required this.icon,
  });

  final String label;
  final String value;
  final String sublabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: context.mishkat.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: context.mishkat.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 1),
          Text(
            sublabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: context.mishkat.textMuted),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Controls Section
// ─────────────────────────────────────────────────────────────────────────────
class _ControlsSection extends StatelessWidget {
  const _ControlsSection({required this.state});
  final QiblaState state;

  @override
  Widget build(BuildContext context) {
    if (state.status == QiblaStatus.listening) {
      return Center(
        child: MishkatTextAction(
          onPressed: context.read<QiblaCubit>().stop,
          icon: Icons.pause_circle_outline_rounded,
          label: 'إيقاف التوجيه مؤقتاً',
        ),
      );
    }

    return MishkatPrimaryAction(
      onPressed: context.read<QiblaCubit>().start,
      icon: const Icon(Icons.explore_rounded),
      label: 'ابدأ تحديد اتجاه القبلة',
      isFullWidth: true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Pill Badge (Top Right)
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});
  final QiblaState state;

  @override
  Widget build(BuildContext context) {
    late final String text;
    late final Color color;
    late final IconData icon;

    if (state.aligned) {
      text = 'متطابق مع القبلة';
      color = context.mishkat.success;
      icon = Icons.check_circle_outline_rounded;
    } else if (state.status == QiblaStatus.listening) {
      if (state.accuracy == null) {
        text = 'جارٍ القياس';
        color = context.mishkat.primary;
        icon = Icons.sensors_rounded;
      } else if (state.accuracy! < 0 || state.accuracy! > 25) {
        text = 'تحتاج معايرة';
        color = context.mishkat.warning;
        icon = Icons.screen_rotation_alt_rounded;
      } else {
        text = 'دقة ${state.accuracyLabel}';
        color = context.mishkat.primary;
        icon = Icons.sensors_rounded;
      }
    } else if (state.status == QiblaStatus.ready) {
      text = 'جاهزة للاستخدام';
      color = context.mishkat.textSecondary;
      icon = Icons.radio_button_checked_rounded;
    } else if (state.status == QiblaStatus.unavailable) {
      text = 'المستشعر غير متاح';
      color = context.mishkat.warning;
      icon = Icons.warning_amber_rounded;
    } else {
      text = 'الموقع مطلوب';
      color = context.mishkat.textMuted;
      icon = Icons.location_off_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(MishkatRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// No Location State Card
// ─────────────────────────────────────────────────────────────────────────────
class _NoLocationCard extends StatelessWidget {
  const _NoLocationCard({required this.isLocating});
  final bool isLocating;

  @override
  Widget build(BuildContext context) {
    return MishkatCard(
      padding: const EdgeInsets.all(MishkatSpacing.xl),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.mishkat.primarySoft,
            ),
            child: Icon(
              Icons.location_off_outlined,
              size: 32,
              color: context.mishkat.primary,
            ),
          ),
          const SizedBox(height: MishkatSpacing.md),
          Text(
            'تحديد الموقع مطلوب',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: MishkatSpacing.xs),
          Text(
            'نحتاج إلى إحداثيات موقعك لحساب الزاوية الجغرافية الدقيقة باتجاه المسجد الحرام بمكة المكرمة.\nتُحسب القبلة محليًا بالكامل على جهازك دون إرسال بياناتك لأي جهة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: context.mishkat.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: MishkatSpacing.lg),
          MishkatPrimaryButton(
            onPressed: isLocating
                ? null
                : context.read<SettingsCubit>().useCurrentLocation,
            icon: isLocating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.my_location_rounded),
            label: isLocating ? 'جارٍ تحديد موقعك...' : 'استخدام موقعي الحالي',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sensor Unavailable Notice Card
// ─────────────────────────────────────────────────────────────────────────────
class _SensorUnavailableCard extends StatelessWidget {
  const _SensorUnavailableCard({required this.state});
  final QiblaState state;

  @override
  Widget build(BuildContext context) {
    final bearingText = state.bearing != null
        ? '${state.bearing!.round()}°'
        : '';

    return Container(
      margin: const EdgeInsets.only(top: MishkatSpacing.md),
      padding: const EdgeInsets.all(MishkatSpacing.base),
      decoration: BoxDecoration(
        color: context.mishkat.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MishkatRadius.md),
        border: Border.all(
          color: context.mishkat.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: context.mishkat.warning,
            size: 20,
          ),
          const SizedBox(width: MishkatSpacing.md),
          Expanded(
            child: Text(
              'مستشعر البوصلة المباشر غير متوفر على هذا الجهاز.\n'
              'يمكنك الاستعانة بزاوية القبلة المحسوبة ($bearingText من الشمال الحقيقي) لتحديد الاتجاه يدويًا.',
              style: TextStyle(
                fontSize: 12.5,
                color: context.mishkat.textPrimary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Calibration Tip Card
// ─────────────────────────────────────────────────────────────────────────────
class _CalibrationTipCard extends StatelessWidget {
  const _CalibrationTipCard({required this.state});

  final QiblaState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final needsCalibration =
        state.accuracy != null && (state.accuracy! < 0 || state.accuracy! > 25);
    final accent = needsCalibration ? colors.warning : colors.primary;

    return MishkatCard(
      onTap: () => _showCalibrationTips(context),
      color: needsCalibration
          ? colors.warning.withValues(alpha: .07)
          : colors.surfaceMuted,
      borderColor: needsCalibration
          ? colors.warning.withValues(alpha: .28)
          : colors.border,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              needsCalibration
                  ? Icons.screen_rotation_alt_rounded
                  : Icons.shield_outlined,
              color: accent,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needsCalibration
                      ? 'البوصلة تحتاج إلى معايرة'
                      : 'إرشادات لدقة البوصلة',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  needsCalibration
                      ? 'حرّك الهاتف بشكل الرقم 8 لتحسين القراءة.'
                      : 'استخدم الهاتف بعيداً عن المعادن والمغناطيس.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Icon(
            MishkatNavigationIcons.forward,
            color: colors.textMuted,
            size: 20,
          ),
        ],
      ),
    );
  }

  void _showCalibrationTips(BuildContext context) {
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
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
                'لأفضل دقة للقبلة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              const _CalibrationStep(
                icon: Icons.screen_rotation_alt_rounded,
                title: 'عاير المستشعر',
                subtitle: 'حرّك الهاتف في الهواء على شكل الرقم 8 عدة مرات.',
              ),
              const SizedBox(height: 10),
              const _CalibrationStep(
                icon: Icons.phone_android_rounded,
                title: 'أمسك الهاتف بشكل مسطح',
                subtitle: 'اجعل الشاشة للأعلى ووجّه أعلى الهاتف أمامك.',
              ),
              const SizedBox(height: 10),
              const _CalibrationStep(
                icon: Icons.electrical_services_outlined,
                title: 'ابتعد عن مصادر التشويش',
                subtitle: 'تجنب المعادن والسماعات والأغطية المغناطيسية.',
              ),
              const SizedBox(height: 18),
              MishkatPrimaryAction(
                label: 'حسناً، فهمت',
                isFullWidth: true,
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalibrationStep extends StatelessWidget {
  const _CalibrationStep({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colors.primarySoft,
            borderRadius: MishkatRadius.brSm,
          ),
          child: Icon(icon, color: colors.primary, size: 19),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
