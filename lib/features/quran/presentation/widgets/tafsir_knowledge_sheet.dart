import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/mushaf_layout_models.dart';
import '../../data/models/quran_models.dart';
import '../../data/repositories/tafsir_repository.dart';
import '../cubit/tafsir_cubit.dart';
import '../cubit/tafsir_state.dart';

/// Interactive knowledge sheet presenting authentic Quran commentary (Tafsir),
/// source attribution, and Quranic verse context for a selected Ayah.
class TafsirKnowledgeSheet extends StatefulWidget {
  const TafsirKnowledgeSheet({
    super.key,
    required this.ayah,
    required this.quranData,
    this.initialSourceId,
    this.repository,
  });

  final AyahBounds ayah;
  final QuranData quranData;
  final String? initialSourceId;
  final TafsirRepository? repository;

  /// Presents the [TafsirKnowledgeSheet] as an animated modal bottom sheet.
  static Future<void> show({
    required BuildContext context,
    required AyahBounds ayah,
    required QuranData quranData,
    String? initialSourceId,
    TafsirRepository? repository,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TafsirKnowledgeSheet(
        ayah: ayah,
        quranData: quranData,
        initialSourceId: initialSourceId,
        repository: repository,
      ),
    );
  }

  @override
  State<TafsirKnowledgeSheet> createState() => _TafsirKnowledgeSheetState();
}

class _TafsirKnowledgeSheetState extends State<TafsirKnowledgeSheet> {
  TafsirCubit? _localCubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localCubit == null) {
      try {
        context.read<TafsirCubit>();
      } catch (_) {
        _localCubit = TafsirCubit(
          repository: widget.repository,
        )..loadTafsir(widget.ayah.globalAyah, sourceId: widget.initialSourceId);
      }
    }
  }

  @override
  void dispose() {
    _localCubit?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_localCubit != null) {
      return BlocProvider.value(
        value: _localCubit!,
        child: _buildContent(context),
      );
    }
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chapter = widget.quranData.chapter(widget.ayah.surah);
    final ayahIndex = (widget.ayah.ayah - 1).clamp(0, chapter.ayahs.length - 1);
    final ayahText = chapter.ayahs.isNotEmpty ? chapter.ayahs[ayahIndex] : '';
    final juzNumber = _juzFor(widget.quranData, widget.ayah.globalAyah);

    final backgroundColor = isDark
        ? const Color(0xFF16241D)
        : const Color(0xFFFAF7F2);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFDED8CD);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 28,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sheet Drag Handle Pill
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.2,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Top Header Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: isDark ? 0.2 : 0.12,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.menu_book_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تفسير ${chapter.name}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'الآية ${widget.ayah.ayah} · الجزء $juzNumber · صفحة ${widget.ayah.page}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'إغلاق',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 16, thickness: 0.8),

                    // Scrollable Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Authentic Quran Verse Text Block
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.black.withValues(alpha: 0.22)
                                    : const Color(0xFFF1EBE1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : const Color(0xFFE2D9CB),
                                ),
                              ),
                              child: Text(
                                '﴿ $ayahText ﴾',
                                textAlign: TextAlign.center,
                                textDirection: TextDirection.rtl,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  height: 1.85,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFFE7ECE8)
                                      : const Color(0xFF1E2822),
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // Tafsir Body via BlocBuilder
                            BlocBuilder<TafsirCubit, TafsirState>(
                              builder: (context, state) {
                                if (state.isLoading) {
                                  return _buildLoadingState(context);
                                }
                                if (state.isError) {
                                  return _buildErrorState(context, state);
                                }
                                if (state.isUnavailable) {
                                  return _buildUnavailableState(context);
                                }
                                if (state.isLoaded && state.entry != null) {
                                  return _buildLoadedContent(
                                    context,
                                    state,
                                    isDark,
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text(
            'جارٍ جلب التفسير الموثّق…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, TafsirState state) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              state.errorMessage ?? 'تعذر تحميل التفسير.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => context.read<TafsirCubit>().loadTafsir(
                widget.ayah.globalAyah,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailableState(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 36,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'لا يتوفر التفسير لهذه الآية حاليًا.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedContent(
    BuildContext context,
    TafsirState state,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final source = state.selectedSource;
    final entry = state.entry!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Source Header Row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source?.name ?? 'التفسير الميسر',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (source?.author.isNotEmpty ?? false)
                    Text(
                      source!.author,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.65,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (state.availableSources.length > 1)
              _buildSourceDropdown(context, state),
          ],
        ),

        const SizedBox(height: 14),

        // Commentary Body Text
        SelectableText(
          entry.text,
          textAlign: TextAlign.justify,
          textDirection: TextDirection.rtl,
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.8,
            fontSize: 16.5,
            color: isDark ? const Color(0xFFDEE5DF) : const Color(0xFF222C25),
          ),
        ),

        const SizedBox(height: 24),

        // Source Attribution Footer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_outlined,
                size: 16,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source?.attribution ?? 'مأخوذ وموثق من مجمع الملك فهد لطباعة المصحف الشريف بالمدينة المنورة عبر موسوعة القرآن الكريم (QuranEnc.com)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    height: 1.45,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourceDropdown(BuildContext context, TafsirState state) {
    return PopupMenuButton<String>(
      tooltip: 'اختيار مصدر التفسير',
      initialValue: state.selectedSource?.id,
      onSelected: (sourceId) {
        context.read<TafsirCubit>().changeSource(sourceId);
      },
      itemBuilder: (context) => [
        for (final src in state.availableSources)
          PopupMenuItem<String>(
            value: src.id,
            child: Row(
              children: [
                Expanded(child: Text(src.name)),
                if (src.id == state.selectedSource?.id)
                  const Icon(Icons.check_rounded, size: 18),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'المصدر',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  int _juzFor(QuranData data, int global) {
    var value = 1;
    for (final juz in data.juz) {
      if (data.globalFor(juz.surah, juz.ayah) <= global) value = juz.number;
    }
    return value;
  }
}
