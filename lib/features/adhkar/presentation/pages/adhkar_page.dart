import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/adhkar_models.dart';
import '../cubit/adhkar_cubit.dart';
import '../cubit/adhkar_state.dart';
import 'adhkar_reader_page.dart';
import '../../../tasbih/presentation/cubit/tasbih_cubit.dart';
import '../../../tasbih/presentation/cubit/tasbih_state.dart';
import '../../../tasbih/presentation/pages/tasbih_page.dart';

class AdhkarPage extends StatefulWidget {
  const AdhkarPage({super.key});

  @override
  State<AdhkarPage> createState() => _AdhkarPageState();
}

class _AdhkarPageState extends State<AdhkarPage> {
  static const _groups = <_AdhkarGroup>[
    _AdhkarGroup(
      label: 'يومي',
      icon: Icons.today_rounded,
      ids: [0, 1, 133, 2, 3, 27, 13, 129, 130],
    ),
    _AdhkarGroup(
      label: 'الصلاة',
      icon: Icons.mosque_outlined,
      ids: [
        6,
        7,
        10,
        11,
        12,
        13,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
        25,
        26,
        27,
        28,
        32,
        33,
        107,
      ],
    ),
    _AdhkarGroup(
      label: 'البيت والحياة',
      icon: Icons.home_outlined,
      ids: [
        4,
        5,
        8,
        9,
        14,
        15,
        16,
        17,
        29,
        30,
        31,
        61,
        62,
        63,
        64,
        65,
        66,
        67,
        68,
        69,
        70,
        71,
        72,
        73,
        74,
        75,
        76,
        77,
        78,
        79,
        80,
        81,
        84,
        85,
        86,
        87,
        88,
        89,
        90,
        91,
        92,
        93,
        94,
        106,
        108,
        109,
        110,
        111,
        112,
        113,
        114,
        122,
        123,
        127,
        132,
      ],
    ),
    _AdhkarGroup(
      label: 'الكرب والعافية',
      icon: Icons.favorite_outline_rounded,
      ids: [
        34,
        35,
        36,
        37,
        38,
        39,
        40,
        41,
        42,
        43,
        44,
        45,
        46,
        47,
        48,
        49,
        50,
        51,
        52,
        53,
        54,
        55,
        56,
        57,
        58,
        59,
        60,
        82,
        83,
        124,
        125,
        126,
        128,
      ],
    ),
    _AdhkarGroup(
      label: 'السفر',
      icon: Icons.route_outlined,
      ids: [95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105],
    ),
    _AdhkarGroup(
      label: 'الحج والعمرة',
      icon: Icons.location_on_outlined,
      ids: [115, 116, 117, 118, 119, 120, 121],
    ),
    _AdhkarGroup(
      label: 'الذكر والفضل',
      icon: Icons.auto_awesome_outlined,
      ids: [107, 108, 129, 130, 131, 132],
    ),
    _AdhkarGroup(label: 'الكل', icon: Icons.grid_view_rounded, ids: []),
  ];

  var _selectedGroup = 0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdhkarCubit, AdhkarState>(
      builder: (context, state) {
        if (state.status == AdhkarStatus.initial ||
            state.status == AdhkarStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == AdhkarStatus.failure) {
          return ContentStatePanel(
            icon: Icons.auto_awesome_outlined,
            title: 'تعذّر تحميل الأذكار',
            message: state.error ?? 'حاول مرة أخرى.',
            action: MishkatPrimaryButton(
              onPressed: context.read<AdhkarCubit>().load,
              label: 'إعادة المحاولة',
            ),
          );
        }

        final searching = state.query.trim().isNotEmpty;
        final visible = searching
            ? context.read<AdhkarCubit>().filteredCategories()
            : _categoriesForGroup(state);
        final morning = _category(state, 1);
        final evening = _category(state, 133);

        return ListView(
          key: const PageStorageKey('adhkar-index'),
          padding: MishkatSpacing.page,
          children: [
            _Header(categoryCount: state.categories.length),
            const SizedBox(height: MishkatSpacing.lg),
            TextField(
              onChanged: context.read<AdhkarCubit>().search,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'ابحث عن ذكر أو مناسبة',
              ),
            ),
            if (!searching) ...[
              const SizedBox(height: MishkatSpacing.base),
              const _TasbihShortcut(),
              const SectionHeading(
                title: 'ورد اليوم',
                padding: EdgeInsets.only(top: 24, bottom: 10),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (morning != null)
                    Expanded(
                      child: _DailyWirdCard(
                        category: morning,
                        icon: Icons.wb_sunny_outlined,
                        label: 'ابدأ صباحك',
                        progress: state.progress[morning.id] ?? const {},
                        onTap: () => _open(context, morning),
                      ),
                    ),
                  if (morning != null && evening != null)
                    const SizedBox(width: MishkatSpacing.sm),
                  if (evening != null)
                    Expanded(
                      child: _DailyWirdCard(
                        category: evening,
                        icon: Icons.dark_mode_outlined,
                        label: 'حصّن مساءك',
                        progress: state.progress[evening.id] ?? const {},
                        onTap: () => _open(context, evening),
                      ),
                    ),
                ],
              ),
              const SectionHeading(
                title: 'تصفّح حسب المناسبة',
                padding: EdgeInsets.only(top: 24, bottom: 10),
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _groups.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    return _CategoryFilterChip(
                      label: group.label,
                      icon: group.icon,
                      selected: _selectedGroup == index,
                      onTap: () => setState(() => _selectedGroup = index),
                    );
                  },
                ),
              ),
            ],
            SectionHeading(
              title: searching
                  ? '${visible.length} نتيجة'
                  : _groups[_selectedGroup].label == 'الكل'
                  ? 'جميع الأبواب'
                  : _groups[_selectedGroup].label,
              padding: const EdgeInsets.only(top: 24, bottom: 10),
            ),
            if (visible.isEmpty)
              const ContentStatePanel(
                icon: Icons.search_off_rounded,
                title: 'لا توجد نتائج',
                message: 'جرّب كلمة أقصر مثل: سفر، نوم، كرب.',
              )
            else
              for (final category in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: MishkatSpacing.sm),
                  child: _CategoryTile(
                    category: category,
                    progress: state.progress[category.id] ?? const {},
                    onTap: () => _open(context, category),
                  ),
                ),
          ],
        );
      },
    );
  }

  AdhkarCategory? _category(AdhkarState state, int id) =>
      state.categories.where((item) => item.id == id).firstOrNull;

  List<AdhkarCategory> _categoriesForGroup(AdhkarState state) {
    final group = _groups[_selectedGroup];
    if (group.ids.isEmpty) return state.allCategories;
    final ids = group.ids.where((id) => id != 1 && id != 133).toSet();
    return state.allCategories.where((item) => ids.contains(item.id)).toList();
  }

  Future<void> _open(BuildContext context, AdhkarCategory category) async {
    context.read<AdhkarCubit>().select(category.id);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const AdhkarReaderPage()),
    );
  }
}

