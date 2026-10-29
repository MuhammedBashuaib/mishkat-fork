import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../cubit/tasbih_cubit.dart';
import '../cubit/tasbih_state.dart';

class TasbihPage extends StatefulWidget {
  const TasbihPage({super.key, this.onCompletionSound});

  final VoidCallback? onCompletionSound;

  @override
  State<TasbihPage> createState() => _TasbihPageState();
}

class _TasbihPageState extends State<TasbihPage> {
  static const _completionSoundAsset = 'assets/audio/tasbih_complete.wav';

  AudioPlayer? _completionSoundPlayer;
  Future<void>? _completionSoundReady;

  @override
  void initState() {
    super.initState();
    if (widget.onCompletionSound == null) {
      final player = AudioPlayer();
      _completionSoundPlayer = player;
      _completionSoundReady = _loadCompletionSound(player);
    }
  }

  @override
  void dispose() {
    _completionSoundPlayer?.dispose();
    super.dispose();
  }

  Future<void> _loadCompletionSound(AudioPlayer player) async {
    try {
      await player.setAsset(_completionSoundAsset);
    } on Object {
      // A missing audio backend must never interrupt the counter.
    }
  }

  Future<void> _playCompletionSound() async {
    final injectedPlayer = widget.onCompletionSound;
    if (injectedPlayer != null) {
      injectedPlayer();
      return;
    }
    final player = _completionSoundPlayer;
    if (player == null) return;
    try {
      await _completionSoundReady;
      await player.seek(Duration.zero);
      await player.play();
    } on Object {
      // Keep counting even if the device cannot play the short chime.
    }
  }

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
          buildWhen: (previous, current) => previous.count != current.count,
          builder: (context, state) => IconButton(
            tooltip: 'تراجع عن آخر ضغطة',
            onPressed: state.count == 0
                ? null
                : context.read<TasbihCubit>().undo,
            icon: const Icon(Icons.undo_rounded),
          ),
        ),
        IconButton(
          tooltip: 'إعدادات المسبحة',
          onPressed: () => _showTasbihSettingsSheet(context),
          icon: const Icon(Icons.tune_rounded),
        ),
        const SizedBox(width: 2),
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
                  _CounterSurface(
                    state: state,
                    onCompletionSound: _playCompletionSound,
                  ),
                  const SizedBox(height: MishkatSpacing.base),
                  _SessionStats(state: state),
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

  static const _editCustomValue = '__edit_custom__';
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
    final options = <TasbihDhikr>[
      ...tasbihDhikrOptions,
      if (state.customDhikrText.isNotEmpty)
        TasbihDhikr(
          id: tasbihCustomDhikrId,
          text: state.customDhikrText,
          suggestedTarget: state.customDhikrTarget,
        ),
    ];
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
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: options.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 56,
                  color: context.mishkat.borderSubtle,
                ),
                itemBuilder: (context, index) {
                  final item = options[index];
                  final isSelected = item.id == state.dhikrId;
                  final isCustom = item.id == tasbihCustomDhikrId;
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
                            : isCustom
                            ? Icons.edit_note_rounded
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
                    subtitle: Text(
                      isCustom
                          ? 'ذكر مخصص · الهدف ${item.suggestedTarget}'
                          : 'الهدف المقترح ${item.suggestedTarget}',
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(context, _editCustomValue),
                icon: Icon(
                  state.customDhikrText.isEmpty
                      ? Icons.add_rounded
                      : Icons.edit_rounded,
                ),
                label: Text(
                  state.customDhikrText.isEmpty
                      ? 'إضافة ذكر مخصص'
                      : 'تعديل الذكر المخصص',
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == _editCustomValue && pageContext.mounted) {
      await _showCustomDhikrSheet(pageContext, state);
      return;
    }
    if (selected != null && pageContext.mounted) {
      await pageContext.read<TasbihCubit>().selectDhikr(selected);
    }
  }

  Future<void> _showCustomDhikrSheet(
    BuildContext pageContext,
    TasbihState state,
  ) async {
    final value = await showModalBottomSheet<_CustomDhikrValue>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _CustomDhikrSheet(
        initialText: state.customDhikrText,
        initialTarget: state.customDhikrText.isEmpty
            ? state.target
            : state.customDhikrTarget,
      ),
    );
    if (value != null && pageContext.mounted) {
      await pageContext.read<TasbihCubit>().setCustomDhikr(
        value.text,
        target: value.target,
      );
    }
  }
}

class _CustomDhikrValue {
  const _CustomDhikrValue(this.text, this.target);

  final String text;
  final int target;
}

class _CustomDhikrSheet extends StatefulWidget {
  const _CustomDhikrSheet({
    required this.initialText,
    required this.initialTarget,
  });

  final String initialText;
  final int initialTarget;

  @override
  State<_CustomDhikrSheet> createState() => _CustomDhikrSheetState();
}

class _CustomDhikrSheetState extends State<_CustomDhikrSheet> {
  static const _targetPresets = [33, 100, 1000];

