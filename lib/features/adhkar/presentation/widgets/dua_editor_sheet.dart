import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/adhkar_models.dart';
import '../cubit/adhkar_cubit.dart';

/// Modal bottom sheet for adding or editing a personal dua/supplication.
class DuaEditorSheet extends StatefulWidget {
  const DuaEditorSheet({super.key, this.duaId, this.index, this.item});

  final int? duaId;
  final int? index;
  final DhikrItem? item;

  static Future<bool?> show(
    BuildContext context, {
    int? duaId,
    int? index,
    DhikrItem? item,
  }) {
    final cubit = context.read<AdhkarCubit>();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MishkatRadius.xl),
        ),
      ),
      builder: (sheetContext) => BlocProvider.value(
        value: cubit,
        child: DuaEditorSheet(duaId: duaId, index: index, item: item),
      ),
    );
  }

  @override
  State<DuaEditorSheet> createState() => _DuaEditorSheetState();
}

class _DuaEditorSheetState extends State<DuaEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _textController;
  late final TextEditingController _countController;
  bool _isSaving = false;

  bool get _isEdit => widget.item != null || widget.index != null;
  bool get _isCard => widget.duaId != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item?.title);
    _textController = TextEditingController(text: widget.item?.text);
    _countController = TextEditingController(
      text: '${widget.item != null ? widget.item!.count : 1}',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    _countController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      context.showMessage(
        _isCard
            ? 'يرجى كتابة نص البطاقة أولاً.'
            : 'يرجى كتابة نص الدعاء أولاً.',
      );
      return;
    }

    final title = _titleController.text.trim();
    final count = int.tryParse(
      AppFormatters.normalizeArabic(_countController.text),
    );
    if (count == null || count < 1 || count > 10000) {
      context.showMessage('أدخل عدد تكرار من 1 إلى 10000.');
      return;
    }
    setState(() => _isSaving = true);

    try {
      await context.read<AdhkarCubit>().saveCustom(
        duaId: widget.duaId,
        index: widget.index,
        title: title,
        text: text,
        count: count,
      );
      if (mounted) {
        context.showMessage(
          _isCard
              ? (_isEdit
                    ? 'تم تحديث البطاقة.'
                    : 'تمت إضافة البطاقة إلى الدعاء.')
              : 'تمت إضافة الدعاء إلى أدعيتك.',
        );
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        context.showMessage('تعذّر الحفظ. حاول مرة أخرى.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        MishkatSpacing.lg,
        MishkatSpacing.md,
        MishkatSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + MishkatSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top drag handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(MishkatRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: MishkatSpacing.lg),

            // Header with icon and title
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: BorderRadius.circular(MishkatRadius.md),
                  ),
                  child: Icon(
                    _isEdit
                        ? Icons.edit_note_rounded
                        : Icons.bookmark_add_rounded,
                    color: colors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: MishkatSpacing.md),
                Expanded(
                  child: Text(
                    _isCard
                        ? (_isEdit ? 'تعديل البطاقة' : 'إضافة بطاقة للدعاء')
                        : 'إضافة دعاء جديد',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
              ],
            ),
            if (!_isCard) ...[
              const SizedBox(height: MishkatSpacing.sm),
              Text(
                'يُحفظ الدعاء مستقلًا، ويمكنك إضافة بطاقات أخرى داخله.',
                style: TextStyle(color: colors.textSecondary, height: 1.5),
              ),
            ],
            const SizedBox(height: MishkatSpacing.lg),

            // Optional title input
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: _isCard
                    ? 'عنوان البطاقة (اختياري)'
                    : 'عنوان الدعاء (اختياري)',
                hintText: _isCard
                    ? 'مثال: دعاء البداية'
                    : 'مثال: دعاء تيسير الأمور، للوالدين...',
              ),
            ),
            const SizedBox(height: MishkatSpacing.md),

            // Required dua text input
            TextField(
              controller: _textController,
              minLines: 3,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: _isCard ? 'نص البطاقة *' : 'نص الدعاء أو الذكر *',
                hintText: 'اكتب نص الدعاء هنا...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: MishkatSpacing.md),

            // Repetition count input
            TextField(
              controller: _countController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'عدد مرات التكرار',
                hintText: '1',
                suffixText: 'مرات',
              ),
            ),
            const SizedBox(height: MishkatSpacing.xl),

            // Action button
            MishkatPrimaryAction(
              onPressed: _isSaving ? null : _submit,
              icon: const Icon(Icons.check_rounded),
              label: _isEdit
                  ? 'حفظ التعديلات'
                  : _isCard
                  ? 'إضافة البطاقة'
                  : 'حفظ في أدعيتي',
            ),
          ],
        ),
      ),
    );
  }
}
