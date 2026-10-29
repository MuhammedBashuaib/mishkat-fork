import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../../adhkar/data/models/adhkar_models.dart';
import '../../../adhkar/presentation/cubit/adhkar_cubit.dart';
import '../../../adhkar/presentation/cubit/adhkar_state.dart';
import '../../../adhkar/presentation/pages/adhkar_reader_page.dart';
import '../../../adhkar/presentation/widgets/dua_editor_sheet.dart';
import '../../../khatma/presentation/cubit/khatma_cubit.dart';
import '../../../khatma/presentation/cubit/khatma_state.dart';
import '../../../home_widgets/presentation/pages/home_widgets_page.dart';
import '../../../prayer_times/domain/models/prayer_models.dart';
import '../../../quran/presentation/cubit/quran_cubit.dart';
import '../../../quran/presentation/pages/quran_reader_page.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../tasbih/presentation/cubit/tasbih_cubit.dart';
import '../../../tasbih/presentation/cubit/tasbih_state.dart';
import '../../../tasbih/presentation/pages/tasbih_page.dart';
import '../cubit/home_cubit.dart';
import '../cubit/home_state.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      buildWhen: (previous, current) =>
          previous.schedule != current.schedule ||
          previous.now.day != current.now.day,
      builder: (context, state) {
        final settings = context.watch<SettingsCubit>().state.settings;
        final now = state.now;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: ListView(
              key: const PageStorageKey('home-page-scroll'),
              padding: MishkatSpacing.page,
              children: [
                const _HomeAppBar(),
                const SizedBox(height: MishkatSpacing.xl),
                _CalmDayIntro(
                  now: now,
                  hijriOffset: settings.hijriOffset,
                  city: settings.city,
                ),
                const SizedBox(height: MishkatSpacing.lg),
                if (state.schedule == null)
                  _LocationPrompt(
                    onTap: context.read<SettingsCubit>().useCurrentLocation,
                  )
                else ...[
                  _NextPrayerHero(schedule: state.schedule!),
                  const SizedBox(height: MishkatSpacing.lg),
                  _DailyFocusCard(now: now),
                  const SizedBox(height: MishkatSpacing.xl),
                  _PrayerScheduleSection(
                    schedule: state.schedule!,
                    settings: settings,
                  ),
                  const SizedBox(height: MishkatSpacing.xl),
                  const _MyDuasSection(),
                  const SizedBox(height: MishkatSpacing.xxl),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Home App Bar
// ─────────────────────────────────────────────────────────────────────────────
class _HomeAppBar extends StatelessWidget {
  const _HomeAppBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Brand Mark + Title
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 26),
            const SizedBox(width: MishkatSpacing.sm),
            Text(
              'مِشكاة',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const Spacer(),
        MishkatIconButton(
          tooltip: 'ودجت مشكاة',
          icon: const Icon(Icons.widgets_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const HomeWidgetsPage()),
          ),
        ),
        const SizedBox(width: MishkatSpacing.xs),
        MishkatIconButton(
          tooltip: 'الإعدادات',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
          ),
        ),
      ],
    );
  }
}

class _CalmDayIntro extends StatelessWidget {
  const _CalmDayIntro({
    required this.now,
    required this.hijriOffset,
    required this.city,
  });

  final DateTime now;
  final int hijriOffset;
  final String city;

