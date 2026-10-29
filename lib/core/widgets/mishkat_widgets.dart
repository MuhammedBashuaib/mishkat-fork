import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_formatters.dart';
import '../../../features/prayer_times/domain/models/prayer_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. Living UI: Micro-interactive Pressable
// ─────────────────────────────────────────────────────────────────────────────
/// Provides subtle, calm scale feedback (0.98) on press without bouncy flashiness.
class MishkatPressable extends StatefulWidget {
  const MishkatPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.98,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final BorderRadius? borderRadius;

  @override
  State<MishkatPressable> createState() => _MishkatPressableState();
}

class _MishkatPressableState extends State<MishkatPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.scaleDown : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeInOut,
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Primary Action Button
// ─────────────────────────────────────────────────────────────────────────────
/// Deep Mishkat green background, white text, strong calm contrast, medium radius.
class MishkatPrimaryAction extends StatelessWidget {
  const MishkatPrimaryAction({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.isFullWidth = false,
    this.padding,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
  });

  final VoidCallback? onPressed;
  final String label;
  final Widget? icon;
  final bool isFullWidth;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? disabledBackgroundColor;
  final Color? disabledForegroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        backgroundColor ?? (isDark ? colors.primary : colors.brandDeep);
    final fgColor =
        foregroundColor ?? (isDark ? colors.background : Colors.white);
    final effectiveBackground = onPressed != null
        ? bgColor
        : (disabledBackgroundColor ?? colors.border);
    final effectiveForeground = onPressed != null
        ? fgColor
        : (disabledForegroundColor ?? colors.textMuted);

