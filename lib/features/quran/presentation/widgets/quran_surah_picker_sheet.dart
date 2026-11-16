import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../data/models/quran_models.dart';
import '../services/quran_surah_search.dart';

class QuranSurahPickerSheet extends StatefulWidget {
  const QuranSurahPickerSheet({
    required this.chapters,
    required this.reciterName,
    required this.onSelected,
    super.key,
  });

  final List<QuranChapter> chapters;
  final String reciterName;
  final ValueChanged<QuranChapter> onSelected;

  @override
  State<QuranSurahPickerSheet> createState() => _QuranSurahPickerSheetState();
}

class _QuranSurahPickerSheetState extends State<QuranSurahPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapters = QuranSurahSearch.findChapters(widget.chapters, _query);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: DraggableScrollableSheet(
        initialChildSize: keyboard > 0 ? 0.9 : 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => ListView.builder(
          controller: scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: chapters.isEmpty ? 2 : chapters.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(MishkatSpacing.base),
                    child: Column(
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'اختر السورة للاستماع بصوت ${widget.reciterName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _search,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'ابحث باسم السورة أو رقمها',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'مسح البحث',
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: () {
                                      _search.clear();
                                      if (scrollController.hasClients) {
                                        scrollController.jumpTo(0);
                                      }
                                      setState(() => _query = '');
                                    },
                                  ),
                          ),
                          onChanged: (value) {
                            if (scrollController.hasClients) {
                              scrollController.jumpTo(0);
                            }
                            setState(() => _query = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
              );
            }
            if (chapters.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا توجد سور مطابقة لبحثك',
                  textAlign: TextAlign.center,
                ),
              );
            }
            final chapter = chapters[index - 1];
            return ListTile(
              key: ValueKey(chapter.number),
              leading: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.mishkat.primarySoft,
                  borderRadius: BorderRadius.circular(MishkatRadius.sm),
                ),
                child: Text(
                  '${chapter.number}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.mishkat.primary,
                  ),
                ),
              ),
              title: Text(
                'سورة ${chapter.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${chapter.revelationType} · ${chapter.ayahs.length} آية · صفحة ${chapter.page}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.play_circle_fill_rounded),
              onTap: () => widget.onSelected(chapter),
            );
          },
        ),
      ),
    );
  }
}
