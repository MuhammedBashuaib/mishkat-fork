import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';

/// Premium Bottom Navigation Bar for Mishkat.
///
/// Features:
/// - 5 items with Qibla (القبلة) as the prominent central floating compass element.
/// - RTL-native order: [الرئيسية, القرآن, القبلة, الأذكار, المكتبة].
/// - Subtle elevation, soft shadows, rounded surfaces adhering to Islamic aesthetics.
/// - Responsive scaling supporting 320px narrow phones up to tablets.
/// - Proper Safe Area padding for notches and home indicators.
class MishkatBottomNavBar extends StatelessWidget {
  const MishkatBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final navSurface = isDark ? context.mishkat.surface : Colors.white;
    final topBorderColor = isDark
        ? context.mishkat.borderSubtle
        : context.mishkat.border;

    return Container(
      decoration: BoxDecoration(
        color: navSurface,
        border: Border(top: BorderSide(color: topBorderColor, width: 1)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : const Color(0xFF0B3D32).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: SizedBox(
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // Navigation Items Row
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Item 0: الرئيسية (Home)
                    Expanded(
                      child: _NavItem(
                        index: 0,
                        selectedIndex: selectedIndex,
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        label: 'الرئيسية',
                        onTap: () => _handleTap(0),
                      ),
                    ),

                    // Item 1: القرآن (Quran)
                    Expanded(
                      child: _NavItem(
                        index: 1,
                        selectedIndex: selectedIndex,
                        icon: Icons.menu_book_outlined,
                        selectedIcon: Icons.menu_book_rounded,
                        label: 'القرآن',
                        onTap: () => _handleTap(1),
                      ),
                    ),

                    // Item 2: Spacer slot for the floating Center Compass Button
                    const Expanded(child: SizedBox.shrink()),

                    // Item 3: الأذكار (Adhkar)
                    Expanded(
                      child: _NavItem(
                        index: 3,
                        selectedIndex: selectedIndex,
                        icon: Icons.auto_awesome_outlined,
                        selectedIcon: Icons.auto_awesome_rounded,
                        label: 'الأذكار',
                        onTap: () => _handleTap(3),
                      ),
                    ),

                    // Item 4: المكتبة (Library)
                    Expanded(
                      child: _NavItem(
                        index: 4,
                        selectedIndex: selectedIndex,
                        icon: Icons.local_library_outlined,
                        selectedIcon: Icons.local_library_rounded,
                        label: 'المكتبة',
                        onTap: () => _handleTap(4),
                      ),
                    ),
                  ],
                ),
              ),

              // Item 2: Floating Center Compass Button (القبلة)
              Positioned(
                bottom: 4,
                child: _CenterCompassButton(
                  isSelected: selectedIndex == 2,
                  onTap: () => _handleTap(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(int index) {
    if (selectedIndex != index) {
      HapticFeedback.selectionClick();
      onItemSelected(index);
    }
  }
}

/// Standard Navigation Item for regular tabs.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.selectedIndex,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final int index;
  final int selectedIndex;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  bool get isSelected => index == selectedIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark
        ? context.mishkat.primary
        : context.mishkat.primaryDark;
    final unselectedColor = context.mishkat.textSecondary;

    return Semantics(
      button: true,
      label: label,
      selected: isSelected,
      child: InkResponse(
        onTap: onTap,
        splashColor: context.mishkat.primarySoft,
        highlightColor: Colors.transparent,
        radius: 28,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon container with soft indicator pill for selected state
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? context.mishkat.primarySoft
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(MishkatRadius.pill),
              ),
              child: Icon(
                isSelected ? selectedIcon : icon,
                size: 22,
                color: isSelected ? primaryColor : unselectedColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? primaryColor : unselectedColor,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prominent Center Floating Compass Button for Qibla.
class _CenterCompassButton extends StatefulWidget {
  const _CenterCompassButton({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_CenterCompassButton> createState() => _CenterCompassButtonState();
}

class _CenterCompassButtonState extends State<_CenterCompassButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = widget.isSelected;

    // Theme-aware color choices
    final activeBg = isDark ? context.mishkat.primary : context.mishkat.primary;
    final activeIconColor = isDark ? Colors.black : Colors.white;
    final inactiveBg = context.mishkat.primarySoft;
    final inactiveIconColor = isDark
        ? context.mishkat.primary
        : context.mishkat.primary;

    return Semantics(
      button: true,
      label: 'القبلة',
      selected: isSelected,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The Elevated Circle
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? activeBg : inactiveBg,
                  border: Border.all(
                    color: isSelected
                        ? (isDark
                              ? context.mishkat.primary
                              : context.mishkat.gold)
                        : context.mishkat.border,
                    width: isSelected ? 2 : 1.5,
                  ),
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(
                        color:
                            (isDark
                                    ? context.mishkat.primary
                                    : const Color(0xFF0B3D32))
                                .withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    else
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Compass Rose Ring decoration
                      Icon(
                        Icons.explore_outlined,
                        size: 30,
                        color: isSelected
                            ? activeIconColor.withValues(alpha: 0.35)
                            : inactiveIconColor.withValues(alpha: 0.3),
                      ),
                      // Prominent Compass Needle / Arrow
                      Icon(
                        Icons.explore_rounded,
                        size: 26,
                        color: isSelected ? activeIconColor : inactiveIconColor,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'القبلة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? (isDark
                            ? context.mishkat.primary
                            : context.mishkat.primaryDark)
                      : context.mishkat.textSecondary,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
