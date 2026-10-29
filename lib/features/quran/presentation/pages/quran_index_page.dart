import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/quran_models.dart';
import '../../data/repositories/mushaf_layout_repository.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_state.dart';
import '../services/quran_search_normalizer.dart';
import '../widgets/tafsir_knowledge_sheet.dart';
import 'quran_reader_page.dart';
import 'quran_search_page.dart';

/// Dedicated index page for browsing Surahs, Juz, and Bookmarks.
class QuranIndexPage extends StatefulWidget {
  const QuranIndexPage({super.key, this.initialMode = QuranIndexMode.surahs});

  final QuranIndexMode initialMode;

  static Route<void> route({
    QuranIndexMode initialMode = QuranIndexMode.surahs,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => QuranIndexPage(initialMode: initialMode),
    );
  }

  @override
  State<QuranIndexPage> createState() => _QuranIndexPageState();
}

class _QuranIndexPageState extends State<QuranIndexPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    final initialIndex = switch (widget.initialMode) {
      QuranIndexMode.surahs => 0,
      QuranIndexMode.juz => 1,
      QuranIndexMode.bookmarks => 2,
    };
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;

    return BlocBuilder<QuranCubit, QuranState>(
      builder: (context, state) {
        if (state.data == null) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('فهرس القرآن الكريم'),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final data = state.data!;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'رجوع',
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'فهرس القرآن الكريم',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'البحث الشامل',
                icon: const Icon(Icons.search_rounded),
                onPressed: () =>
                    Navigator.push(context, QuranSearchPage.route()),
              ),
            ],
          ),
          body: Column(
            children: [
              // 1. Reading Continuation Banner (Last Read)
              _buildContinuationBanner(context, state),

              // 2. Filter / Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MishkatSpacing.base,
                  vertical: MishkatSpacing.xs,
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: switch (_tabController.index) {
                      0 => 'ابحث باسم السورة أو رقمها...',
                      1 => 'ابحث برقم الجزء أو السورة...',
                      _ => 'ابحث في العلامات المحفوظة...',
                    },
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_filter.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _filter = '');
                            },
                          ),
                        IconButton(
                          tooltip: 'البحث في نص الآيات',
                          icon: const Icon(
                            Icons.travel_explore_rounded,
                            size: 20,
                          ),
                          onPressed: () =>
                              Navigator.push(context, QuranSearchPage.route()),
                        ),
                      ],
                    ),
                  ),
                  onChanged: (val) => setState(() => _filter = val.trim()),
                ),
              ),

              // 3. Three Primary Tabs: السور / الأجزاء / العلامات
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor
                          .withValues(alpha: 0.15),
                    ),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: colors.primary,
                  indicatorWeight: 3,
                  labelColor: colors.primary,
                  unselectedLabelColor: colors.textSecondary,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  tabs: const [
                    Tab(text: 'السور'),
                    Tab(text: 'الأجزاء'),
                    Tab(text: 'العلامات'),
                  ],
                ),
              ),

              // 4. Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSurahsList(context, data),
                    _buildJuzList(context, data),
                    _IndexBookmarksList(state: state, filter: _filter),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContinuationBanner(BuildContext context, QuranState state) {
    final colors = context.mishkat;
    final data = state.data!;
    final lastRead = state.lastRead;
    final point = lastRead ?? data.page(state.currentPage).first;
    final chapter = data.chapter(point.surah);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MishkatSpacing.base,
        MishkatSpacing.xs,
        MishkatSpacing.base,
        MishkatSpacing.xs,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(MishkatRadius.md),
        onTap: () async {
          final targetPoint =
              state.lastRead ?? data.page(state.currentPage).first;
          final targetPage = data.pageForGlobal(targetPoint.global);
          await context.read<QuranCubit>().openPage(
            targetPage,
            point: targetPoint,
          );
          if (context.mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    QuranReaderPage(initialGlobalAyah: targetPoint.global),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.primarySoft.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(MishkatRadius.md),
            border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bookmark_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lastRead != null ? 'متابعة آخر قراءة' : 'ابدأ القراءة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      lastRead != null
                          ? 'سورة ${chapter.name} · صفحة ${state.currentPage} · آية ${point.ayah}'
                          : 'سورة الفاتحة · صفحة 1',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(MishkatRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'استئناف',
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_back_rounded,
                      size: 14,
                      color: colors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSurahsList(BuildContext context, QuranData data) {
    final filteredChapters = _filter.isEmpty
        ? data.chapters
        : data.chapters
              .where((c) {
                final rawQuery = _filter.trim();
                final normQuery = QuranSearchNormalizer.normalize(
                  QuranSearchNormalizer.convertArabicDigits(rawQuery),
                );
                final numQuery = int.tryParse(normQuery);
                if (numQuery != null && c.number == numQuery) return true;

                final normName = QuranSearchNormalizer.normalize(c.name);
                if (normName.contains(normQuery)) return true;

                if (c.englishName.toLowerCase().contains(
                  rawQuery.toLowerCase(),
                )) {
                  return true;
                }

                final normRev = QuranSearchNormalizer.normalize(
                  c.revelationType,
                );
                if (normRev.contains(normQuery)) return true;

                return false;
              })
              .toList(growable: false);

    if (filteredChapters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(MishkatSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: context.mishkat.textMuted,
              ),
              const SizedBox(height: 12),
              const Text(
                'لا توجد سورة مطابقة للبحث',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'جرّب البحث باسم السورة أو رقمها',
                style: TextStyle(
                  color: context.mishkat.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: MishkatSpacing.page,
      itemCount: filteredChapters.length,
      itemBuilder: (context, index) {
        final chapter = filteredChapters[index];
        return _IndexTile(
          number: chapter.number,
          title: 'سورة ${chapter.name}',
          subtitle:
              '${chapter.revelationType} · ${chapter.ayahs.length} آية · صفحة ${chapter.page}',
          onTap: () async {
            await context.read<QuranCubit>().openSurah(chapter.number);
            final global = data.globalFor(chapter.number, 1);
            if (context.mounted) {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => QuranReaderPage(initialGlobalAyah: global),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildJuzList(BuildContext context, QuranData data) {
    final filteredJuz = _filter.isEmpty
        ? data.juz
        : data.juz
              .where((j) {
                final rawQuery = _filter.trim();
                final normQuery = QuranSearchNormalizer.normalize(
                  QuranSearchNormalizer.convertArabicDigits(rawQuery),
                );
                final numQuery = int.tryParse(normQuery);
                if (numQuery != null && j.number == numQuery) return true;

                final chapter = data.chapter(j.surah);
                final normChapter = QuranSearchNormalizer.normalize(
                  chapter.name,
                );
                if (normChapter.contains(normQuery)) return true;

                return false;
              })
              .toList(growable: false);

    if (filteredJuz.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(MishkatSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: context.mishkat.textMuted,
              ),
              const SizedBox(height: 12),
              const Text(
                'لا توجد نتائج مطابقة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'جرّب البحث برقم الجزء من 1 إلى 30',
                style: TextStyle(
                  color: context.mishkat.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: MishkatSpacing.page,
      itemCount: filteredJuz.length,
      itemBuilder: (context, index) {
        final juz = filteredJuz[index];
        final chapter = data.chapter(juz.surah);
        final global = data.globalFor(juz.surah, juz.ayah);
        final page = data.pageForGlobal(global);
        return _IndexTile(
          number: juz.number,
          title: 'الجزء ${juz.number}',
          subtitle: 'سورة ${chapter.name} · آية ${juz.ayah} · صفحة $page',
          onTap: () async {
            await context.read<QuranCubit>().openJuz(juz.number);
            if (context.mounted) {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => QuranReaderPage(initialGlobalAyah: global),
                ),
              );
            }
          },
        );
      },
    );
  }
}

class _IndexTile extends StatelessWidget {
  const _IndexTile({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final int number;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: MishkatSpacing.xs),
    child: MishkatCard(
      padding: const EdgeInsets.symmetric(
        horizontal: MishkatSpacing.md,
        vertical: MishkatSpacing.sm,
      ),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.mishkat.primarySoft,
              borderRadius: BorderRadius.circular(MishkatRadius.md),
              border: Border.all(
                color: context.mishkat.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: context.mishkat.primary,
                fontSize: 13.5,
              ),
            ),
          ),
          const SizedBox(width: MishkatSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.mishkat.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_left_rounded,
            color: context.mishkat.textMuted,
            size: 22,
          ),
        ],
      ),
    ),
  );
}

enum _BookmarkSortMode { recent, mushafOrder }

class _IndexBookmarksList extends StatefulWidget {
  const _IndexBookmarksList({required this.state, this.filter = ''});
  final QuranState state;
  final String filter;

  @override
  State<_IndexBookmarksList> createState() => _IndexBookmarksListState();
}

class _IndexBookmarksListState extends State<_IndexBookmarksList> {
  _BookmarkSortMode _sortMode = _BookmarkSortMode.recent;

  @override
  Widget build(BuildContext context) {
    final bookmarks = widget.state.bookmarks;
    if (bookmarks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MishkatSpacing.xl,
          vertical: MishkatSpacing.xxl,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.mishkat.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bookmark_border_rounded,
                size: 32,
                color: context.mishkat.primary,
              ),
            ),
            const SizedBox(height: MishkatSpacing.md),
            Text(
              'لا توجد علامات محفوظة بعد',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: MishkatSpacing.xs),
            Text(
              'يمكنك حفظ أي آية بالضغط عليها في المصحف أو من قائمة خيارات الآية.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.mishkat.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    final query = widget.filter.trim();
    final filtered = query.isEmpty
        ? bookmarks
        : bookmarks
              .where((b) {
                final chapter = widget.state.data!.chapter(b.point.surah);
                final normQuery = QuranSearchNormalizer.normalize(
                  QuranSearchNormalizer.convertArabicDigits(query),
                );
                final normName = QuranSearchNormalizer.normalize(chapter.name);
                if (normName.contains(normQuery)) return true;
                if (b.label != null &&
                    QuranSearchNormalizer.normalize(b.label!)
                        .contains(normQuery)) {
                  return true;
                }
                return false;
              })
              .toList(growable: false);

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(MishkatSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: context.mishkat.textMuted,
              ),
              const SizedBox(height: 12),
              const Text(
                'لا توجد علامات مطابقة للبحث',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    final sortedList = switch (_sortMode) {
      _BookmarkSortMode.recent => List<QuranBookmark>.from(
        filtered,
      )..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      _BookmarkSortMode.mushafOrder => List<QuranBookmark>.from(
        filtered,
      )..sort((a, b) => a.point.global.compareTo(b.point.global)),
    };

    return ListView(
      padding: MishkatSpacing.page,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MishkatSpacing.xs,
            vertical: MishkatSpacing.xs,
          ),
          child: Row(
            children: [
              Text(
                '${filtered.length} علامة',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.mishkat.textSecondary,
                ),
              ),
              const Spacer(),
              SegmentedButton<_BookmarkSortMode>(
                segments: const [
                  ButtonSegment(
                    value: _BookmarkSortMode.recent,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('الأحدث', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  ButtonSegment(
                    value: _BookmarkSortMode.mushafOrder,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('المصحف', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
                selected: {_sortMode},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelectionChanged: (selected) {
                  setState(() => _sortMode = selected.first);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: MishkatSpacing.sm),
        for (final bookmark in sortedList)
          _IndexBookmarkTile(
            key: ValueKey('bm_${bookmark.point.global}'),
            bookmark: bookmark,
            state: widget.state,
          ),
      ],
    );
  }
}

class _IndexBookmarkTile extends StatelessWidget {
  const _IndexBookmarkTile({
    super.key,
    required this.bookmark,
    required this.state,
  });

  final QuranBookmark bookmark;
  final QuranState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<QuranCubit>();
    final data = state.data!;
    final chapter = data.chapter(bookmark.point.surah);

    final ayahIndex = bookmark.point.ayah - 1;
    final snippet = (ayahIndex >= 0 && ayahIndex < chapter.ayahs.length)
        ? chapter.ayahs[ayahIndex]
        : '';

    return Dismissible(
      key: ValueKey('dismissible_${bookmark.point.global}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: MishkatSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(MishkatRadius.md),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'حذف',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) {
        final removed = bookmark;
        cubit.removeBookmark(removed.point.global);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم حذف الفاصل: سورة ${chapter.name} آية ${removed.point.ayah}',
            ),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'تراجع',
              onPressed: () {
                cubit.toggleAyahBookmark(
                  removed.point.global,
                  label: removed.label,
                );
              },
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: MishkatSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(MishkatRadius.md),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(MishkatRadius.md),
          onTap: () async {
            await cubit.openPage(bookmark.page, point: bookmark.point);
            if (context.mounted) {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      QuranReaderPage(initialGlobalAyah: bookmark.point.global),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(MishkatSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: context.mishkat.primarySoft,
                        borderRadius: BorderRadius.circular(MishkatRadius.sm),
                      ),
                      child: Icon(
                        Icons.bookmark_rounded,
                        size: 20,
                        color: context.mishkat.primary,
                      ),
                    ),
                    const SizedBox(width: MishkatSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'سورة ${chapter.name}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              if (bookmark.label != null &&
                                  bookmark.label!.trim().isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.mishkat.primarySoft,
                                    borderRadius: BorderRadius.circular(
                                      MishkatRadius.xs,
                                    ),
                                  ),
                                  child: Text(
                                    bookmark.label!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: context.mishkat.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'صفحة ${bookmark.page} · آية ${bookmark.point.ayah}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.mishkat.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (snippet.isNotEmpty) ...[
                  const SizedBox(height: MishkatSpacing.sm),
                  Text(
                    snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Amiri',
                      fontSize: 15,
                      height: 1.6,
                      color: context.mishkat.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: MishkatSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          _openTafsir(context, bookmark.point.global, state),
                      icon: const Icon(Icons.menu_book_rounded, size: 16),
                      label: const Text(
                        'التفسير',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => cubit.playAyah(bookmark.point.global),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text(
                        'استماع',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTafsir(
    BuildContext context,
    int globalAyah,
    QuranState state,
  ) async {
    final quranData = state.data;
    if (quranData == null) return;
    final layoutRepo = MushafLayoutRepository.instance;
    if (!layoutRepo.isLoaded) {
      await layoutRepo.load();
    }
    final ayahBounds = layoutRepo.getAyah(globalAyah);
    if (ayahBounds == null || !context.mounted) return;
    await TafsirKnowledgeSheet.show(
      context: context,
      ayah: ayahBounds,
      quranData: quranData,
    );
  }
}
