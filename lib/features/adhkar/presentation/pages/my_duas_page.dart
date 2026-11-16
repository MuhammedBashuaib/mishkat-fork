import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/navigation_icons.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/adhkar_models.dart';
import '../cubit/adhkar_cubit.dart';
import '../cubit/adhkar_state.dart';
import '../widgets/dua_editor_sheet.dart';
import 'adhkar_reader_page.dart';

class MyDuasPage extends StatefulWidget {
  const MyDuasPage({super.key});

  @override
  State<MyDuasPage> createState() => _MyDuasPageState();
}

class _MyDuasPageState extends State<MyDuasPage> {
  String _query = '';

  Future<void> _open(AdhkarCategory dua) async {
    final cubit = context.read<AdhkarCubit>();
    cubit.select(dua.id);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BlocProvider.value(value: cubit, child: const AdhkarReaderPage()),
      ),
    );
  }

  Future<void> _rename(AdhkarCategory dua) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDuaDialog(name: dua.name),
    );
    if (name == null || !mounted) return;
    try {
      await context.read<AdhkarCubit>().renameCustomDua(dua.id, name);
    } catch (_) {
      if (mounted) context.showMessage('تعذّر تعديل العنوان. حاول مرة أخرى.');
    }
  }

  Future<void> _delete(AdhkarCategory dua) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الدعاء؟'),
        content: Text('سيُحذف «${dua.name}» وجميع بطاقاته.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AdhkarCubit>().deleteCustomDua(dua.id);
    } catch (_) {
      if (mounted) context.showMessage('تعذّر حذف الدعاء. حاول مرة أخرى.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'رجوع',
        icon: const Icon(MishkatNavigationIcons.back),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text('أدعيتي'),
      actions: [
        IconButton(
          tooltip: 'إضافة دعاء جديد',
          onPressed: () => DuaEditorSheet.show(context),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: BlocBuilder<AdhkarCubit, AdhkarState>(
        builder: (context, state) {
          if (state.status == AdhkarStatus.initial ||
              state.status == AdhkarStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == AdhkarStatus.failure) {
            return ContentStatePanel(
              icon: Icons.error_outline,
              title: 'تعذّر تحميل أدعيتك',
              message: 'حاول مرة أخرى.',
              action: FilledButton(
                onPressed: context.read<AdhkarCubit>().load,
                child: const Text('إعادة المحاولة'),
              ),
            );
          }
          final query = AppFormatters.normalizeArabic(_query);
          final duas = state.customDuas.reversed
              .where(
                (dua) =>
                    query.isEmpty ||
                    AppFormatters.normalizeArabic(dua.name).contains(query) ||
                    dua.items.any(
                      (item) => AppFormatters.normalizeArabic(
                        '${item.title} ${item.text}',
                      ).contains(query),
                    ),
              )
              .toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                key: const PageStorageKey('my-duas-list'),
                padding: MishkatSpacing.page,
                children: [
                  Text(
                    'لكل دعاء بطاقاته وعدّاداته المستقلة.',
                    style: TextStyle(color: context.mishkat.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'ابحث في أدعيتك',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (state.customDuas.isEmpty)
                    ContentStatePanel(
                      icon: Icons.favorite_outline_rounded,
                      title: 'لا توجد أدعية مضافة بعد',
                      message: 'أضف دعاءً، ثم أضف داخله ما تحتاجه من بطاقات.',
                      action: FilledButton.icon(
                        onPressed: () => DuaEditorSheet.show(context),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('إضافة أول دعاء'),
                      ),
                    )
                  else if (duas.isEmpty)
                    const ContentStatePanel(
                      icon: Icons.search_off_rounded,
                      title: 'لا توجد نتائج',
                      message: 'جرّب عنوان الدعاء أو كلمة من نصّه.',
                    )
                  else
                    for (final dua in duas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DuaTile(
                          dua: dua,
                          progress: state.progress[dua.id] ?? const {},
                          onOpen: () => _open(dua),
                          onRename: () => _rename(dua),
                          onDelete: () => _delete(dua),
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _DuaTile extends StatelessWidget {
  const _DuaTile({
    required this.dua,
    required this.progress,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final AdhkarCategory dua;
  final Map<int, int> progress;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cardCount = switch (dua.items.length) {
      1 => 'بطاقة واحدة',
      2 => 'بطاقتان',
      <= 10 => '${dua.items.length} بطاقات',
      _ => '${dua.items.length} بطاقة',
    };
    final completed = dua.items.indexed
        .where((entry) => (progress[entry.$1] ?? 0) >= entry.$2.count)
        .length;
    return MishkatCard(
      key: ValueKey('custom-dua-${dua.id}'),
      onTap: onOpen,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 12),
      child: Row(
        children: [
          Icon(Icons.favorite_outline_rounded, color: context.mishkat.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dua.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (dua.items.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    dua.items.first.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.mishkat.textSecondary),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  dua.items.isEmpty
                      ? 'أضف أول بطاقة لهذا الدعاء'
                      : '$cardCount • $completed مكتملة',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.mishkat.primary,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'خيارات الدعاء',
            onSelected: (value) => value == 'rename' ? onRename() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('تعديل العنوان')),
              PopupMenuItem(value: 'delete', child: Text('حذف الدعاء')),
            ],
          ),
          const Icon(MishkatNavigationIcons.forward, size: 20),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _RenameDuaDialog extends StatefulWidget {
  const _RenameDuaDialog({required this.name});

  final String name;

  @override
  State<_RenameDuaDialog> createState() => _RenameDuaDialogState();
}

class _RenameDuaDialogState extends State<_RenameDuaDialog> {
  late final _controller = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('تعديل عنوان الدعاء'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 100,
      decoration: const InputDecoration(labelText: 'عنوان الدعاء'),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      TextButton(onPressed: _save, child: const Text('حفظ')),
    ],
  );
}
