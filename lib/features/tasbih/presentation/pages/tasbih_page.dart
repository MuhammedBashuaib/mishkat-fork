import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../cubit/tasbih_cubit.dart';
import '../cubit/tasbih_state.dart';

class TasbihPage extends StatelessWidget {
  const TasbihPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(Icons.arrow_forward_rounded),
        tooltip: 'رجوع',
      ),
      title: const Text('المسبحة'),
      actions: [
        BlocBuilder<TasbihCubit, TasbihState>(
          buildWhen: (previous, current) =>
              previous.hapticsEnabled != current.hapticsEnabled,
          builder: (context, state) => IconButton(
            tooltip: state.hapticsEnabled ? 'إيقاف الاهتزاز' : 'تشغيل الاهتزاز',
            onPressed: context.read<TasbihCubit>().toggleHaptics,
            icon: Icon(
              state.hapticsEnabled
                  ? Icons.vibration_rounded
                  : Icons.phone_android_rounded,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: BlocBuilder<TasbihCubit, TasbihState>(
      builder: (context, state) => SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              MishkatSpacing.base,
              MishkatSpacing.md,
              MishkatSpacing.base,
              MishkatSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, constraints.maxHeight - 44),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DhikrSelector(state: state),
                  const SizedBox(height: MishkatSpacing.base),
                  _TargetSelector(state: state),
                  const SizedBox(height: MishkatSpacing.lg),
                  _CounterSurface(state: state),
                  const SizedBox(height: MishkatSpacing.base),
                  _SessionStats(state: state),
                  const SizedBox(height: MishkatSpacing.md),
                  _SessionActions(state: state),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DhikrSelector extends StatelessWidget {
  const _DhikrSelector({required this.state});

  final TasbihState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Semantics(
      button: true,
      label: 'الذكر الحالي: ${state.dhikr.text}، اضغط لتغييره',
      child: MishkatCard(
        onTap: () => _showDhikrSheet(context, state),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: colors.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: MishkatSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الذكر الحالي',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.dhikr.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: MishkatSpacing.sm),
            Icon(Icons.keyboard_arrow_down_rounded, color: colors.textMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _showDhikrSheet(
    BuildContext pageContext,
    TasbihState state,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: pageContext,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'اختر الذكر',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'عند تغيير الذكر تبدأ جلسة جديدة، ويبقى مجموعك محفوظًا.',
                    style: TextStyle(
                      color: context.mishkat.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: tasbihDhikrOptions.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 56,
                  color: context.mishkat.borderSubtle,
                ),
                itemBuilder: (context, index) {
                  final item = tasbihDhikrOptions[index];
                  final isSelected = item.id == state.dhikrId;
                  return ListTile(
                    onTap: () => Navigator.pop(context, item.id),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? context.mishkat.primarySoft
                            : context.mishkat.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSelected
                            ? Icons.check_rounded
                            : Icons.auto_awesome_outlined,
                        size: 18,
                        color: context.mishkat.primary,
                      ),
                    ),
                    title: Text(
                      item.text,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text('الهدف المقترح ${item.suggestedTarget}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && pageContext.mounted) {
      await pageContext.read<TasbihCubit>().selectDhikr(selected);
    }
  }
}

class _TargetSelector extends StatelessWidget {
  const _TargetSelector({required this.state});

  final TasbihState state;

  @override
  Widget build(BuildContext context) {
    const presets = [33, 100, 1000];
    final isCustom = !presets.contains(state.target);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'هدف الجلسة',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: MishkatSpacing.sm),
        Row(
          children: [
            for (final target in presets) ...[
              Expanded(
                child: _TargetButton(
                  label: '$target',
                  selected: state.target == target,
                  onTap: () => context.read<TasbihCubit>().setTarget(target),
                ),
              ),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: _TargetButton(
                label: isCustom ? '${state.target}' : 'مخصص',
                selected: isCustom,
                onTap: () => _showCustomTargetDialog(context, state.target),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showCustomTargetDialog(
    BuildContext pageContext,
    int current,
  ) async {
    final controller = TextEditingController(text: '$current');
    final value = await showDialog<int>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: const Text('هدف مخصص'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 4,
          decoration: const InputDecoration(
            labelText: 'عدد التسبيحات',
            hintText: 'من 1 إلى 9999',
          ),
          onSubmitted: (raw) {
            final parsed = int.tryParse(raw);
            if (parsed != null && parsed >= 1 && parsed <= 9999) {
              Navigator.pop(context, parsed);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text);
              if (parsed != null && parsed >= 1 && parsed <= 9999) {
                Navigator.pop(context, parsed);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && pageContext.mounted) {
      await pageContext.read<TasbihCubit>().setTarget(value);
    }
  }
}

class _TargetButton extends StatelessWidget {
  const _TargetButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = selected
        ? (isDark ? colors.primarySoft : colors.brandDeep)
        : colors.surface;
    final foreground = selected
        ? (isDark ? colors.primary : Colors.white)
        : colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: 'هدف $label',
      child: Material(
        color: background,
        borderRadius: MishkatRadius.brMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: MishkatRadius.brMd,
              border: Border.all(
                color: selected ? background : colors.borderSubtle,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CounterSurface extends StatelessWidget {
  const _CounterSurface({required this.state});

  final TasbihState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final diameter = math.min(MediaQuery.sizeOf(context).width - 88, 244.0);
    final onPrimary = isDark ? colors.primaryDark : Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: colors.brandDeep,
        borderRadius: MishkatRadius.brXl,
        boxShadow: MishkatShadows.elevated(context),
      ),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: state.completed
                ? Row(
                    key: const ValueKey('completed'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: onPrimary,
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        state.count == state.target
                            ? 'أتممت هدف الجلسة، تقبّل الله'
                            : 'تجاوزت هدفك بـ ${state.count - state.target}',
                        style: TextStyle(
                          color: onPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'بقي ${state.remaining} لإتمام الهدف',
                    key: const ValueKey('remaining'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
          ),
          const SizedBox(height: MishkatSpacing.md),
          Semantics(
            button: true,
            label:
                'عد التسبيح، ${state.count} من ${state.target}. اضغط للزيادة',
            child: MishkatPressable(
              scaleDown: 0.965,
              onTap: () {
                if (state.hapticsEnabled) {
                  if (state.count + 1 == state.target) {
                    HapticFeedback.heavyImpact();
                  } else {
                    HapticFeedback.selectionClick();
                  }
                }
                context.read<TasbihCubit>().increment();
              },
              child: SizedBox(
                width: diameter,
                height: diameter,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: state.progress,
                        strokeWidth: 9,
                        backgroundColor: Colors.white.withValues(alpha: 0.13),
                        valueColor: AlwaysStoppedAnimation<Color>(onPrimary),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Container(
                      width: diameter - 28,
                      height: diameter - 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(
                          alpha: isDark ? 0.08 : 0.07,
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 130),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(scale: animation, child: child),
                            child: Text(
                              '${state.count}',
                              key: ValueKey(state.count),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 58,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'اضغط للتسبيح',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: MishkatSpacing.md),
          Text(
            state.dhikr.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionStats extends StatelessWidget {
  const _SessionStats({required this.state});

  final TasbihState state;

  @override
  Widget build(BuildContext context) => MishkatCard(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
    child: Row(
      children: [
        Expanded(
          child: _StatItem(
            icon: Icons.today_rounded,
            label: 'ذكر اليوم',
            value: '${state.todayTotal}',
          ),
        ),
        _StatDivider(color: context.mishkat.borderSubtle),
        Expanded(
          child: _StatItem(
            icon: Icons.flag_outlined,
            label: 'الجولات',
            value: '${state.rounds}',
          ),
        ),
        _StatDivider(color: context.mishkat.borderSubtle),
        Expanded(
          child: _StatItem(
            icon: Icons.all_inclusive_rounded,
            label: 'الإجمالي',
            value: '${state.total}',
          ),
        ),
      ],
    ),
  );
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, size: 17, color: context.mishkat.primary),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 1),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.5, color: context.mishkat.textSecondary),
      ),
    ],
  );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 48, color: color);
}

class _SessionActions extends StatelessWidget {
  const _SessionActions({required this.state});

  final TasbihState state;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: MishkatSecondaryAction(
          onPressed: state.count == 0 ? null : context.read<TasbihCubit>().undo,
          icon: const Icon(Icons.undo_rounded),
          label: 'تراجع عن آخر ضغطة',
          isFullWidth: true,
        ),
      ),
      const SizedBox(width: MishkatSpacing.sm),
      IconButton.filledTonal(
        tooltip: 'بدء جلسة جديدة',
        onPressed: state.count == 0 ? null : () => _confirmReset(context),
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
  );

  Future<void> _confirmReset(BuildContext pageContext) async {
    final confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: const Text('بدء جلسة جديدة؟'),
        content: const Text(
          'سيعود عدّاد الجلسة إلى الصفر، وسيبقى مجموعك اليومي والتراكمي محفوظًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('بدء جلسة جديدة'),
          ),
        ],
      ),
    );
    if (confirmed == true && pageContext.mounted) {
      await pageContext.read<TasbihCubit>().reset();
    }
  }
}