    final child = Material(
      color: effectiveBackground,
      borderRadius: MishkatRadius.brMd,
      elevation: 0,
      child: InkWell(
        borderRadius: MishkatRadius.brMd,
        onTap: onPressed,
        child: Padding(
          padding:
              padding ??
              const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                IconTheme(
                  data: IconThemeData(color: effectiveForeground, size: 18),
                  child: icon!,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: effectiveForeground,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final wrapped = MishkatPressable(onTap: onPressed, child: child);

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: wrapped);
    }
    return wrapped;
  }
}

/// Backwards compatibility alias for MishkatPrimaryAction.
typedef MishkatPrimaryButton = MishkatPrimaryAction;

// ─────────────────────────────────────────────────────────────────────────────
// 3. Secondary Action Button
// ─────────────────────────────────────────────────────────────────────────────
/// Transparent or tonal background, green text/icon, no heavy border.
class MishkatSecondaryAction extends StatelessWidget {
  const MishkatSecondaryAction({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.isFullWidth = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final Widget? icon;
  final bool isFullWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final child = Material(
      color: colors.primarySoft,
      borderRadius: MishkatRadius.brMd,
      child: InkWell(
        borderRadius: MishkatRadius.brMd,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                IconTheme(
                  data: IconThemeData(color: colors.primary, size: 17),
                  child: icon!,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final wrapped = MishkatPressable(onTap: onPressed, child: child);

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: wrapped);
    }
    return wrapped;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Text Action (No Surrounding Box)
// ─────────────────────────────────────────────────────────────────────────────
/// Lightweight text + optional icon action with 44px touch target.
class MishkatTextAction extends StatelessWidget {
  const MishkatTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: MishkatRadius.brSm,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 4),
                Icon(icon, size: 14, color: colors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Subtle Icon Action Button
// ─────────────────────────────────────────────────────────────────────────────
/// Soft circular/rounded tonal surface, consistent 44-48px touch target.
class MishkatIconButton extends StatelessWidget {
  const MishkatIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.backgroundColor,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final button = Material(
      color: backgroundColor ?? colors.surfaceVariant.withValues(alpha: 0.6),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: IconTheme(
              data: IconThemeData(color: color ?? colors.textPrimary, size: 20),
              child: icon,
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Navigation Shortcut Tile
// ─────────────────────────────────────────────────────────────────────────────
/// Clean navigation row for shortcuts (Qibla, reading, etc.).
class MishkatShortcutTile extends StatelessWidget {
  const MishkatShortcutTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Distinct tonal surface clearly different from page background
    // Light: soft minty tonal surface (primarySoft 65%)
    // Dark: elevated dark green container (surfaceVariant)
    final surfaceColor =
        color ??
        (isDark
            ? colors.surfaceVariant
            : colors.primarySoft.withValues(alpha: 0.65));

    return MishkatPressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: MishkatRadius.brLg,
          border: Border.all(
            color: isDark
                ? colors.border.withValues(alpha: 0.45)
                : colors.primary.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Qibla icon anchor: 42x42 circular container
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isDark
                    ? colors.primary.withValues(alpha: 0.18)
                    : colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isDark ? colors.primaryStrong : colors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: MishkatSpacing.md),
            // Title & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: colors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w400,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: MishkatSpacing.sm),
            // Correct RTL forward navigation chevron (mirrors in RTL to point left: <)
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.textSecondary.withValues(alpha: 0.7),
                  size: 22,
                ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Section Header
// ─────────────────────────────────────────────────────────────────────────────
/// Calm editorial section header with typography hierarchy.
class MishkatSectionHeader extends StatelessWidget {
  const MishkatSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.only(top: 24, bottom: 10),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                letterSpacing: -0.3,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Backwards compatibility alias for MishkatSectionHeader.
typedef SectionHeading = MishkatSectionHeader;

// ─────────────────────────────────────────────────────────────────────────────
// 8. Tonal Surface Container
// ─────────────────────────────────────────────────────────────────────────────
/// Soft surface container without harsh borders. Lets content breathe.
class MishkatTonalSurface extends StatelessWidget {
  const MishkatTonalSurface({
    super.key,
    required this.child,
    this.padding = MishkatSpacing.card,
    this.color,
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final radius = borderRadius ?? MishkatRadius.brLg;
    final bg = color ?? colors.surface;

    final content = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        boxShadow: MishkatShadows.subtle(context),
      ),
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      return MishkatPressable(
        onTap: onTap,
        borderRadius: radius,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(borderRadius: radius, onTap: onTap, child: content),
        ),
      );
    }

    return content;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 9. Card Container (Subtle Outline)
// ─────────────────────────────────────────────────────────────────────────────
class MishkatCard extends StatelessWidget {
  const MishkatCard({
    super.key,
    required this.child,
    this.padding = MishkatSpacing.card,
    this.color,
    this.borderColor,
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final radius = borderRadius ?? MishkatRadius.brLg;
    final background = color ?? colors.surface;
    final borderSide = BorderSide(
      color: borderColor ?? colors.border.withValues(alpha: 0.5),
      width: 1,
    );

    final cardMaterial = Material(
      color: background,
      shape: RoundedRectangleBorder(borderRadius: radius, side: borderSide),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(padding: padding, child: child),
      ),
    );

    final content = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: MishkatShadows.subtle(context),
      ),
      child: cardMaterial,
    );

    if (onTap != null) {
      return MishkatPressable(
        onTap: onTap,
        borderRadius: radius,
        child: content,
      );
    }

    return content;
  }
}

/// Flat surface alias.
typedef MishkatSurface = MishkatTonalSurface;

// ─────────────────────────────────────────────────────────────────────────────
// 10. Information Block (Date / Content Info Row)
// ─────────────────────────────────────────────────────────────────────────────
/// Pure content block without button borders.
class MishkatInfoRow extends StatelessWidget {
  const MishkatInfoRow({
    super.key,
    required this.primaryLabel,
    required this.primaryValue,
    required this.secondaryLabel,
    required this.secondaryValue,
    this.primaryGold = true,
  });

  final String primaryLabel;
  final String primaryValue;
  final String secondaryLabel;
  final String secondaryValue;
  final bool primaryGold;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: MishkatRadius.brLg,
        boxShadow: MishkatShadows.subtle(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primaryLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: primaryGold ? colors.gold : colors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  primaryValue,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            height: 32,
            width: 1,
            color: colors.borderSubtle,
            margin: const EdgeInsets.symmetric(horizontal: 14),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  secondaryLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  secondaryValue,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
// 11. Unified Prayer Schedule Table
// ─────────────────────────────────────────────────────────────────────────────
/// ONE unified, compact prayer timetable rather than six separate buttons.
class MishkatPrayerSchedule extends StatelessWidget {
  const MishkatPrayerSchedule({
    super.key,
    required this.schedule,
    required this.cityName,
    required this.onLocationTap,
  });

  final PrayerSchedule schedule;
  final String cityName;
  final VoidCallback onLocationTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final nextKey = schedule.next.key;
    final moments = schedule.moments;

    // Split into 2 columns of 3 rows:
    // Right col (RTL): moments 0, 1, 2 (Fajr, Shuruq, Dhuhr)
    // Left col (RTL): moments 3, 4, 5 (Asr, Maghrib, Isha)
    final col1 = moments.sublist(0, 3);
    final col2 = moments.sublist(3, 6);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: MishkatRadius.brLg,
        boxShadow: MishkatShadows.subtle(context),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row inside the card
          Row(
            children: [
              Text(
                'مواقيت اليوم',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              MishkatTextAction(
                label: cityName,
                icon: Icons.location_on_outlined,
                onPressed: onLocationTap,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: colors.borderSubtle),
          const SizedBox(height: 8),

          // 2 Columns Timetable
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    for (final moment in col1)
                      _PrayerSlot(
                        moment: moment,
                        isNext: moment.key == nextKey,
                      ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 110,
                color: colors.borderSubtle,
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
              Expanded(
                child: Column(
                  children: [
                    for (final moment in col2)
                      _PrayerSlot(
                        moment: moment,
                        isNext: moment.key == nextKey,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrayerSlot extends StatelessWidget {
  const _PrayerSlot({required this.moment, required this.isNext});

  final PrayerMoment moment;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.0),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
      decoration: BoxDecoration(
        color: isNext ? colors.primarySoft : Colors.transparent,
        borderRadius: MishkatRadius.brSm,
      ),
      child: Row(
        children: [
          if (isNext) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              moment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isNext ? FontWeight.w700 : FontWeight.w600,
                color: isNext ? colors.primary : colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            AppFormatters.time(moment.at),
            style: TextStyle(
              fontSize: 12,
              fontWeight: isNext ? FontWeight.w700 : FontWeight.w600,
              color: isNext ? colors.primaryDark : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 12. Isolated Real-Time Countdown
// ─────────────────────────────────────────────────────────────────────────────
/// Updates ticker internally without rebuilding parent HomePage.
class NextPrayerCountdown extends StatefulWidget {
  const NextPrayerCountdown({
    super.key,
    required this.targetTime,
    this.textStyle,
  });

  final DateTime targetTime;
  final TextStyle? textStyle;

  @override
  State<NextPrayerCountdown> createState() => _NextPrayerCountdownState();
}

class _NextPrayerCountdownState extends State<NextPrayerCountdown> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _computeRemaining();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant NextPrayerCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetTime != widget.targetTime) {
      _computeRemaining();
    }
  }

  void _computeRemaining() {
    final now = DateTime.now();
    final diff = widget.targetTime.difference(now);
    _remaining = diff.isNegative ? Duration.zero : diff;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final diff = widget.targetTime.difference(now);
      setState(() {
        _remaining = diff.isNegative ? Duration.zero : diff;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = _remaining.inHours.toString().padLeft(2, '0');
    final minutes = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_remaining.inSeconds % 60).toString().padLeft(2, '0');

    final defaultStyle = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      fontFamily: 'monospace',
      color: Colors.white,
    );

    return Text(
      '$hours:$minutes:$seconds',
      style: widget.textStyle ?? defaultStyle,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 13. Minimal Brand Mark
// ─────────────────────────────────────────────────────────────────────────────
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) {
    final goldColor = context.mishkat.gold;
    return Container(
      width: size * 0.75,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: goldColor, width: 2),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(size),
          bottom: Radius.circular(size * 0.22),
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.18,
        height: size * 0.45,
        decoration: BoxDecoration(
          color: goldColor,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 14. Content State Panel (Empty & Error states)
// ─────────────────────────────────────────────────────────────────────────────
class ContentStatePanel extends StatelessWidget {
  const ContentStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.mishkat.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: context.mishkat.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: context.mishkat.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