  late final TextEditingController _textController;
  late final TextEditingController _targetController;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _targetController = TextEditingController(text: '${widget.initialTarget}');
  }

  @override
  void dispose() {
    _textController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.initialText.isEmpty
                        ? Icons.add_rounded
                        : Icons.edit_rounded,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: MishkatSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.initialText.isEmpty
                            ? 'إضافة ذكر مخصص'
                            : 'تعديل الذكر المخصص',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'اكتب الذكر وحدد العدد الذي تريد الوصول إليه.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'إغلاق',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: MishkatSpacing.lg),
            TextField(
              controller: _textController,
              autofocus: true,
              minLines: 3,
              maxLines: 4,
              maxLength: 160,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'نص الذكر',
                hintText: 'مثال: أستغفر الله العظيم',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => _clearValidation(),
            ),
            const SizedBox(height: MishkatSpacing.md),
            Text(
              'هدف الجلسة',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: MishkatSpacing.sm),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _targetController,
              builder: (context, value, _) {
                final selectedTarget = int.tryParse(value.text);
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final target in _targetPresets)
                      ChoiceChip(
                        label: Text('$target'),
                        selected: selectedTarget == target,
                        onSelected: (_) {
                          _targetController.text = '$target';
                          _clearValidation();
                        },
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: MishkatSpacing.md),
            TextField(
              controller: _targetController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'أو اكتب هدفًا مخصصًا',
                hintText: 'من 1 إلى 9999',
                counterText: '',
              ),
              onChanged: (_) => _clearValidation(),
              onSubmitted: (_) => _submit(),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _validationMessage == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: const ValueKey('custom-dhikr-error'),
                      padding: const EdgeInsets.only(top: MishkatSpacing.sm),
                      child: Text(
                        _validationMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: MishkatSpacing.base),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: MishkatRadius.brMd,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: MishkatSpacing.sm),
                  Expanded(
                    child: Text(
                      'سيبدأ عدّ جديد لهذا الذكر، وسيبقى إجماليك محفوظًا.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MishkatSpacing.base),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  widget.initialText.isEmpty
                      ? 'إضافة واستخدام الذكر'
                      : 'حفظ التعديلات',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearValidation() {
    if (_validationMessage != null) {
      setState(() => _validationMessage = null);
    }
  }

  void _submit() {
    final text = _textController.text.trim();
    final target = int.tryParse(_targetController.text);
    if (text.isEmpty || target == null || target < 1 || target > 9999) {
      setState(() => _validationMessage = 'اكتب ذكرًا وحدد هدفًا بين 1 و9999.');
      return;
    }
    Navigator.pop(context, _CustomDhikrValue(text, target));
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
    final value = await showDialog<int>(
      context: pageContext,
      builder: (context) => _CustomTargetDialog(initialTarget: current),
    );
    if (value != null && pageContext.mounted) {
      await pageContext.read<TasbihCubit>().setTarget(value);
    }
  }
}

class _CustomTargetDialog extends StatefulWidget {
  const _CustomTargetDialog({required this.initialTarget});

  final int initialTarget;

  @override
  State<_CustomTargetDialog> createState() => _CustomTargetDialogState();
}

class _CustomTargetDialogState extends State<_CustomTargetDialog> {
  late final TextEditingController _controller;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialTarget}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('هدف مخصص'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 4,
          decoration: const InputDecoration(
            labelText: 'عدد التسبيحات',
            hintText: 'من 1 إلى 9999',
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_validationMessage != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _validationMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(onPressed: _submit, child: const Text('حفظ')),
    ],
  );

  void _submit() {
    final value = int.tryParse(_controller.text);
    if (value == null || value < 1 || value > 9999) {
      setState(() => _validationMessage = 'أدخل عددًا بين 1 و9999.');
      return;
    }
    Navigator.pop(context, value);
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
  const _CounterSurface({required this.state, this.onCompletionSound});

  final TasbihState state;
  final VoidCallback? onCompletionSound;

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
                final completesGoal = state.count + 1 == state.target;
                if (state.hapticsEnabled) {
                  if (completesGoal) {
                    HapticFeedback.heavyImpact();
                  } else {
                    HapticFeedback.selectionClick();
                  }
                }
                if (completesGoal && state.completionSoundEnabled) {
                  onCompletionSound?.call();
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

Future<void> _showTasbihSettingsSheet(BuildContext pageContext) async {
  final cubit = pageContext.read<TasbihCubit>();
  final resetRequested = await showModalBottomSheet<bool>(
    context: pageContext,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) =>
        BlocProvider.value(value: cubit, child: const _TasbihSettingsSheet()),
  );
  if (resetRequested == true && pageContext.mounted) {
    await _confirmReset(pageContext);
  }
}

class _TasbihSettingsSheet extends StatelessWidget {
  const _TasbihSettingsSheet();

  @override
  Widget build(BuildContext context) => BlocBuilder<TasbihCubit, TasbihState>(
    builder: (context, state) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              'إعدادات المسبحة',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          SwitchListTile.adaptive(
            value: state.completionSoundEnabled,
            onChanged: (_) =>
                context.read<TasbihCubit>().toggleCompletionSound(),
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('صوت عند إتمام الهدف'),
            subtitle: const Text('تنبيه قصير مرة واحدة عند بلوغ العدد'),
          ),
          SwitchListTile.adaptive(
            value: state.hapticsEnabled,
            onChanged: (_) => context.read<TasbihCubit>().toggleHaptics(),
            secondary: const Icon(Icons.vibration_rounded),
            title: const Text('الاهتزاز مع العد'),
            subtitle: const Text('لمسة خفيفة، وأقوى عند اكتمال الهدف'),
          ),
          Divider(color: context.mishkat.borderSubtle),
          ListTile(
            enabled: state.count > 0,
            onTap: state.count == 0 ? null : () => Navigator.pop(context, true),
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('بدء جلسة جديدة'),
            subtitle: const Text('تصفير الجلسة مع إبقاء إجماليك محفوظًا'),
          ),
        ],
      ),
    ),
  );
}

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
