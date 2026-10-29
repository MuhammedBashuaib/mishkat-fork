import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/local_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/quran_search_models.dart';
import '../../data/repositories/mushaf_layout_repository.dart';
import '../../data/repositories/quran_search_repository.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_search_cubit.dart';
import '../cubit/quran_search_state.dart';
import '../widgets/quran_search_history_view.dart';
import '../widgets/quran_search_reference_card.dart';
import '../widgets/quran_search_result_tile.dart';
import '../widgets/tafsir_knowledge_sheet.dart';
import 'quran_reader_page.dart';

/// Full-featured Quran Search & Deep Navigation page.
class QuranSearchPage extends StatefulWidget {
  const QuranSearchPage({super.key, this.initialQuery});

  final String? initialQuery;

  static Route<void> route({String? initialQuery}) {
    return MaterialPageRoute<void>(
      builder: (_) => QuranSearchPage(initialQuery: initialQuery),
    );
  }

  @override
  State<QuranSearchPage> createState() => _QuranSearchPageState();
}

class _QuranSearchPageState extends State<QuranSearchPage> {
  late final TextEditingController _textController;
  final MushafLayoutRepository _layoutRepo = MushafLayoutRepository();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialQuery ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _navigateToMushaf({
    required BuildContext context,
    required int page,
    int? globalAyah,
  }) async {
    final searchCubit = context.read<QuranSearchCubit>();
    await searchCubit.commitSearch(_textController.text);

    if (!context.mounted) return;
    final quranCubit = context.read<QuranCubit>();
    final quranData = quranCubit.state.data;
    if (quranData == null) return;

    final point = globalAyah != null
        ? quranData.pointForGlobal(globalAyah)
        : null;
    await quranCubit.openPage(page, point: point);

    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QuranReaderPage(initialGlobalAyah: globalAyah),
      ),
    );
  }

  Future<void> _openTafsir(BuildContext context, int globalAyah) async {
    final quranData = context.read<QuranCubit>().state.data;
    if (quranData == null) return;

    if (!_layoutRepo.isLoaded) {
      await _layoutRepo.load();
    }
    final ayahBounds = _layoutRepo.getAyah(globalAyah);
    if (ayahBounds == null || !context.mounted) return;

    await TafsirKnowledgeSheet.show(
      context: context,
      ayah: ayahBounds,
      quranData: quranData,
    );
  }

  Future<void> _playAyah(BuildContext context, int globalAyah) async {
    final quranCubit = context.read<QuranCubit>();
    final point = quranCubit.state.data?.pointForGlobal(globalAyah);
    final surahName = point != null
        ? quranCubit.state.data?.chapter(point.surah).name
        : '';

    await quranCubit.playAyah(globalAyah, continuous: true, autoScroll: true);
    if (context.mounted) {
      context.showMessage(
        'بدأت تلاوة ${surahName != null ? 'سورة $surahName آية ${point?.ayah}' : 'الآية'}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final quranData = context.read<QuranCubit>().state.data;
    if (quranData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BlocProvider(
      create: (context) {
        final cubit = QuranSearchCubit(
          quranData: quranData,
          searchRepository: QuranSearchRepository(
            storage: LocalStorageService(),
          ),
        );
        if (widget.initialQuery != null &&
            widget.initialQuery!.trim().isNotEmpty) {
          cubit.onQueryChanged(widget.initialQuery!, immediate: true);
        }
        return cubit;
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Builder(
            builder: (context) {
              return TextField(
                controller: _textController,
                autofocus:
                    widget.initialQuery == null || widget.initialQuery!.isEmpty,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث عن آية، سورة، أو اكتب رقم 2:255',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: MishkatSpacing.md,
                  ),
                  suffixIcon: _textController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _textController.clear();
                            context.read<QuranSearchCubit>().clearQuery();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (val) {
                  setState(() {});
                  context.read<QuranSearchCubit>().onQueryChanged(val);
                },
                onSubmitted: (val) {
                  context.read<QuranSearchCubit>().onQueryChanged(
                    val,
                    immediate: true,
                  );
                },
              );
            },
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: BlocBuilder<QuranSearchCubit, QuranSearchState>(
              buildWhen: (prev, curr) => prev.filter != curr.filter,
              builder: (context, state) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: MishkatSpacing.md,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'الكل',
                        selected: state.filter == QuranSearchFilter.all,
                        onSelected: () => context
                            .read<QuranSearchCubit>()
                            .setFilter(QuranSearchFilter.all),
                      ),
                      const SizedBox(width: MishkatSpacing.xs),
                      _FilterChip(
                        label: 'الآيات',
                        selected: state.filter == QuranSearchFilter.ayahs,
                        onSelected: () => context
                            .read<QuranSearchCubit>()
                            .setFilter(QuranSearchFilter.ayahs),
                      ),
                      const SizedBox(width: MishkatSpacing.xs),
                      _FilterChip(
                        label: 'السور',
                        selected: state.filter == QuranSearchFilter.surahs,
                        onSelected: () => context
                            .read<QuranSearchCubit>()
                            .setFilter(QuranSearchFilter.surahs),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        body: BlocBuilder<QuranSearchCubit, QuranSearchState>(
          builder: (context, state) {
            if (state.isInitial) {
              return QuranSearchHistoryView(
                recentSearches: state.recentSearches,
                onSelectQuery: (q) {
                  _textController.text = q;
                  setState(() {});
                  context.read<QuranSearchCubit>().onQueryChanged(
                    q,
                    immediate: true,
                  );
                },
                onRemoveRecent: (q) =>
                    context.read<QuranSearchCubit>().removeRecentSearch(q),
                onClearAll: () =>
                    context.read<QuranSearchCubit>().clearRecentSearches(),
              );
            }

            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.isError) {
              return ContentStatePanel(
                icon: Icons.error_outline_rounded,
                title: 'خطأ في البحث',
                message: state.errorMessage ?? 'حدث خطأ غير متوقع.',
                action: MishkatPrimaryButton(
                  onPressed: () => context
                      .read<QuranSearchCubit>()
                      .onQueryChanged(_textController.text, immediate: true),
                  label: 'إعادة المحاولة',
                ),
              );
            }

            if (state.isEmpty || state.results.isEmpty) {
              return ContentStatePanel(
                icon: Icons.search_off_rounded,
                title: 'لا توجد نتائج',
                message:
                    'لم يتم العثور على نتائج تطابق "${state.query}". جرّب صيغة أخرى أو اكتب اسم السورة.',
              );
            }

            final results = state.results;

            return ListView(
              padding: MishkatSpacing.page,
              children: [
                // 1. Direct Reference Card
                if (results.directReference != null) ...[
                  QuranSearchReferenceCard(
                    reference: results.directReference!,
                    onTap: () => _navigateToMushaf(
                      context: context,
                      page: results.directReference!.page,
                      globalAyah: results.directReference!.globalAyah,
                    ),
                  ),
                  const SizedBox(height: MishkatSpacing.md),
                ],

                // 2. Matched Surahs
                if (results.matchedSurahs.isNotEmpty) ...[
                  Text(
                    'السور (${results.matchedSurahs.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.mishkat.textSecondary,
                    ),
                  ),
                  const SizedBox(height: MishkatSpacing.xs),
                  for (final chapter in results.matchedSurahs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: MishkatSpacing.xs),
                      child: MishkatCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MishkatSpacing.md,
                          vertical: MishkatSpacing.sm,
                        ),
                        onTap: () => _navigateToMushaf(
                          context: context,
                          page: chapter.page,
                          globalAyah: chapter.globalStart,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: context.mishkat.primarySoft,
                                borderRadius: BorderRadius.circular(
                                  MishkatRadius.sm,
                                ),
                              ),
                              child: Text(
                                '${chapter.number}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: context.mishkat.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: MishkatSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'سورة ${chapter.name}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '${chapter.revelationType} · ${chapter.ayahs.length} آية · صفحة ${chapter.page}',
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
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: MishkatSpacing.md),
                ],

                // 3. Matched Ayahs
                if (results.matchedAyahs.isNotEmpty) ...[
                  Text(
                    'الآيات الكريمة (${results.matchedAyahs.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.mishkat.textSecondary,
                    ),
                  ),
                  const SizedBox(height: MishkatSpacing.sm),
                  for (final ayahResult in results.matchedAyahs)
                    QuranSearchResultTile(
                      result: ayahResult,
                      onTapMushaf: () => _navigateToMushaf(
                        context: context,
                        page: ayahResult.page,
                        globalAyah: ayahResult.globalAyah,
                      ),
                      onTapTafsir: () =>
                          _openTafsir(context, ayahResult.globalAyah),
                      onTapPlay: () =>
                          _playAyah(context, ayahResult.globalAyah),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
    );
  }
}
