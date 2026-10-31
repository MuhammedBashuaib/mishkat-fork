import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../data/models/memorization_plan.dart';
import '../../data/models/quran_models.dart';
import '../cubit/quran_memorization_cubit.dart';

/// A short, calm flow for creating or editing one sustainable Hifz plan.
class MemorizationPlanPage extends StatefulWidget {
  const MemorizationPlanPage({
    super.key,
    required this.quranData,
    this.existingPlan,
  });

  final QuranData quranData;
  final MemorizationPlan? existingPlan;

  static Route<bool> route({
    required QuranData quranData,
    MemorizationPlan? existingPlan,
  }) {
    return MaterialPageRoute<bool>(
      builder: (_) => MemorizationPlanPage(
        quranData: quranData,
        existingPlan: existingPlan,
      ),
    );
  }

  @override
  State<MemorizationPlanPage> createState() => _MemorizationPlanPageState();
}

class _MemorizationPlanPageState extends State<MemorizationPlanPage> {
  late int _selectedSurah;
  late int _startAyah;
  late int _endAyah;
  late int _dailyTarget;
  late bool _customRange;
  late final TextEditingController _titleController;

  bool _reminderEnabled = true;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 7, minute: 0);
  bool _isSaving = false;

  static const Map<int, ({String title, String subtitle})> _targetOptions = {
    3: (title: '3 آيات', subtitle: 'بداية خفيفة'),
    5: (title: '5 آيات', subtitle: 'ورد متوازن'),
    8: (title: 'نصف صفحة', subtitle: 'تقريباً'),
    15: (title: 'صفحة', subtitle: 'تقريباً'),
  };

  @override
  void initState() {
    super.initState();
    final plan = widget.existingPlan;
    if (plan != null) {
      final start = widget.quranData.pointForGlobal(plan.startGlobalAyah);
      final end = widget.quranData.pointForGlobal(plan.endGlobalAyah);
      _selectedSurah = plan.surah ?? start.surah;
      _startAyah = start.ayah;
      _endAyah = end.ayah;
      _dailyTarget = plan.dailyTarget;
      final chapter = widget.quranData.chapter(_selectedSurah);
      _customRange = _startAyah != 1 || _endAyah != chapter.ayahs.length;
      _titleController = TextEditingController(text: plan.title);
      _reminderEnabled = plan.reminderHour != null;
      _reminderTime = TimeOfDay(
        hour: plan.reminderHour ?? 7,
        minute: plan.reminderMinute ?? 0,
      );
    } else {
      _selectedSurah = 1;
      final chapter = widget.quranData.chapter(_selectedSurah);
      _startAyah = 1;
      _endAyah = chapter.ayahs.length;
      _dailyTarget = 5;
      _customRange = false;
      _titleController = TextEditingController(
        text: 'حفظ سورة ${chapter.name}',
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _onSurahChanged(int surahNumber) {
    setState(() {
      _selectedSurah = surahNumber;
      final chapter = widget.quranData.chapter(surahNumber);
      _startAyah = 1;
      _endAyah = chapter.ayahs.length;
      _customRange = false;
      _titleController.text = 'حفظ سورة ${chapter.name}';
    });
  }

  void _setCustomRange(bool value) {
    setState(() {
      _customRange = value;
      if (!value) {
        _startAyah = 1;
        _endAyah = widget.quranData.chapter(_selectedSurah).ayahs.length;
      }
    });
  }

  Future<void> _selectReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null && mounted) setState(() => _reminderTime = picked);
  }

  Future<void> _savePlan() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال اسم الخطة'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final chapter = widget.quranData.chapter(_selectedSurah);
      final startGlobal = chapter.globalStart + _startAyah - 1;
      final endGlobal = chapter.globalStart + _endAyah - 1;
      final cubit = context.read<QuranMemorizationCubit>();
      final plan = widget.existingPlan;
      final reminder = _reminderEnabled ? _reminderTime : null;

      if (reminder != null) {
        final settings = context.read<SettingsCubit>();
        if (!settings.state.settings.notificationsEnabled) {
          await settings.setNotificationsEnabled(true);
        }
      }

      if (plan == null) {
        await cubit.createPlan(
          title: title,
          surah: _selectedSurah,
          startGlobalAyah: startGlobal,
          endGlobalAyah: endGlobal,
          dailyTarget: _dailyTarget,
          reminderTime: reminder,
        );
      } else {
        await cubit.updatePlan(
          plan.copyWith(
            title: title,
            surah: _selectedSurah,
            startGlobalAyah: startGlobal,
            endGlobalAyah: endGlobal,
            dailyTarget: _dailyTarget,
            reminderHour: reminder?.hour,
            reminderMinute: reminder?.minute,
            clearReminder: reminder == null,
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            plan == null ? 'تم إنشاء خطة الحفظ' : 'تم حفظ تعديلات الخطة',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final chapter = widget.quranData.chapter(_selectedSurah);
    final ayahCount = (_endAyah - _startAyah + 1).clamp(
      1,
      chapter.ayahs.length,
    );
    final estimatedDays = (ayahCount / _dailyTarget).ceil();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingPlan == null ? 'خطة حفظ جديدة' : 'تعديل خطة الحفظ',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
          children: [
            Text(
              'خطة بسيطة يمكنك الاستمرار عليها',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.3),
            ),
            const SizedBox(height: 4),
            Text(
              'اختر ما ستحفظ ومقداراً يناسب يومك. يمكنك تعديل الخطة لاحقاً.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: MishkatSpacing.lg),
            _PlanSection(
              number: '١',
              title: 'ماذا ستحفظ؟',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('اختر السورة'),
                  const SizedBox(height: 7),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedSurah,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.menu_book_outlined),
                    ),
                    items: widget.quranData.chapters
                        .map(
                          (item) => DropdownMenuItem<int>(
                            value: item.number,
                            child: Text(
                              '${item.number}. سورة ${item.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _onSurahChanged(value);
                    },
                  ),
                  const SizedBox(height: 14),
                  _RangeSelector(
                    customRange: _customRange,
                    onChanged: _setCustomRange,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: !_customRange
                        ? const SizedBox.shrink()
                        : Padding(
                            key: const ValueKey('range'),
                            padding: const EdgeInsets.only(top: 14),
                            child: _AyahRangeFields(
                              totalAyahs: chapter.ayahs.length,
                              startAyah: _startAyah,
                              endAyah: _endAyah,
                              onStartChanged: (value) {
                                setState(() {
                                  _startAyah = value;
                                  if (_endAyah < value) _endAyah = value;
                                });
                              },
                              onEndChanged: (value) {
                                setState(() => _endAyah = value);
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _PlanSection(
              number: '٢',
              title: 'كم تحفظ يومياً؟',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Kept for accessibility and existing test contracts.
                  const Text(
                    'الورد اليومي للآيات الجديدة',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 8.0;
                      final width = (constraints.maxWidth - gap) / 2;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final option in _targetOptions.entries)
                            SizedBox(
                              width: width,
                              child: _TargetOption(
                                title: option.value.title,
                                subtitle: option.value.subtitle,
                                selected: _dailyTarget == option.key,
                                onTap: () =>
                                    setState(() => _dailyTarget = option.key),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  if (!_targetOptions.containsKey(_dailyTarget)) ...[
                    const SizedBox(height: 10),
                    Text(
                      'وردك الحالي: $_dailyTarget آيات يومياً',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'تنتهي الخطة خلال $estimatedDays يوم تقريباً',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _PlanSection(
              number: '٣',
              title: 'تفاصيل اختيارية',
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'اسم الخطة',
                      prefixIcon: Icon(Icons.bookmark_border_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'تذكير يومي',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _reminderEnabled
                          ? 'موعده ${_reminderTime.format(context)}'
                          : 'يمكنك تفعيله لاحقاً',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    value: _reminderEnabled,
                    activeTrackColor: colors.primary,
                    onChanged: (value) {
                      setState(() => _reminderEnabled = value);
                    },
                  ),
                  if (_reminderEnabled)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _selectReminderTime,
                        icon: const Icon(Icons.schedule_rounded, size: 17),
                        label: Text(
                          'تغيير الوقت · ${_reminderTime.format(context)}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlanSummary(
                surahName: chapter.name,
                ayahCount: ayahCount,
                dailyTarget: _dailyTarget,
              ),
              const SizedBox(height: 10),
              MishkatPrimaryAction(
                onPressed: _isSaving ? null : _savePlan,
                label: widget.existingPlan == null
                    ? 'بدء وتثبيت خطة الحفظ'
                    : 'حفظ تعديلات الخطة',
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({
    required this.number,
    required this.title,
    required this.child,
  });

  final String number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: MishkatRadius.brLg,
        side: BorderSide(color: colors.border.withValues(alpha: .55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    number,
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
  );
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.customRange, required this.onChanged});
  final bool customRange;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: MishkatRadius.brMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: _RangeChoice(
              label: 'السورة كاملة',
              icon: Icons.auto_stories_outlined,
              selected: !customRange,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _RangeChoice(
              label: 'آيات محددة',
              icon: Icons.tune_rounded,
              selected: customRange,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeChoice extends StatelessWidget {
  const _RangeChoice({
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
    return Material(
      color: selected ? colors.surface : Colors.transparent,
      borderRadius: MishkatRadius.brSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: MishkatRadius.brSm,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? colors.primary : colors.textSecondary,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AyahRangeFields extends StatelessWidget {
  const _AyahRangeFields({
    required this.totalAyahs,
    required this.startAyah,
    required this.endAyah,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  final int totalAyahs;
  final int startAyah;
  final int endAyah;
  final ValueChanged<int> onStartChanged;
  final ValueChanged<int> onEndChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: startAyah,
            decoration: const InputDecoration(labelText: 'من الآية'),
            items: List.generate(totalAyahs, (index) => index + 1)
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text('$value')),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onStartChanged(value);
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('end-$startAyah-$endAyah'),
            initialValue: endAyah,
            decoration: const InputDecoration(labelText: 'إلى الآية'),
            items:
                List.generate(
                      totalAyahs - startAyah + 1,
                      (index) => startAyah + index,
                    )
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text('$value')),
                    )
                    .toList(),
            onChanged: (value) {
              if (value != null) onEndChanged(value);
            },
          ),
        ),
      ],
    );
  }
}

class _TargetOption extends StatelessWidget {
  const _TargetOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Material(
      color: selected ? colors.primarySoft : colors.surfaceVariant,
      borderRadius: MishkatRadius.brMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: MishkatRadius.brMd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: MishkatRadius.brMd,
            border: selected
                ? Border.all(color: colors.primary.withValues(alpha: .45))
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: selected ? colors.primary : colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: colors.primary,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({
    required this.surahName,
    required this.ayahCount,
    required this.dailyTarget,
  });

  final String surahName;
  final int ayahCount;
  final int dailyTarget;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.auto_stories_outlined, size: 15, color: colors.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'سورة $surahName · $ayahCount آية · $dailyTarget يومياً',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
