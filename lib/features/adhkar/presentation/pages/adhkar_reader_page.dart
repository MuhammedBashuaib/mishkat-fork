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

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  void _prepare(AdhkarCategory category, Map<int, int> progress) {
    if (_categoryId == category.id) return;
    _pages?.dispose();
    _categoryId = category.id;
    final pending = category.items.indexed.where(
      (entry) => (progress[entry.$1] ?? 0) < entry.$2.count,
    );
    _index = pending.firstOrNull?.$1 ?? 0;
    _pages = PageController(initialPage: _index, viewportFraction: 0.94);
  }

  void _goTo(int index) {
    if (_pages?.hasClients != true) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages!.jumpToPage(index);
    } else {
      _pages!.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      );
    }
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
                onPressed: () => DuaEditorSheet.show(context),
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
                              child: PageView.builder(
                                key: ValueKey(category.id),
                                controller: _pages,
                                itemCount: category.items.length,
                                onPageChanged: (value) =>
                                    setState(() => _index = value),
                                itemBuilder: (context, i) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 4,
                                  ),
                                  child: _ReadingCard(
                                    category: category,
                                    index: i,
                                    done: progress[i] ?? 0,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                12,
                                20,
                                12,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!compact)
                                    Text(
                                      'البطاقة ${index + 1} من ${category.items.length} • اسحب للتنقل',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.mishkat.textSecondary,
                                      ),
                                    ),
                                  if (!compact) const SizedBox(height: 12),
                                  _ReaderControls(
                                    compact: compact,
                                    item: category.items[index],
                                    done: progress[index] ?? 0,
                                    previous: index > 0
                                        ? () => _goTo(index - 1)
                                        : null,
                                    next: index < category.items.length - 1
                                        ? () => _goTo(index + 1)
                                        : null,
                                    onCount: () {
                                      HapticFeedback.selectionClick();
                                      context.read<AdhkarCubit>().increment(
                                        category.id,
                                        index,
                                      );
                                    },
                                  ),
                                ],
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
  });
  final AdhkarCategory category;
  final int index;
  final int done;

  @override
  Widget build(BuildContext context) {
    final item = category.items[index];
    final completed = done >= item.count;
    final colors = context.mishkat;
    return Material(
      key: ValueKey('dhikr-card-$index'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: completed
              ? colors.success.withValues(alpha: 0.5)
              : colors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 8, 0),
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
                  onSelected: (value) {
                    final cubit = context.read<AdhkarCubit>();
                    switch (value) {
                      case 'reset':
                        cubit.reset(category.id, index);
                      case 'edit':
                        DuaEditorSheet.show(context, index: index, item: item);
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
                      const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      const PopupMenuItem(value: 'delete', child: Text('حذف')),
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
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 36).clamp(
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                      const SizedBox(height: 24),
                      if (item.countOptions.isEmpty)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primarySoft,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${item.count} ${item.count >= 3 && item.count <= 10 ? 'مرات' : 'مرة'}',
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      if (item.countOptions.isNotEmpty) ...[
                        const SizedBox(height: 20),
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
                                onSelected: (_) => context
                                    .read<AdhkarCubit>()
                                    .setCountTarget(category.id, index, target),
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
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              category.custom ? 'من أدعيتك الخاصة' : 'من كتاب حصن المسلم',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderControls extends StatelessWidget {
  const _ReaderControls({
    required this.item,
    required this.done,
    required this.onCount,
    required this.compact,
    this.previous,
    this.next,
  });
  final DhikrItem item;
  final int done;
  final VoidCallback onCount;
  final bool compact;
  final VoidCallback? previous;
  final VoidCallback? next;

  @override
  Widget build(BuildContext context) {
    final completed = done >= item.count;
    final remaining = (item.count - done).clamp(0, item.count);
    return Row(
      children: [
        IconButton.outlined(
          tooltip: 'الذكر السابق',
          onPressed: previous,
          icon: const Icon(MishkatNavigationIcons.back),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            button: true,
            label: completed
                ? 'اكتمل الذكر'
                : 'اضغط للعد، المتبقي $remaining من ${item.count}',
            excludeSemantics: true,
            child: FilledButton(
              key: const ValueKey('dhikr-counter'),
              onPressed: completed ? null : onCount,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                disabledBackgroundColor: context.mishkat.primarySoft,
                disabledForegroundColor: context.mishkat.primary,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!compact)
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: (done / item.count).clamp(0, 1),
                            strokeWidth: 2,
                            color: completed
                                ? context.mishkat.primary
                                : Theme.of(context).colorScheme.onPrimary,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimary
                                .withValues(alpha: 0.2),
                          ),
                          Icon(
                            completed
                                ? Icons.check_rounded
                                : Icons.touch_app_outlined,
                            size: 17,
                          ),
                        ],
                      ),
                    ),
                  if (!compact) const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          compact
                              ? (completed ? 'تم' : 'عدّ الذكر')
                              : (completed ? 'اكتمل الذكر' : 'اضغط للعد'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (!completed)
                          Text(
                            '${done.clamp(0, item.count)} / ${item.count}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.outlined(
          tooltip: 'الذكر التالي',
          onPressed: next,
          icon: const Icon(MishkatNavigationIcons.forward),
        ),
      ],
    );
  }
}

// Separate the source's repetition instructions from the words being recited.
String _recitation(String text, {bool daily = false}) {
  if (!daily) return text;
  final start = text.indexOf('((');
  final end = text.indexOf('))');
  if (start >= 0 && end > start) return text.substring(start + 2, end).trim();
  return text.replaceFirst(RegExp(r'\s*\(ثلاثَ مرَّاتٍ\)\.?$'), '').trim();
}
