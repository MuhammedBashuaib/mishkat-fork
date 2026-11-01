import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/navigation_icons.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/library_models.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';

class LibraryReaderPage extends StatefulWidget {
  const LibraryReaderPage({super.key});

  @override
  State<LibraryReaderPage> createState() => _LibraryReaderPageState();
}

class _LibraryReaderPageState extends State<LibraryReaderPage> {
  PageController? _controller;
  var _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final cubit = context.read<LibraryCubit>();
    final book = cubit.state.selectedBook;
    _index = book == null ? 0 : cubit.readingIndexFor(book.id);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<LibraryCubit, LibraryState>(
    builder: (context, state) {
      final book = state.selectedBook;
      final entries = state.entries;
      if (book == null || entries.isEmpty) {
        return const Scaffold(
          body: ContentStatePanel(
            icon: Icons.menu_book_outlined,
            title: 'الكتاب غير متاح',
            message: 'ارجع إلى المكتبة واختر كتابًا.',
          ),
        );
      }
      final safeIndex = _index.clamp(0, entries.length - 1);
      final entry = entries[safeIndex];
      final bookmarked = context.read<LibraryCubit>().isBookmarked(
        book.id,
        entry.id,
      );

      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(MishkatNavigationIcons.back),
            tooltip: 'رجوع',
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                '${book.itemLabel} ${safeIndex + 1} من ${entries.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: context.mishkat.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'العلامات المحفوظة',
              onPressed: () => _showBookmarks(context, book, entries),
              icon: const Icon(Icons.bookmarks_outlined),
            ),
            IconButton(
              tooltip: bookmarked ? 'إزالة العلامة' : 'حفظ علامة هنا',
              onPressed: () => context.read<LibraryCubit>().toggleBookmark(
                book.id,
                entry.id,
              ),
              icon: Icon(
                bookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: bookmarked ? context.mishkat.primary : null,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            LinearProgressIndicator(
              value: (safeIndex + 1) / entries.length,
              minHeight: 3,
              backgroundColor: context.mishkat.surfaceMuted,
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: entries.length,
                onPageChanged: (value) {
                  setState(() => _index = value);
                  context.read<LibraryCubit>().saveReadingPosition(
                    book.id,
                    entries[value].id,
                  );
                },
                itemBuilder: (context, index) => _ReadingPage(
                  book: book,
                  entry: entries[index],
                  index: index,
                  total: entries.length,
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: context.mishkat.surface,
                  border: Border(
                    top: BorderSide(color: context.mishkat.border),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: safeIndex == 0
                            ? null
                            : () => _goTo(safeIndex - 1),
                        icon: const Icon(MishkatNavigationIcons.back),
                        label: const Text('السابق'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${safeIndex + 1} / ${entries.length}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: safeIndex == entries.length - 1
                            ? null
                            : () => _goTo(safeIndex + 1),
                        icon: const Icon(MishkatNavigationIcons.forward),
                        label: const Text('التالي'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _goTo(int index) => _controller!.animateToPage(
    index,
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeOutCubic,
  );

  Future<void> _showBookmarks(
    BuildContext context,
    LibraryBook book,
    List<LibraryEntry> entries,
  ) async {
    final cubit = context.read<LibraryCubit>();
    final marked = entries.indexed
        .where((item) => cubit.isBookmarked(book.id, item.$2.id))
        .toList();
    final selected = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => marked.isEmpty
          ? const ContentStatePanel(
              icon: Icons.bookmark_border_rounded,
              title: 'لا توجد علامات بعد',
              message: 'احفظ أي موضع لتعود إليه مباشرة من هنا.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(
                  'علاماتك في ${book.title}',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                for (final item in marked)
                  ListTile(
                    leading: const Icon(Icons.bookmark_rounded),
                    title: Text(item.$2.title),
                    subtitle: Text(item.$2.chapter),
                    trailing: Text('${item.$1 + 1}'),
                    onTap: () => Navigator.pop(sheetContext, item.$1),
                  ),
              ],
            ),
    );
    if (selected != null) await _goTo(selected);
  }
}

class _ReadingPage extends StatelessWidget {
  const _ReadingPage({
    required this.book,
    required this.entry,
    required this.index,
    required this.total,
  });

  final LibraryBook book;
  final LibraryEntry entry;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paperColor = isDark
        ? const Color(0xFF2C251C)
        : const Color(0xFFF1E4CE);
    final paperBorderColor = isDark
        ? const Color(0xFF5D4B35)
        : const Color(0xFFD8C09A);
    final inkColor = isDark ? const Color(0xFFF1E3CB) : const Color(0xFF3D3023);

    return SingleChildScrollView(
      key: PageStorageKey(entry.id),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            entry.chapter,
            style: TextStyle(
              color: context.mishkat.gold,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          MishkatCard(
            color: paperColor,
            borderColor: paperBorderColor,
            padding: const EdgeInsets.all(22),
            child: Text(
              entry.text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: inkColor,
                fontSize: 18,
                height: 2.05,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            entry.reference,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              height: 1.5,
              color: context.mishkat.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text:
                          '${entry.title}\n\n${entry.text}\n\n${entry.reference}',
                    ),
                  );
                  if (context.mounted) context.showMessage('تم نسخ النص.');
                },
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: const Text('نسخ'),
              ),
              if (entry.sourceUrl.isNotEmpty)
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(entry.sourceUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('المصدر'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
