import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/navigation_icons.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/adhkar_models.dart';
import '../cubit/adhkar_cubit.dart';
import '../cubit/adhkar_state.dart';
import '../widgets/dua_editor_sheet.dart';

class AdhkarReaderPage extends StatefulWidget {
  const AdhkarReaderPage({super.key});

  @override
  State<AdhkarReaderPage> createState() => _AdhkarReaderPageState();
}

class _AdhkarReaderPageState extends State<AdhkarReaderPage> {
  PageController? _pages;
  int? _categoryId;
  int _index = 0;
  Timer? _advanceTimer;

  void _cancelAdvance() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
  }

  @override
  void dispose() {
    _cancelAdvance();
    _pages?.dispose();
    super.dispose();
  }

  void _prepare(AdhkarCategory category, Map<int, int> progress) {
    if (_categoryId == category.id) return;
    _cancelAdvance();
    _pages?.dispose();
    _categoryId = category.id;
    final pending = category.items.indexed.where(
      (entry) => (progress[entry.$1] ?? 0) < entry.$2.count,
    );
    _index = pending.firstOrNull?.$1 ?? 0;
    _pages = PageController(initialPage: _index, viewportFraction: 0.92);
  }

  void _goTo(int index) {
    _cancelAdvance();
    if (_pages?.hasClients != true) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages!.jumpToPage(index);
    } else {
      _pages!.animateToPage(
        index,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _count(int index) {
    final pages = _pages;
    if (index != _index || pages == null || !pages.hasClients) return;
    // A swipe or an automatic transition must never count a repetition.
    if (pages.position.isScrollingNotifier.value ||
        (pages.page! - index).abs() > 0.01 ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final cubit = context.read<AdhkarCubit>();
    final category = cubit.state.selected;
    if (category == null || index >= category.items.length) return;
    final item = category.items[index];
    final done = cubit.countFor(category.id, index);
    if (done >= item.count) return;

    unawaited(cubit.increment(category.id, index));
    if (done + 1 < item.count) {
      unawaited(HapticFeedback.selectionClick());
      return;
    }
    unawaited(HapticFeedback.lightImpact());
    if (index == category.items.length - 1) return;
    _cancelAdvance();
    // Leave the completed state visible for a beat before moving on.
    _advanceTimer = Timer(const Duration(milliseconds: 240), () {
      _advanceTimer = null;
      if (!mounted ||
          _index != index ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final current = cubit.state.selected;
      if (current == null ||
          current.id != category.id ||
          current.items.length != category.items.length ||
          current.items[index] != item ||
          cubit.countFor(category.id, index) < item.count ||
          pages.position.isScrollingNotifier.value) {
        return;
      }
      _goTo(index + 1);
    });
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AdhkarCubit, AdhkarState>(
    builder: (context, state) {
      final category = state.selected;
      if (category == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const ContentStatePanel(
            icon: Icons.info_outline,
            title: 'الباب غير موجود',
            message: 'ارجع إلى فهرس الأذكار.',
          ),
        );
      }
      final progress = state.progress[category.id] ?? const <int, int>{};
      _prepare(category, progress);
      // Custom prayers can be deleted while the reader is open.
      final index = _index.clamp(
        0,
        (category.items.length - 1).clamp(0, 100000),
      );
      if (_index != index) {
        _index = index;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _goTo(index);
        });
      }
      final completed = category.items.indexed
          .where((entry) => (progress[entry.$1] ?? 0) >= entry.$2.count)
          .length;
      final allDone =
          category.items.isNotEmpty && completed == category.items.length;

      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(MishkatNavigationIcons.back),
          ),
          title: Text(category.name),
          actions: [
            if (category.items.isNotEmpty)
              IconButton(
                tooltip: 'فهرس الورد',
                onPressed: () => _showContents(category, progress),
                icon: const Icon(Icons.format_list_bulleted_rounded),
              ),
            if (progress.values.any((count) => count > 0))
              IconButton(
                tooltip: 'بدء الورد من جديد',
                onPressed: () => _confirmReset(category),
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            if (category.custom)
              IconButton(
                tooltip: 'إضافة دعاء',
                onPressed: () {
                  _cancelAdvance();
                  DuaEditorSheet.show(context);
                },
                icon: const Icon(Icons.add),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: category.items.isEmpty
                  ? ContentStatePanel(
                      icon: Icons.edit_note,
                      title: 'أدعية خاصة بك',
                      message: 'أضف دعاءً أو ذكرًا تريد الرجوع إليه باستمرار.',
                      action: FilledButton.icon(
                        onPressed: () => DuaEditorSheet.show(context),
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة دعاء'),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final compact =
                            constraints.maxHeight < 420 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.5;
                        return Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                24,
                                compact ? 0 : 8,
                                24,
                                compact ? 8 : 16,
                              ),
                              child: _WirdProgress(
                                compact: compact,
                                completed: completed,
                                total: category.items.length,
                                allDone: allDone,
                              ),
                            ),
                            Expanded(
                              child:
                                  NotificationListener<ScrollStartNotification>(
                                    onNotification: (notification) {
                                      if (notification.dragDetails != null) {
                                        _cancelAdvance();
                                      }
                                      return false;
                                    },
                                    child: PageView.builder(
                                      key: ValueKey(category.id),
                                      controller: _pages,
                                      itemCount: category.items.length,
                                      onPageChanged: (value) {
                                        _cancelAdvance();
                                        setState(() => _index = value);
                                      },
                                      itemBuilder: (context, i) =>
                                          AnimatedBuilder(
                                            animation: _pages!,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 8,
                                                  ),
                                              child: ExcludeSemantics(
                                                excluding: i != _index,
                                                child: IgnorePointer(
                                                  ignoring: i != _index,
                                                  child: _ReadingCard(
                                                    category: category,
                                                    index: i,
                                                    done: progress[i] ?? 0,
                                                    compact: compact,
                                                    active: i == _index,
                                                    onCount: () => _count(i),
                                                    onInteraction:
                                                        _cancelAdvance,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            builder: (context, child) {
                                              final page =
                                                  _pages!.hasClients &&
                                                      _pages!
                                                          .position
                                                          .hasContentDimensions
                                                  ? _pages!.page ??
                                                        _index.toDouble()
                                                  : _index.toDouble();
                                              final distance = (page - i)
                                                  .abs()
                                                  .clamp(0.0, 1.0);
                                              if (MediaQuery.disableAnimationsOf(
                                                context,
                                              )) {
                                                return child!;
                                              }
                                              return Transform.translate(
                                                offset: Offset(
                                                  0,
                                                  10 * distance,
                                                ),
                                                child: Transform.scale(
                                                  scale: 1 - 0.045 * distance,
                                                  child: Opacity(
                                                    opacity:
                                                        1 - 0.25 * distance,
                                                    child: child,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                    ),
                                  ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                24,
                                compact ? 4 : 8,
                                24,
                                compact ? 4 : 12,
                              ),
                              child: _ReaderControls(
                                compact: compact,
                                index: index,
                                total: category.items.length,
                                previous: index > 0
                                    ? () => _goTo(index - 1)
                                    : null,
                                next: index < category.items.length - 1
                                    ? () => _goTo(index + 1)
                                    : null,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _confirmReset(AdhkarCategory category) async {
    _cancelAdvance();
    final reset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بدء الورد من جديد؟'),
        content: const Text('سيعود عدّ جميع الأذكار في هذا الباب إلى الصفر.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إعادة العد'),
          ),
        ],
      ),
    );
    if (reset == true && mounted) {
      await context.read<AdhkarCubit>().resetCategory(category.id);
      if (mounted) _goTo(0);
    }
  }

  Future<void> _showContents(
    AdhkarCategory category,
    Map<int, int> progress,
  ) async {
    _cancelAdvance();
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'فهرس الورد',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: category.items.length,
                  itemBuilder: (context, i) {
                    final item = category.items[i];
                    final done = (progress[i] ?? 0) >= item.count;
                    return ListTile(
                      key: ValueKey('dhikr-index-$i'),
                      selected: i == _index,
                      leading: CircleAvatar(
                        backgroundColor: context.mishkat.primarySoft,
                        child: done
                            ? const Icon(Icons.check_rounded)
                            : Text('${i + 1}'),
                      ),
                      title: Text(
                        item.title.isEmpty
                            ? _recitation(
                                item.text,
                                daily: category.id == 1 || category.id == 133,
                              )
                            : item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        done ? 'مكتمل' : '${progress[i] ?? 0} / ${item.count}',
                      ),
                      onTap: () => Navigator.pop(context, i),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) _goTo(selected);
  }
}

class _WirdProgress extends StatelessWidget {
  const _WirdProgress({
    required this.completed,
    required this.total,
    required this.allDone,
    this.compact = false,
  });
  final int completed;
  final int total;
  final bool allDone;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!compact)
        Row(
          children: [
            Icon(
              allDone ? Icons.check_circle_outline_rounded : Icons.spa_outlined,
              size: 20,
              color: context.mishkat.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                allDone
                    ? 'أتممت الورد، تقبّل الله منك'
                    : 'على مهل، ذكرًا بعد ذكر',
                style: TextStyle(
                  color: context.mishkat.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$completed / $total',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: context.mishkat.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      if (!compact) const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: completed / total,
          minHeight: 4,
          backgroundColor: context.mishkat.borderSubtle,
          semanticsLabel: 'تقدم الورد، $completed من $total أذكار مكتملة',
        ),
      ),
    ],
  );
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.category,
    required this.index,
    required this.done,
    required this.compact,
    required this.active,
    required this.onCount,
    required this.onInteraction,
  });
  final AdhkarCategory category;
  final int index;
  final int done;
  final bool compact;
  final bool active;
  final VoidCallback onCount;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    final item = category.items[index];
    final completed = done >= item.count;
    final colors = context.mishkat;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Material(
      key: ValueKey('dhikr-card-$index'),
      color: completed
          ? Color.alphaBlend(
              colors.primarySoft.withValues(alpha: 0.35),
              colors.surface,
            )
          : colors.surface,
      animationDuration: duration,
      elevation: 1,
      shadowColor: colors.primary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: completed
              ? colors.success.withValues(alpha: 0.5)
              : colors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Keep taps in the gesture arena during the completion pause so an
        // extra tap cannot turn into a scroll start and cancel auto-advance.
        // The page checks the current count before accepting any repetition.
        onTap: onCount,
        excludeFromSemantics: true,
        splashColor: completed
            ? Colors.transparent
            : colors.primary.withValues(alpha: 0.08),
        highlightColor: completed
            ? Colors.transparent
            : colors.primary.withValues(alpha: 0.04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 8, 0),
              child: Row(
                children: [
                  Icon(
                    completed
                        ? Icons.check_circle_rounded
                        : Icons.auto_stories_outlined,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      completed ? 'اكتمل الذكر' : 'الذكر ${index + 1}',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'نسخ الذكر',
                    icon: const Icon(Icons.copy_outlined, size: 19),
                    onPressed: () async {
                      onInteraction();
                      await Clipboard.setData(
                        ClipboardData(
                          text: _recitation(
                            item.text,
                            daily: category.id == 1 || category.id == 133,
                          ),
                        ),
                      );
                      if (context.mounted) context.showMessage('تم نسخ الذكر.');
                    },
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'خيارات الذكر',
                    icon: const Icon(Icons.more_horiz_rounded),
                    onOpened: onInteraction,
                    onSelected: (value) {
                      onInteraction();
                      final cubit = context.read<AdhkarCubit>();
                      switch (value) {
                        case 'reset':
                          cubit.reset(category.id, index);
                        case 'edit':
                          DuaEditorSheet.show(
                            context,
                            index: index,
                            item: item,
                          );
                        case 'delete':
                          cubit.deleteCustom(index);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'reset',
                        child: Text('إعادة عدّ هذا الذكر'),
                      ),
                      if (category.custom) ...[
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('تعديل'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('حذف'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  key: PageStorageKey('${category.id}-$index-text'),
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - 32).clamp(
                        0,
                        double.infinity,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (item.title.isNotEmpty) ...[
                          Text(
                            item.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          _recitation(
                            item.text,
                            daily: category.id == 1 || category.id == 133,
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontSize:
                                    (Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.fontSize ??
                                        15) *
                                    1.4,
                                height: 2,
                                color: colors.textPrimary,
                              ),
                        ),
                        if (item.countOptions.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            'عدد التكرار',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              for (final target in item.countOptions)
                                ChoiceChip(
                                  label: Text('$target'),
                                  selected: item.count == target,
                                  onSelected: (_) {
                                    onInteraction();
                                    context.read<AdhkarCubit>().setCountTarget(
                                      category.id,
                                      index,
                                      target,
                                    );
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.note,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11,
                              height: 1.7,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          category.custom
                              ? 'من أدعيتك الخاصة'
                              : 'من كتاب حصن المسلم',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 10 : 16),
              child: _CardCounter(
                item: item,
                done: done,
                compact: compact,
                active: active,
                onCount: onCount,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardCounter extends StatelessWidget {
  const _CardCounter({
    required this.item,
    required this.done,
    required this.compact,
    required this.active,
    required this.onCount,
  });
  final DhikrItem item;
  final int done;
  final bool compact;
  final bool active;
  final VoidCallback onCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final completed = done >= item.count;
    final remaining = (item.count - done).clamp(0, item.count);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    // The entire card handles touch. Assistive technologies get one clearly
    // named counter action here while retaining access to the prayer and tools.
    return Semantics(
      key: active ? const ValueKey('dhikr-counter') : null,
      container: true,
      button: !completed,
      liveRegion: active,
      label: completed ? 'اكتمل الذكر' : 'عدّ الذكر',
      value: completed ? null : 'المتبقي $remaining من ${item.count}',
      onTap: active && !completed ? onCount : null,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: compact ? 10 : 14,
        ),
        decoration: BoxDecoration(
          color: colors.primarySoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: compact ? 36 : 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: (done / item.count).clamp(0.0, 1.0)),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 3,
                        strokeCap: StrokeCap.round,
                        color: colors.primary,
                        backgroundColor: colors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  Icon(
                    completed ? Icons.check_rounded : Icons.touch_app_outlined,
                    color: colors.primary,
                    size: compact ? 20 : 24,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: duration,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.18),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      completed ? 'تمّ الذكر' : '$remaining / ${item.count}',
                      key: ValueKey('$remaining-${item.count}'),
                      textDirection: completed
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 18 : 24,
                        height: 1.4,
                      ),
                    ),
                  ),
                  Text(
                    completed
                        ? 'تقبّل الله منك'
                        : compact
                        ? 'اضغط للعدّ'
                        : 'اضغط في أي مكان على البطاقة',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 10,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderControls extends StatelessWidget {
  const _ReaderControls({
    required this.index,
    required this.total,
    required this.compact,
    this.previous,
    this.next,
  });
  final int index;
  final int total;
  final bool compact;
  final VoidCallback? previous;
  final VoidCallback? next;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton.outlined(
        tooltip: 'الذكر السابق',
        onPressed: previous,
        icon: const Icon(MishkatNavigationIcons.back),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1} / $total',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: context.mishkat.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            if (!compact)
              Text(
                'اسحب للتنقل بين الأذكار',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.mishkat.textSecondary,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      IconButton.outlined(
        tooltip: 'الذكر التالي',
        onPressed: next,
        icon: const Icon(MishkatNavigationIcons.forward),
      ),
    ],
  );
}

// Separate the source's repetition instructions from the words being recited.
String _recitation(String text, {bool daily = false}) {
  if (!daily) return text;
  final start = text.indexOf('((');
  final end = text.indexOf('))');
  if (start >= 0 && end > start) return text.substring(start + 2, end).trim();
  return text.replaceFirst(RegExp(r'\s*\(ثلاثَ مرَّاتٍ\)\.?$'), '').trim();
}