  @override
  Widget build(BuildContext context) {
    final greeting = now.hour < 12
        ? 'صباح هادئ'
        : now.hour < 18
        ? 'نهارك مبارك'
        : 'مساء هادئ';
    final hijri = AppFormatters.hijriDate(
      now,
      offset: hijriOffset,
    ).split('،').last.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: MishkatSpacing.xs),
        Wrap(
          spacing: MishkatSpacing.sm,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              hijri,
              style: TextStyle(
                color: context.mishkat.gold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text('•', style: TextStyle(color: context.mishkat.border)),
            Text(
              city.isEmpty ? 'حدّد موقعك' : city,
              style: TextStyle(
                color: context.mishkat.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// A single, contextual daily focus replaces the former stack of competing cards.
class _DailyFocusCard extends StatelessWidget {
  const _DailyFocusCard({required this.now});

  final DateTime now;

  ({String title, String subtitle, IconData icon, int categoryId})
  get _adhkarMoment {
    if (now.hour >= 5 && now.hour < 12) {
      return (
        title: 'أذكار الصباح',
        subtitle: 'ابدأ يومك بذكر هادئ',
        icon: Icons.wb_sunny_outlined,
        categoryId: 1,
      );
    }
    if (now.hour >= 16 && now.hour < 22) {
      return (
        title: 'أذكار المساء',
        subtitle: 'اختم يومك بالسكينة',
        icon: Icons.wb_twilight_rounded,
        categoryId: 133,
      );
    }
    if (now.hour >= 22 || now.hour < 5) {
      return (
        title: 'أذكار النوم',
        subtitle: 'حصّن ليلتك قبل النوم',
        icon: Icons.nights_stay_outlined,
        categoryId: 2,
      );
    }
    return (
      title: 'ذكر قصير',
      subtitle: 'لحظة ذكر تعيد لك هدوءك',
      icon: Icons.auto_awesome_outlined,
      categoryId: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final moment = _adhkarMoment;
    final colors = context.mishkat;

    return BlocBuilder<KhatmaCubit, KhatmaState>(
      builder: (context, khatmaState) {
        final quranState = context.watch<QuranCubit>().state;
        final active = khatmaState.active;
        final page = quranState.currentPage;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'وردك الآن',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: MishkatSpacing.sm),
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: MishkatRadius.brLg,
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Column(
                children: [
                  _FocusRow(
                    icon: moment.icon,
                    title: moment.title,
                    subtitle: moment.subtitle,
                    emphasized: true,
                    onTap: () {
                      context.read<AdhkarCubit>().select(moment.categoryId);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdhkarReaderPage(),
                        ),
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 68,
                    color: colors.borderSubtle,
                  ),
                  _FocusRow(
                    icon: Icons.menu_book_outlined,
                    title: active?.name ?? 'تابع تلاوتك',
                    subtitle: active != null
                        ? 'صفحة $page · ورد اليوم ${active.dailyPages} صفحات'
                        : 'أكمل من صفحة $page',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => QuranReaderPage(
                          initialGlobalAyah: quranState.lastRead?.global,
                        ),
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 68,
                    color: colors.borderSubtle,
                  ),
                  BlocBuilder<TasbihCubit, TasbihState>(
                    buildWhen: (previous, current) =>
                        previous.count != current.count ||
                        previous.target != current.target ||
                        previous.dhikrId != current.dhikrId,
                    builder: (context, tasbihState) => _FocusRow(
                      icon: Icons.touch_app_outlined,
                      title: 'المسبحة',
                      subtitle: tasbihState.count == 0
                          ? 'ابدأ جلسة ذكر هادئة'
                          : '${tasbihState.dhikr.text} • ${tasbihState.count} من ${tasbihState.target}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const TasbihPage(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FocusRow extends StatelessWidget {
  const _FocusRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return InkWell(
      borderRadius: MishkatRadius.brLg,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: emphasized ? colors.primarySoft : colors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 19, color: colors.primary),
            ),
            const SizedBox(width: MishkatSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_left_rounded, size: 20, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

// The next prayer remains the only strong visual anchor on the page.
class _NextPrayerHero extends StatelessWidget {
  const _NextPrayerHero({required this.schedule});
  final PrayerSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final next = schedule.next;
    final background = context.mishkat.brandDeep;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: MishkatRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'الصلاة القادمة',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              const Spacer(),
              Text(
                'الأذان ${AppFormatters.time(next.at)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  next.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'متبقي',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  NextPrayerCountdown(targetTime: next.at),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unified prayer schedule
// ─────────────────────────────────────────────────────────────────────────────
class _PrayerScheduleSection extends StatelessWidget {
  const _PrayerScheduleSection({
    required this.schedule,
    required this.settings,
  });

  final PrayerSchedule schedule;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final cityName = settings.city.isNotEmpty ? settings.city : 'موقعك الحالي';

    return MishkatPrayerSchedule(
      schedule: schedule,
      cityName: cityName,
      onLocationTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SettingsPage(openPrayerSettings: true),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Qibla Shortcut Navigation Row
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// 8. Daily Adhkar Section (Tonal Chips + Text Action)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// 9. My Duas Section (Shortcut to Add + Latest 3 Duas)
// ─────────────────────────────────────────────────────────────────────────────
class _MyDuasSection extends StatelessWidget {
  const _MyDuasSection();

  void _openAllDuas(BuildContext context) {
    context.read<AdhkarCubit>().select(0);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AdhkarReaderPage()));
  }

  void _openAddDua(BuildContext context) {
    DuaEditorSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdhkarCubit, AdhkarState>(
      buildWhen: (previous, current) =>
          previous.customItems != current.customItems ||
          previous.progress[0] != current.progress[0],
      builder: (context, state) {
        final customItems = state.customItems;
        final colors = context.mishkat;

        if (customItems.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MishkatSectionHeader(
                title: 'أدعيتي',
                padding: const EdgeInsets.only(top: 8, bottom: 10),
                trailing: MishkatTextAction(
                  label: 'إضافة دعاء',
                  icon: Icons.add_rounded,
                  onPressed: () => _openAddDua(context),
                ),
              ),
              MishkatTonalSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.edit_note_rounded,
                        size: 24,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد أدعية مضافة بعد',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'احفظ أدعيتك الخاصة والمأثورة للرجوع إليها وترديدها.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    MishkatSecondaryAction(
                      onPressed: () => _openAddDua(context),
                      icon: const Icon(Icons.add_rounded),
                      label: 'إضافة أول دعاء',
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final totalCount = customItems.length;
        final latestCount = math.min(3, totalCount);
        // Latest 3 duas in reverse chronological order (newest first)
        final latestEntries = <({int originalIndex, DhikrItem item})>[
          for (var i = totalCount - 1; i >= totalCount - latestCount; i--)
            (originalIndex: i, item: customItems[i]),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MishkatSectionHeader(
              title: 'أدعيتي',
              padding: const EdgeInsets.only(top: 8, bottom: 10),
              trailing: MishkatTextAction(
                label: 'إضافة دعاء',
                icon: Icons.add_rounded,
                onPressed: () => _openAddDua(context),
              ),
            ),
            for (final entry in latestEntries) ...[
              _HomeDuaCard(
                item: entry.item,
                originalIndex: entry.originalIndex,
                onTap: () => _openAllDuas(context),
              ),
              const SizedBox(height: MishkatSpacing.sm),
            ],
            if (totalCount > 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Center(
                  child: MishkatTextAction(
                    label: 'عرض جميع أدعيتي ($totalCount)',
                    icon: Icons.chevron_left_rounded,
                    onPressed: () => _openAllDuas(context),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HomeDuaCard extends StatelessWidget {
  const _HomeDuaCard({
    required this.item,
    required this.originalIndex,
    required this.onTap,
  });

  final DhikrItem item;
  final int originalIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final hasTitle = item.title.trim().isNotEmpty;
    final adhkarState = context.watch<AdhkarCubit>().state;
    final done = adhkarState.progress[0]?[originalIndex] ?? 0;
    final isCompleted = item.count > 0 && done >= item.count;

    return MishkatCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? colors.primary.withValues(alpha: 0.15)
                      : colors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.favorite_rounded,
                  size: 15,
                  color: isCompleted ? colors.primary : colors.gold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasTitle ? item.title.trim() : 'من أدعيتي',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: hasTitle ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ),
              if (item.count > 1) ...[
                MishkatPressable(
                  onTap: isCompleted
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          context.read<AdhkarCubit>().increment(
                            0,
                            originalIndex,
                          );
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? colors.primary.withValues(alpha: 0.15)
                          : colors.surfaceVariant,
                      borderRadius: MishkatRadius.brPill,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCompleted
                              ? Icons.check_rounded
                              : Icons.touch_app_outlined,
                          size: 12,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isCompleted
                              ? 'مكتمل'
                              : (done > 0
                                    ? '$done / ${item.count}'
                                    : '${item.count}×'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              MishkatIconButton(
                tooltip: 'نسخ الدعاء',
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: item.text));
                  if (context.mounted) {
                    context.showMessage('تم نسخ الدعاء.');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.text.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              height: 1.7,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 10. Daily Wird / Quran Moment (Clear Visual Hierarchy)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Location Prompt Banner (if no location is configured)
// ─────────────────────────────────────────────────────────────────────────────
class _LocationPrompt extends StatelessWidget {
  const _LocationPrompt({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.mishkat.brandDeep,
        borderRadius: MishkatRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ابدأ بمواقيت مدينتك',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'نحتاج موقعك لحساب أوقات الصلاة والقبلة محلياً على جهازك.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          MishkatPrimaryAction(
            onPressed: onTap,
            icon: const Icon(Icons.my_location_rounded),
            label: 'استخدام موقعي الحالي',
          ),
        ],
      ),
    );
  }
}
