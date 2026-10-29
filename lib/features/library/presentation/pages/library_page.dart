import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../../khatma/presentation/pages/khatma_page.dart';
import '../../data/models/library_models.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';
import 'library_reader_page.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<LibraryCubit, LibraryState>(
    builder: (context, state) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<LibrarySection>(
              segments: const [
                ButtonSegment(
                  value: LibrarySection.books,
                  icon: Icon(Icons.local_library_outlined, size: 18),
                  label: Text('المكتبة'),
                ),
                ButtonSegment(
                  value: LibrarySection.khatma,
                  icon: Icon(Icons.route_outlined, size: 18),
                  label: Text('خطة الختمة'),
                ),
              ],
              selected: {state.section},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  context.read<LibraryCubit>().setSection(value.first),
            ),
          ),
        ),
        Expanded(
          child: state.section == LibrarySection.books
              ? _BooksView(state: state)
              : const KhatmaPage(),
        ),
      ],
    ),
  );
}

class _BooksView extends StatelessWidget {
  const _BooksView({required this.state});
  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    if (state.status == LibraryStatus.loading && state.books.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == LibraryStatus.failure && state.books.isEmpty) {
      return ContentStatePanel(
        icon: Icons.local_library_outlined,
        title: 'تعذّر تحميل المكتبة',
        message: state.error ?? 'حدث خطأ غير متوقع.',
        action: MishkatPrimaryButton(
          onPressed: context.read<LibraryCubit>().load,
          label: 'إعادة المحاولة',
        ),
      );
    }

    final cubit = context.read<LibraryCubit>();
    final books = cubit.filteredBooks();
    final categories = [
      'الكل',
      ...{for (final book in state.books) book.category},
    ];
    final totalItems = state.books.fold<int>(
      0,
      (total, book) => total + book.availableItems,
    );
    final recent = state.history.isEmpty
        ? null
        : state.books
              .where((book) => book.id == state.history.first)
              .firstOrNull;

