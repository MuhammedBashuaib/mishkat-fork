import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/services/local_notification_service.dart';
import '../../../../core/services/home_widget_service.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../../adhkar/presentation/cubit/adhkar_cubit.dart';
import '../../../adhkar/presentation/pages/adhkar_page.dart';
import '../../../adhkar/presentation/pages/adhkar_reader_page.dart';
import '../../../home/presentation/pages/home_page.dart';
import '../../../khatma/presentation/cubit/khatma_cubit.dart';
import '../../../library/presentation/pages/library_page.dart';
import '../../../library/presentation/cubit/library_cubit.dart';
import '../../../library/presentation/cubit/library_state.dart';
import '../../../qibla/presentation/pages/qibla_page.dart';
import '../../../quran/presentation/pages/quran_page.dart';
import '../../../quran/presentation/pages/quran_memorization_page.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../cubit/shell_cubit.dart';

import '../widgets/mishkat_bottom_nav_bar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _onboardingPresented = false;
  bool _routingNotification = false;
  bool _routingHomeWidget = false;

  @override
  void initState() {
    super.initState();
    notificationTapPayload.addListener(_onNotificationTap);
    homeWidgetLaunchUri.addListener(_onHomeWidgetTap);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onNotificationTap();
      _onHomeWidgetTap();
    });
  }

  @override
  void dispose() {
    notificationTapPayload.removeListener(_onNotificationTap);
    homeWidgetLaunchUri.removeListener(_onHomeWidgetTap);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<SettingsCubit>().state.settings;
    if (notificationTapPayload.value != null ||
        homeWidgetLaunchUri.value != null) {
      _onboardingPresented = true;
    }
    if (!_onboardingPresented && !settings.onboardingSeen) {
      _onboardingPresented = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOnboarding());
    }
  }

  void _onNotificationTap() {
    final payload = notificationTapPayload.value;
    if (!mounted ||
        payload == null ||
        payload.isEmpty ||
        _routingNotification) {
      return;
    }
    _routingNotification = true;
    notificationTapPayload.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      final parts = payload.split(':');
      final destination = parts.first;

      switch (destination) {
        case 'adhkar':
          final route = parts.length > 1 ? parts[1] : '1';
          final categoryId =
              int.tryParse(route) ?? (route == 'evening' ? 133 : 1);
          context.read<ShellCubit>().select(3);
          context.read<AdhkarCubit>().select(categoryId);
          navigator.push(
            MaterialPageRoute<void>(builder: (_) => const AdhkarReaderPage()),
          );
          break;
        case 'khatma':
          context.read<ShellCubit>().select(4);
          context.read<LibraryCubit>().setSection(LibrarySection.khatma);
          if (parts.length > 1) {
            context.read<KhatmaCubit>().setActive(parts[1]);
          }
          break;
        case 'memorization':
          context.read<ShellCubit>().select(1);
          navigator.push(QuranMemorizationPage.route());
          break;
        case 'prayer':
        default:
          context.read<ShellCubit>().select(0);
          break;
      }
      _routingNotification = false;
    });
  }

  void _onHomeWidgetTap() {
    final uri = homeWidgetLaunchUri.value;
    if (!mounted || uri == null || _routingHomeWidget) return;
    _routingHomeWidget = true;
    homeWidgetLaunchUri.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      switch (uri.host) {
        case 'qibla':
          context.read<ShellCubit>().select(2);
          break;
        case 'adhkar':
          final hour = DateTime.now().hour;
          context.read<ShellCubit>().select(3);
          context.read<AdhkarCubit>().select(
            hour >= 16 && hour < 22
                ? 133
                : hour >= 22 || hour < 5
                ? 2
                : 1,
          );
          navigator.push(
            MaterialPageRoute<void>(builder: (_) => const AdhkarReaderPage()),
          );
          break;
        case 'prayer':
        default:
          context.read<ShellCubit>().select(0);
          break;
      }
      _routingHomeWidget = false;
    });
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ShellCubit, ShellState>(
    builder: (context, state) {
      const pages = [
        HomePage(),
        QuranPage(),
        QiblaPage(),
        AdhkarPage(),
        LibraryPage(),
      ];
      const titles = [
        'مِشكاة',
        'القرآن الكريم',
        'اتجاه القبلة',
        'الأذكار',
        'المكتبة والختمة',
      ];

      return Scaffold(
        appBar: (state.index == 0 || state.index == 2)
            ? null
            : AppBar(
                title: Text(titles[state.index]),
                leading: IconButton(
                  tooltip: 'تبديل المظهر',
                  onPressed: () {
                    final dark =
                        Theme.of(context).brightness == Brightness.dark;
                    context.read<SettingsCubit>().setTheme(
                      dark ? AppThemePreference.light : AppThemePreference.dark,
                    );
                  },
                  icon: Icon(
                    Theme.of(context).brightness == Brightness.dark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'الإعدادات',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsPage(),
                      ),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
        body: IndexedStack(index: state.index, children: pages),
        bottomNavigationBar: MishkatBottomNavBar(
          selectedIndex: state.index,
          onItemSelected: context.read<ShellCubit>().select,
        ),
      );
    },
  );

  Future<void> _showOnboarding() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MishkatRadius.xl),
        ),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          MishkatSpacing.lg,
          MishkatSpacing.md,
          MishkatSpacing.lg,
          MediaQuery.viewInsetsOf(sheetContext).bottom + MishkatSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: context.mishkat.border,
                  borderRadius: BorderRadius.circular(MishkatRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: MishkatSpacing.lg),
            Text(
              'مرحبًا بك في مشكاة',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.mishkat.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: MishkatSpacing.xs),
            Text(
              'ابدأ بمواقيت مدينتك',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: MishkatSpacing.sm),
            Text(
              'نستخدم موقعك لحساب الصلاة والقبلة بدقة، ثم نحتفظ به على جهازك فقط دون إرساله لأي خادم.',
              style: TextStyle(
                fontSize: 14,
                color: context.mishkat.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: MishkatSpacing.lg),
            Container(
              padding: const EdgeInsets.all(MishkatSpacing.base),
              decoration: BoxDecoration(
                color: context.mishkat.primarySoft,
                borderRadius: BorderRadius.circular(MishkatRadius.md),
                border: Border.all(color: context.mishkat.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: context.mishkat.primary,
                    size: 22,
                  ),
                  const SizedBox(width: MishkatSpacing.md),
                  Expanded(
                    child: Text(
                      'تُحسب المواقيت والقبلة بالكامل على جهازك دون اتصال.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.mishkat.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MishkatSpacing.lg),
            MishkatPrimaryButton(
              onPressed: () async {
                await context.read<SettingsCubit>().useCurrentLocation();
                if (!mounted) return;
                if (sheetContext.mounted &&
                    context
                        .read<SettingsCubit>()
                        .state
                        .settings
                        .onboardingSeen) {
                  Navigator.pop(sheetContext);
                }
              },
              icon: const Icon(Icons.my_location_rounded),
              label: 'استخدام موقعي الحالي',
            ),
            const SizedBox(height: MishkatSpacing.sm),
            OutlinedButton(
              onPressed: () async {
                await context.read<SettingsCubit>().skipOnboarding();
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
              child: const Text('سأختار مدينتي لاحقًا'),
            ),
          ],
        ),
      ),
    );
  }
}
