import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/quran_search_models.dart';
import '../services/quran_search_highlighter.dart';

/// Card tile presenting an individual Ayah search result with RTL match highlighting
/// and deep navigation actions (Mushaf, Tafsir, Audio, Copy).
class QuranSearchResultTile extends StatelessWidget {
  const QuranSearchResultTile({
    super.key,
    required this.result,
    required this.onTapMushaf,
    required this.onTapTafsir,
    required this.onTapPlay,
  });

  final QuranAyahSearchResult result;
  final VoidCallback onTapMushaf;
  final VoidCallback onTapTafsir;
  final VoidCallback onTapPlay;

  void _copyToClipboard(BuildContext context) {
    final text =
        '﴿ ${result.originalText} ﴾ [${result.surahName}: ${result.ayah}]';
    Clipboard.setData(ClipboardData(text: text));
    context.showMessage('تم نسخ الآية الكريمة');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final defaultTextStyle = TextStyle(
      fontSize: 16,
      height: 1.8,
      fontFamily: 'Amiri',
      color: theme.textTheme.bodyLarge?.color,
    );

    final highlightTextStyle = TextStyle(
      fontSize: 16,
      height: 1.8,
      fontFamily: 'Amiri',
      fontWeight: FontWeight.w800,
      backgroundColor: isDark
          ? context.mishkat.gold.withValues(alpha: 0.35)
          : context.mishkat.gold.withValues(alpha: 0.25),
      color: isDark ? context.mishkat.gold : const Color(0xFF8C5A00),
    );

    final highlightedSpan = QuranSearchHighlighter.buildHighlightedSpan(
      text: result.originalText,
      ranges: result.matchRanges,
      defaultStyle: defaultTextStyle,
      highlightStyle: highlightTextStyle,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: MishkatSpacing.sm),
      child: MishkatCard(
        padding: const EdgeInsets.all(MishkatSpacing.base),
        onTap: onTapMushaf,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row: Surah Name & Ayah info + Actions
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MishkatSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: context.mishkat.primarySoft,
                    borderRadius: BorderRadius.circular(MishkatRadius.xs),
                    border: Border.all(
                      color: context.mishkat.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    'سورة ${result.surahName} · آية ${result.ayah}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.mishkat.primary,
                    ),
                  ),
                ),
                const SizedBox(width: MishkatSpacing.xs),
                Text(
                  'صفحة ${result.page}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.mishkat.textSecondary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: 'نسخ الآية',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copyToClipboard(context),
                ),
              ],
            ),
            const SizedBox(height: MishkatSpacing.sm),

            // Ayah Text with Highlight
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text.rich(highlightedSpan, textAlign: TextAlign.right),
            ),
            const SizedBox(height: MishkatSpacing.sm),

            // Footer Quick Action Buttons
            Wrap(
              spacing: MishkatSpacing.xs,
              runSpacing: MishkatSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: onTapMushaf,
                  icon: const Icon(Icons.menu_book_rounded, size: 16),
                  label: const Text('المصحف', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onTapTafsir,
                  icon: const Icon(Icons.school_outlined, size: 16),
                  label: const Text('التفسير', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onTapPlay,
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('استماع', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
