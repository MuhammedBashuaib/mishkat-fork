import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/quran_models.dart';

class OralRecitationSelection {
  const OralRecitationSelection({
    required this.surahNumber,
    required this.startGlobalAyah,
    required this.endGlobalAyah,
    this.startPage,
    this.endPage,
  });

  final int surahNumber;
  final int startGlobalAyah;
  final int endGlobalAyah;
  final int? startPage;
  final int? endPage;
}

/// Selects complete verses from a surah or an inclusive printed-page range.
class OralRecitationRangeSheet extends StatefulWidget {
  const OralRecitationRangeSheet({
    super.key,
    required this.quranData,
    required this.onSelected,
    this.initialSurah = 1,
  });

  final QuranData quranData;
  final int initialSurah;
  final ValueChanged<OralRecitationSelection> onSelected;

  @override
  State<OralRecitationRangeSheet> createState() =>
      _OralRecitationRangeSheetState();
}

class _OralRecitationRangeSheetState extends State<OralRecitationRangeSheet> {
  final _form = GlobalKey<FormState>();
  late int _surah;
  int _startAyah = 1;
  late int _endAyah;
  bool _wholeSurah = false;
  bool _byPages = false;
  late final TextEditingController _startPage;
  late final TextEditingController _endPage;

  @override
  void initState() {
    super.initState();
    _surah = widget.initialSurah.clamp(1, widget.quranData.chapters.length);
    final chapter = widget.quranData.chapter(_surah);
    _endAyah = chapter.ayahs.length.clamp(1, 5);
    _startPage = TextEditingController(text: '${chapter.page}');
    _endPage = TextEditingController(text: '${chapter.page}');
  }

  @override
  void dispose() {
    _startPage.dispose();
    _endPage.dispose();
    super.dispose();
  }

  int? _number(String? value) =>
      int.tryParse(AppFormatters.normalizeArabic(value ?? '').trim());

  int get _pageCount => widget.quranData.pages.length;

  String? _validatePage(String? value) {
    final page = _number(value);
    return page == null || page < 1 || page > _pageCount
        ? 'أدخل صفحة من 1 إلى $_pageCount'
        : null;
  }

  OralRecitationSelection? _selection() {
    final data = widget.quranData;
    if (_byPages) {
      final start = _number(_startPage.text);
      final end = _number(_endPage.text);
      if (start == null ||
          end == null ||
          start < 1 ||
          end < start ||
          end > _pageCount) {
        return null;
      }
      final first = data.page(start).first;
      final last = data.page(end).last;
      return OralRecitationSelection(
        surahNumber: first.surah,
        startGlobalAyah: first.global,
        endGlobalAyah: last.global,
        startPage: start,
        endPage: end,
      );
    }
    final chapter = data.chapter(_surah);
    return OralRecitationSelection(
      surahNumber: _surah,
      startGlobalAyah: chapter.globalStart + (_wholeSurah ? 0 : _startAyah - 1),
      endGlobalAyah:
          chapter.globalStart +
          (_wholeSurah ? chapter.ayahs.length : _endAyah) -
          1,
    );
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final selection = _selection();
    if (selection == null) return;
    FocusScope.of(context).unfocus();
    widget.onSelected(selection);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final chapter = widget.quranData.chapter(_surah);
    final totalAyahs = chapter.ayahs.length;
    final selection = _selection();
    final selectedCount = selection == null
        ? 0
        : selection.endGlobalAyah - selection.startGlobalAyah + 1;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textMuted.withValues(alpha: .35),
                    borderRadius: MishkatRadius.brPill,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'تسميع حر',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'اختر سورة وآياتها، أو صفحة واحدة أو عدة صفحات.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 18),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('السورة والآيات')),
                  ButtonSegment(value: true, label: Text('الصفحات')),
                ],
                selected: {_byPages},
                onSelectionChanged: (values) =>
                    setState(() => _byPages = values.single),
              ),
              const SizedBox(height: 16),
              if (_byPages) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _pageField(isStart: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _pageField(isStart: false)),
                  ],
                ),
              ] else ...[
                DropdownButtonFormField<int>(
                  key: ValueKey('free-surah-$_surah'),
                  initialValue: _surah,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'السورة',
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
                    if (value == null) return;
                    setState(() {
                      _surah = value;
                      _startAyah = 1;
                      _endAyah = widget.quranData
                          .chapter(value)
                          .ayahs
                          .length
                          .clamp(1, 5);
                    });
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  tileColor: colors.surfaceVariant.withValues(alpha: .6),
                  shape: RoundedRectangleBorder(
                    borderRadius: MishkatRadius.brMd,
                  ),
                  title: const Text(
                    'السورة كاملة',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'أو عطّل الخيار وحدد بداية ونهاية.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _wholeSurah,
                  onChanged: (value) => setState(() {
                    _wholeSurah = value;
                    _startAyah = 1;
                    _endAyah = value ? totalAyahs : totalAyahs.clamp(1, 5);
                  }),
                ),
                if (!_wholeSurah) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('free-start-$_surah-$_startAyah'),
                          initialValue: _startAyah,
                          decoration: const InputDecoration(
                            labelText: 'من الآية',
                          ),
                          items: List.generate(totalAyahs, (index) => index + 1)
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text('$value'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _startAyah = value;
                              if (_endAyah < value) _endAyah = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey(
                            'free-end-$_surah-$_startAyah-$_endAyah',
                          ),
                          initialValue: _endAyah,
                          decoration: const InputDecoration(
                            labelText: 'إلى الآية',
                          ),
                          items:
                              List.generate(
                                    totalAyahs - _startAyah + 1,
                                    (index) => _startAyah + index,
                                  )
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text('$value'),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => _endAyah = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 12),
              Text(
                selection == null
                    ? 'اختر نطاق صفحات من 1 إلى $_pageCount.'
                    : '${_byPages ? '${selection.endPage! - selection.startPage! + 1} صفحة · ' : ''}$selectedCount آية محددة',
                key: const ValueKey('recitation-range-count'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              MishkatPrimaryAction(
                label: 'متابعة إلى التسميع',
                icon: const Icon(Icons.mic_rounded),
                isFullWidth: true,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageField({required bool isStart}) {
    return TextFormField(
      key: ValueKey(isStart ? 'free-start-page' : 'free-end-page'),
      controller: isStart ? _startPage : _endPage,
      keyboardType: TextInputType.number,
      textInputAction: isStart ? TextInputAction.next : TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]')),
        LengthLimitingTextInputFormatter(4),
      ],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: isStart ? 'من صفحة' : 'إلى صفحة',
        helperText: 'من 1 إلى $_pageCount',
        errorMaxLines: 3,
      ),
      validator: (value) {
        final error = _validatePage(value);
        if (error != null) return error;
        if (!isStart && _number(value)! < (_number(_startPage.text) ?? 1)) {
          return 'صفحة النهاية تسبق البداية';
        }
        return null;
      },
      onChanged: (_) => setState(() {}),
      onFieldSubmitted: (_) {
        if (!isStart) _submit();
      },
    );
  }
}