    return ListView(
      key: const PageStorageKey('library-books'),
      padding: MishkatSpacing.page,
      children: [
        Text(
          'معرفة موثّقة',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: context.mishkat.gold,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'المكتبة الإسلامية',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          '${state.books.length} كتب · $totalItems مادة عربية · تعمل دون إنترنت',
          style: TextStyle(color: context.mishkat.textSecondary, height: 1.5),
        ),
        if (recent != null) ...[
          const SizedBox(height: 20),
          _ContinueReadingCard(
            book: recent,
            hasSavedPosition: state.readingPositions.containsKey(recent.id),
            onTap: () => _openBook(context, recent),
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          onChanged: cubit.search,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'ابحث عن كتاب أو مؤلف',
          ),
        ),
        const SectionHeading(
          title: 'تصفّح حسب المجال',
          padding: EdgeInsets.only(top: 22, bottom: 10),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = categories[index];
              return _CategoryChip(
                label: category,
                selected: state.category == category,
                onTap: () => cubit.setCategory(category),
              );
            },
          ),
        ),
        SectionHeading(
          title: state.query.isEmpty
              ? state.category == 'الكل'
                    ? 'كل الكتب'
                    : state.category
              : '${books.length} نتيجة',
          padding: const EdgeInsets.only(top: 24, bottom: 10),
        ),
        if (books.isEmpty)
          const ContentStatePanel(
            icon: Icons.search_off_rounded,
            title: 'لا توجد نتائج',
            message: 'جرّب اسم كتاب أو مؤلف أو مجال آخر.',
          )
        else
          for (final book in books)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _BookCard(
                book: book,
                bookmarkCount: cubit.bookmarksForBook(book.id),
                hasSavedPosition: state.readingPositions.containsKey(book.id),
                loading:
                    state.status == LibraryStatus.loading &&
                    state.selectedBook?.id == book.id,
              ),
            ),
        const SizedBox(height: 8),
        MishkatCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_outlined, color: context.mishkat.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'نعرض مصدر كل نص بوضوح. بيانات كتب الحديث عربية ومهيكلة من Open Hadith Data، والتفسير الميسر من QuranEnc.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: context.mishkat.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({
    required this.book,
    required this.hasSavedPosition,
    required this.onTap,
  });
  final LibraryBook book;
  final bool hasSavedPosition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MishkatCard(
    onTap: onTap,
    color: context.mishkat.primarySoft,
    borderColor: context.mishkat.primary.withValues(alpha: 0.18),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 54,
          decoration: BoxDecoration(
            color: context.mishkat.surface,
            borderRadius: MishkatRadius.brMd,
          ),
          child: Icon(
            Icons.auto_stories_rounded,
            color: context.mishkat.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasSavedPosition ? 'تابع من موضعك' : 'آخر كتاب فتحته',
                style: TextStyle(
                  fontSize: 11.5,
                  color: context.mishkat.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_left_rounded, color: context.mishkat.primary),
      ],
    ),
  );
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.bookmarkCount,
    required this.hasSavedPosition,
    required this.loading,
  });
  final LibraryBook book;
  final int bookmarkCount;
  final bool hasSavedPosition;
  final bool loading;

  @override
  Widget build(BuildContext context) => MishkatCard(
    padding: const EdgeInsets.all(14),
    onTap: loading ? null : () => _openBook(context, book),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 72,
          decoration: BoxDecoration(
            color: _bookColor(context, book).withValues(alpha: 0.14),
            borderRadius: MishkatRadius.brMd,
            border: Border.all(
              color: _bookColor(context, book).withValues(alpha: 0.25),
            ),
          ),
          child: Icon(
            _bookIcon(book),
            size: 27,
            color: _bookColor(context, book),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: context.mishkat.textSecondary,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _MetaLabel(
                    icon: Icons.menu_book_outlined,
                    text: '${book.availableItems} ${book.itemLabel}',
                  ),
                  if (hasSavedPosition)
                    const _MetaLabel(
                      icon: Icons.history_rounded,
                      text: 'موضع محفوظ',
                    ),
                  if (bookmarkCount > 0)
                    _MetaLabel(
                      icon: Icons.bookmark_rounded,
                      text: '$bookmarkCount علامة',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      book.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.mishkat.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (loading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    Icon(
                      Icons.chevron_left_rounded,
                      color: context.mishkat.textMuted,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: context.mishkat.surfaceMuted,
      borderRadius: MishkatRadius.brPill,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: context.mishkat.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: context.mishkat.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : context.mishkat.textSecondary;
    return Material(
      color: selected ? context.mishkat.brandDeep : context.mishkat.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? context.mishkat.primary : context.mishkat.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openBook(BuildContext context, LibraryBook book) async {
  final cubit = context.read<LibraryCubit>();
  await cubit.openBook(book);
  if (!context.mounted) return;

  if (cubit.state.status == LibraryStatus.ready) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const LibraryReaderPage()),
    );
    return;
  }

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(cubit.state.error ?? 'تعذّر فتح الكتاب، حاول مرة أخرى.'),
      ),
    );
}

IconData _bookIcon(LibraryBook book) => switch (book.category) {
  'التفسير وعلوم القرآن' => Icons.auto_stories_outlined,
  'أذكار وأدعية' => Icons.volunteer_activism_outlined,
  'السيرة والشمائل' => Icons.favorite_outline_rounded,
  'أحكام وفقه' => Icons.balance_outlined,
  _ => Icons.menu_book_rounded,
};

Color _bookColor(BuildContext context, LibraryBook book) => switch (book.id) {
  'bukhari' => context.mishkat.primary,
  'muslim' => context.mishkat.gold,
  'tafsir-muyassar' => context.mishkat.success,
  'hisn' => context.mishkat.warning,
  _ => context.mishkat.primaryStrong,
};
