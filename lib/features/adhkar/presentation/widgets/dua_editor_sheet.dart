import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/adhkar_models.dart';
import '../cubit/adhkar_cubit.dart';

/// Creates a personal dua with its cards, appends cards, or edits one card.
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
  final _titleController = TextEditingController();
  final _cards = <_CardDraft>[];
  final _removedCards = <_CardDraft>[];
  var _nextCardId = 0;
  bool _isSaving = false;
  bool _showErrors = false;

  bool get _isEdit => widget.item != null || widget.index != null;
  bool get _isCard => widget.duaId != null;

  @override
  void initState() {
    super.initState();
    _cards.add(_CardDraft(_nextCardId++, item: widget.item));
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final card in [..._cards, ..._removedCards]) {
      card.dispose();
    }
    super.dispose();
  }

  void _reveal(_CardDraft card) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cardContext = card.anchor.currentContext;
      if (mounted && cardContext != null) {
        Scrollable.ensureVisible(
          cardContext,
          alignment: 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
        );
      }
    });
  }

  void _addCard() {
    if (_isSaving) return;
    final card = _CardDraft(_nextCardId++);
    setState(() => _cards.add(card));
    _reveal(card);
  }

  void _removeCard(_CardDraft card) {
    if (_isSaving || _cards.length == 1) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _cards.remove(card);
      // Keep controllers alive until the removed fields have unmounted.
      _removedCards.add(card);
    });
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    for (final card in _cards) {
      if (!card.isValid) {
        setState(() => _showErrors = true);
        _reveal(card);
        return;
      }
    }
    setState(() => _isSaving = true);
    final cubit = context.read<AdhkarCubit>();
    final items = [for (final card in _cards) card.toItem()];
    try {
      if (_isEdit) {
        final item = items.single;
        await cubit.saveCustom(
          duaId: widget.duaId,
          index: widget.index,
          title: item.title,
          text: item.text,
          count: item.count,
        );
      } else {
        await cubit.saveCustomCards(
          duaId: widget.duaId,
          title: _titleController.text.trim(),
          items: items,
        );
      }
      if (mounted) {
        context.showMessage(
          _isEdit
              ? 'تم تحديث البطاقة.'
              : _isCard
              ? (_cards.length == 1
                    ? 'تمت إضافة البطاقة إلى الدعاء.'
                    : 'تمت إضافة البطاقات إلى الدعاء.')
              : 'تم حفظ الدعاء وبطاقاته في أدعيتك.',
        );
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        context.showMessage('تعذّر الحفظ. بطاقاتك ما زالت هنا، حاول مرة أخرى.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final duaName = _isCard
        ? context.read<AdhkarCubit>().state.categoryById(widget.duaId!)?.name
        : null;
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
                        ? (_isEdit ? 'تعديل البطاقة' : 'إضافة بطاقات للدعاء')
                        : 'إضافة دعاء جديد',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: MishkatSpacing.sm),
            Text(
              _isCard ? 'ضمن «${duaName ?? 'الدعاء'}»' : 'اجمع أدعيتك تحت عنوان واحد، ولكل بطاقة نصّها وعدد تكرارها.',
              style: TextStyle(color: colors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: MishkatSpacing.lg),
            if (!_isCard) ...[
              TextField(
                controller: _titleController,
                enabled: !_isSaving,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'عنوان الدعاء (اختياري)',
                  hintText: 'مثال: أدعية قبل النوم',
                ),
              ),
              const SizedBox(height: MishkatSpacing.lg),
            ],
            for (final (index, card) in _cards.indexed) ...[
              _cardFields(context, card, index),
              const SizedBox(height: MishkatSpacing.md),
            ],
            if (!_isEdit) ...[
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _addCard,
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة بطاقة أخرى'),
              ),
              const SizedBox(height: MishkatSpacing.lg),
            ],
            MishkatPrimaryAction(
              onPressed: _isSaving ? null : _submit,
              icon: const Icon(Icons.check_rounded),
              label: _isSaving
                  ? 'جارٍ الحفظ…'
                  : _isEdit
                  ? 'حفظ التعديلات'
                  : _isCard
                  ? (_cards.length == 1 ? 'إضافة البطاقة' : 'إضافة البطاقات')
                  : 'حفظ في أدعيتي',
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardFields(BuildContext context, _CardDraft card, int index) {
    final colors = context.mishkat;
    return Padding(
      key: card.anchor,
      padding: EdgeInsets.zero,
      child: Container(
        key: ValueKey('dua-draft-card-${card.id}'),
        padding: const EdgeInsets.all(MishkatSpacing.md),
        decoration: BoxDecoration(
          color: colors.primarySoft.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(MishkatRadius.md),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'البطاقة ${(widget.index ?? index) + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                ),
                if (!_isEdit && _cards.length > 1)
                  IconButton(
                    tooltip: 'إزالة البطاقة ${index + 1}',
                    onPressed: _isSaving ? null : () => _removeCard(card),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: MishkatSpacing.md),
            if (_isCard) ...[
              TextField(
                key: ValueKey('dua-card-title-${card.id}'),
                controller: card.title,
                enabled: !_isSaving,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'عنوان البطاقة (اختياري)',
                  hintText: 'مثال: دعاء البداية',
                ),
              ),
              const SizedBox(height: MishkatSpacing.md),
            ],
            TextField(
              key: ValueKey('dua-card-text-${card.id}'),
              controller: card.text,
              enabled: !_isSaving,
              minLines: 3,
              maxLines: 6,
              onChanged: _showErrors ? (_) => setState(() {}) : null,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: _isCard ? 'نص البطاقة *' : 'نص الدعاء أو الذكر *',
                hintText: 'اكتب نص الدعاء أو الذكر هنا...',
                alignLabelWithHint: true,
                errorMaxLines: 2,
                errorText: _showErrors && card.text.text.trim().isEmpty
                    ? 'اكتب نص الدعاء أو الذكر لهذه البطاقة.'
                    : null,
              ),
            ),
            const SizedBox(height: MishkatSpacing.md),
            TextField(
              key: ValueKey('dua-card-count-${card.id}'),
              controller: card.count,
              enabled: !_isSaving,
              keyboardType: TextInputType.number,
              onChanged: _showErrors ? (_) => setState(() {}) : null,
              decoration: InputDecoration(
                labelText: 'عدد مرات التكرار',
                hintText: '1',
                suffixText: 'مرات',
                errorMaxLines: 2,
                errorText: _showErrors && !card.hasValidCount
                    ? 'أدخل عددًا من 1 إلى 10000.'
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardDraft {
  _CardDraft(this.id, {DhikrItem? item})
    : title = TextEditingController(text: item?.title),
      text = TextEditingController(text: item?.text),
      count = TextEditingController(text: '${item?.count ?? 1}');

  final int id;
  final anchor = GlobalKey();
  final TextEditingController title;
  final TextEditingController text;
  final TextEditingController count;

  int? get repetitions =>
      int.tryParse(AppFormatters.normalizeArabic(count.text));
  bool get hasValidCount =>
      repetitions != null && repetitions! >= 1 && repetitions! <= 10000;
  bool get isValid => text.text.trim().isNotEmpty && hasValidCount;

  DhikrItem toItem() => DhikrItem(
    title: title.text.trim(),
    text: text.text.trim(),
    count: repetitions!,
  );

  void dispose() {
    title.dispose();
    text.dispose();
    count.dispose();
  }
}
