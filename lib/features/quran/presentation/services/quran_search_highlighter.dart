import 'package:flutter/material.dart';

import '../../data/models/quran_search_models.dart';

/// Utility to build rich highlighted [TextSpan] trees from Quran text and match ranges.
class QuranSearchHighlighter {
  const QuranSearchHighlighter._();

  /// Merges overlapping and consecutive [TextMatchRange] elements.
  static List<TextMatchRange> mergeRanges(List<TextMatchRange> ranges) {
    if (ranges.length <= 1) return ranges;

    final sorted = List<TextMatchRange>.from(ranges)
      ..sort((a, b) => a.start.compareTo(b.start));

    final merged = <TextMatchRange>[sorted.first];

    for (var i = 1; i < sorted.length; i++) {
      final current = sorted[i];
      final last = merged.last;

      if (current.start <= last.end) {
        // Overlapping or contiguous
        final newEnd = current.end > last.end ? current.end : last.end;
        merged[merged.length - 1] = TextMatchRange(
          start: last.start,
          end: newEnd,
        );
      } else {
        merged.add(current);
      }
    }

    return merged;
  }

  /// Builds a [TextSpan] containing highlighted spans for matching portions of [text].
  static TextSpan buildHighlightedSpan({
    required String text,
    required List<TextMatchRange> ranges,
    required TextStyle defaultStyle,
    required TextStyle highlightStyle,
  }) {
    if (ranges.isEmpty || text.isEmpty) {
      return TextSpan(text: text, style: defaultStyle);
    }

    final merged = mergeRanges(ranges);
    final spans = <InlineSpan>[];
    var currentIndex = 0;

    for (final range in merged) {
      final start = range.start.clamp(0, text.length);
      final end = range.end.clamp(0, text.length);

      if (start > currentIndex) {
        spans.add(
          TextSpan(
            text: text.substring(currentIndex, start),
            style: defaultStyle,
          ),
        );
      }

      if (end > start) {
        spans.add(
          TextSpan(text: text.substring(start, end), style: highlightStyle),
        );
      }

      currentIndex = end;
    }

    if (currentIndex < text.length) {
      spans.add(
        TextSpan(text: text.substring(currentIndex), style: defaultStyle),
      );
    }

    return TextSpan(children: spans);
  }
}