class _TasbihShortcut extends StatelessWidget {
  const _TasbihShortcut();

  @override
  Widget build(BuildContext context) => BlocBuilder<TasbihCubit, TasbihState>(
    buildWhen: (previous, current) =>
        previous.count != current.count ||
        previous.target != current.target ||
        previous.dhikrId != current.dhikrId,
    builder: (context, state) {
      final colors = context.mishkat;
      return Semantics(
        button: true,
        label: 'فتح المسبحة الإلكترونية',
        child: MishkatCard(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const TasbihPage())),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: colors.primarySoft,
          borderColor: colors.primary.withValues(alpha: 0.18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.touch_app_outlined,
                  color: colors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: MishkatSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'المسبحة الإلكترونية',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.count == 0
                          ? 'ابدأ جلسة ذكر بعد وردك'
                          : '${state.dhikr.text} • ${state.count} من ${state.target}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MishkatSpacing.sm),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: colors.primary,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.categoryCount});
  final int categoryCount;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'حصن المسلم',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: context.mishkat.gold,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        'الأذكار والأدعية',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 4),
      Text(
        '$categoryCount بابًا موثوقًا، مرتّبة لتصل إلى ذكرك في لحظات.',
        style: TextStyle(color: context.mishkat.textSecondary, height: 1.5),
      ),
    ],
  );
}

class _AdhkarGroup {
  const _AdhkarGroup({
    required this.label,
    required this.icon,
    required this.ids,
  });
  final String label;
  final IconData icon;
  final List<int> ids;
}

class _CategoryFilterChip extends StatelessWidget {
  const _CategoryFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = selected
        ? isDark
              ? colors.primarySoft
              : colors.brandDeep
        : colors.surface;
    final foreground = selected
        ? isDark
              ? colors.primary
              : Colors.white
        : colors.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: background,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? colors.primary.withValues(alpha: isDark ? 0.45 : 0.20)
                : colors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyWirdCard extends StatelessWidget {
  const _DailyWirdCard({
    required this.category,
    required this.icon,
    required this.label,
    required this.progress,
    required this.onTap,
  });
  final AdhkarCategory category;
  final IconData icon;
  final String label;
  final Map<int, int> progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final completed = _completedItems(category, progress);
    final ratio = category.items.isEmpty
        ? 0.0
        : completed / category.items.length;
    final hasStarted = completed > 0;
    return Semantics(
      button: true,
      label: '${category.name}، $completed من ${category.items.length} مكتمل',
      child: MishkatCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        color: context.mishkat.primarySoft,
        borderColor: context.mishkat.primary.withValues(alpha: 0.18),
        child: SizedBox(
          height: 142,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: context.mishkat.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: context.mishkat.primary),
              ),
              const Spacer(),
              Text(
                category.name,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              Text(
                hasStarted
                    ? 'تابع الورد • $completed/${category.items.length}'
                    : '$label • ${category.items.length} ذكرًا',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: context.mishkat.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: MishkatRadius.brPill,
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: context.mishkat.surface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.progress,
    required this.onTap,
  });
  final AdhkarCategory category;
  final Map<int, int> progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final completed = _completedItems(category, progress);
    final hasProgress = completed > 0;
    final allDone =
        category.items.isNotEmpty && completed == category.items.length;
    return MishkatCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: allDone
                  ? context.mishkat.success.withValues(alpha: 0.13)
                  : context.mishkat.primarySoft,
              borderRadius: MishkatRadius.brMd,
            ),
            child: Icon(
              allDone
                  ? Icons.check_rounded
                  : category.custom
                  ? Icons.favorite_outline_rounded
                  : Icons.auto_awesome_outlined,
              color: allDone
                  ? context.mishkat.success
                  : context.mishkat.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: MishkatSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  hasProgress
                      ? '$completed من ${category.items.length} مكتمل'
                      : category.custom && category.items.isEmpty
                      ? 'أضف أدعيتك الخاصة'
                      : '${category.items.length} ذكرًا',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.mishkat.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (hasProgress && !allDone)
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                value: completed / category.items.length,
                strokeWidth: 3,
                backgroundColor: context.mishkat.surfaceMuted,
              ),
            )
          else
            Icon(Icons.chevron_left_rounded, color: context.mishkat.textMuted),
        ],
      ),
    );
  }
}

int _completedItems(AdhkarCategory category, Map<int, int> progress) => [
  for (var i = 0; i < category.items.length; i++)
    if ((progress[i] ?? 0) >= category.items[i].count) i,
].length;
