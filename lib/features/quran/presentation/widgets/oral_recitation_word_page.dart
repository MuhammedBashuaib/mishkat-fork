import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/mushaf_layout_models.dart';
import '../../data/models/oral_recitation_models.dart';
import '../../data/models/printed_mushaf_models.dart';
import '../../data/models/quran_models.dart';
import '../cubit/quran_oral_recitation_state.dart';
import '../services/quran_recitation_text.dart';

/// Printed glyphs are shaped once per page size; live feedback changes paint.
/// Hidden words keep their real width and are excluded from accessibility text.
class OralRecitationWordPage extends StatefulWidget {
  const OralRecitationWordPage({
    super.key,
    required this.geometry,
    required this.quran,
    required this.printedPage,
    required this.state,
    required this.isCurrent,
    this.scrollEnabled = true,
  });

  final MushafPageGeometry geometry;
  final QuranData quran;
  final PrintedMushafPage printedPage;
  final QuranOralRecitationState state;
  final bool isCurrent;
  final bool scrollEnabled;

  @override
  State<OralRecitationWordPage> createState() => _OralRecitationWordPageState();
}

class _OralRecitationWordPageState extends State<OralRecitationWordPage> {
  final _scroll = ScrollController();
  _PageLayout? _layout;
  Object? _layoutSignature;
  QuranOralRecitationState? _appearanceState;
  List<OralMushafPaintedWord> _paintedWords = const [];
  bool _followPending = true;
  double? _viewportHeight;

  @override
  void didUpdateWidget(covariant OralRecitationWordPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(
          oldWidget.state.visibleWordIndices,
          widget.state.visibleWordIndices,
        ) ||
        oldWidget.state.currentGlobalAyah != widget.state.currentGlobalAyah ||
        (!oldWidget.isCurrent && widget.isCurrent)) {
      _followPending = true;
    }
  }

  void _followWord() {
    if (!_followPending || !widget.isCurrent || !widget.scrollEnabled) return;
    _followPending = false;
    final visibleWords = _paintedWords
        .where(
          (word) =>
              word.targetIndex != null &&
              widget.state.visibleWordIndices.contains(word.targetIndex),
        )
        .toList();
    final word = visibleWords.isEmpty ? null : visibleWords.last;
    if (word == null || word.boxes.isEmpty) return;
    final top = word.boxes.map((box) => box.top).reduce(math.min);
    final bottom = word.boxes.map((box) => box.bottom).reduce(math.max);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final offset = _scroll.offset;
      final height = _scroll.position.viewportDimension;
      // The controls can leave a short landscape viewport. Keep the entire
      // word visible whenever it fits, reducing the margin before clipping it.
      final margin = math.min(
        8.0,
        math.max(0.0, (height - (bottom - top)) / 2),
      );
      if (top >= offset + margin && bottom <= offset + height - margin) return;
      final minimum = bottom + margin - height;
      final maximum = top - margin;
      final preferred = top - height * .35;
      final next =
          (minimum <= maximum ? preferred.clamp(minimum, maximum) : top).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          );
      _scroll.animateTo(
        next,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _layout?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = dark ? const Color(0xFF14211B) : const Color(0xFFFAF7EF);
    final ink = dark ? const Color(0xFFECE5D8) : const Color(0xFF29261F);
    final error = dark ? const Color(0xFFFF9292) : const Color(0xFFB3261E);
    final ornament = dark ? const Color(0xFF91866C) : const Color(0xFF9B8A66);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 460.0);
        if (_viewportHeight != constraints.maxHeight) {
          _viewportHeight = constraints.maxHeight;
          _followPending = true;
        }
        final signature = (
          widget.geometry,
          widget.printedPage,
          widget.quran,
          widget.state.targetWords,
          width,
          dark,
          context.mishkat.primary,
        );
        if (signature != _layoutSignature) {
          final lines = _pageLines(
            widget.geometry,
            widget.printedPage,
            widget.quran,
            widget.state,
          );
          // Printed line breaks and word widths are independent of visibility
          // and available height. Only the viewport moves during recitation.
          final measured = _PageLayout.measure(
            lines,
            page: widget.geometry.page,
            width: width,
            canonicalText: widget.geometry.ayahs
                .map(
                  (ayah) =>
                      widget.quran.chapter(ayah.surah).ayahs[ayah.ayah - 1],
                )
                .join(' '),
            ink: ink,
            ornament: ornament,
          );
          _layout?.dispose();
          _layout = measured;
          _layoutSignature = signature;
          _appearanceState = null;
        }
        final layout = _layout!;
        // Recognition emits new sets even when their contents are unchanged.
        // Keep shaping and geometry independent of those live hypotheses.
        if (!_sameAppearance(_appearanceState, widget.state)) {
          _paintedWords = layout.displayWords(widget.state);
          _appearanceState = widget.state;
        }
        _followWord();
        // If every printed line fits, bring the bottom paper edge into view
        // without moving or resizing any word. Short viewports still scroll.
        final paperHeight = constraints.maxHeight >= layout.minimumHeight
            ? math.min(layout.height, constraints.maxHeight)
            : layout.height;
        final height = math.max(paperHeight, constraints.maxHeight);
        final currentAyah = widget.geometry.ayahs
            .where((ayah) => ayah.globalAyah == widget.state.currentGlobalAyah)
            .firstOrNull;
        final location =
            'صفحة ${_arabic(widget.geometry.page)} من المصحف'
            '${currentAyah == null ? '' : '، موضع التسميع الآية ${_arabic(currentAyah.ayah)}'}';
        final visibleText = _paintedWords
            .where((token) => token.visible)
            .map(
              (token) =>
                  token.mistake ? '${token.text}، موضع مراجعة' : token.text,
            )
            .join(' ');
        return Semantics(
          key: const Key('oral-word-page-semantics'),
          label: visibleText.isEmpty ? location : '$location. $visibleText',
          child: ExcludeSemantics(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  controller: _scroll,
                  physics: widget.scrollEnabled
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  child: CustomPaint(
                    key: const Key('oral-word-page-paint'),
                    size: Size(width, height),
                    painter: OralRecitationWordsPainter._(
                      layout,
                      words: _paintedWords,
                      currentGlobalAyah: widget.state.currentGlobalAyah,
                      currentColor: context.mishkat.primary,
                      hiddenColor: ink.withValues(alpha: dark ? .13 : .1),
                      errorColor: error,
                      paperColor: paper,
                      ornamentColor: ornament,
                      paperHeight: paperHeight,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

bool _sameAppearance(
  QuranOralRecitationState? previous,
  QuranOralRecitationState current,
) =>
    previous != null &&
    previous.mode == current.mode &&
    setEquals(previous.visibleWordIndices, current.visibleWordIndices) &&
    setEquals(previous.mistakeWordIndices, current.mistakeWordIndices) &&
    setEquals(
      previous.unresolvedMistakeWordIndices,
      current.unresolvedMistakeWordIndices,
    ) &&
    setEquals(previous.hintedWordIndices, current.hintedWordIndices) &&
    setEquals(previous.revealedGlobals, current.revealedGlobals);

class _PageWord {
  const _PageWord({
    required this.source,
    required this.canonicalText,
    required this.targetIndex,
  });
  final PrintedMushafWord source;
  final String canonicalText;
  final int? targetIndex;

  bool isVisible(QuranOralRecitationState state) =>
      source.isMarker ||
      (targetIndex != null &&
          (state.mode == OralRecitationMode.reading ||
              state.revealedGlobals.contains(source.globalAyah) ||
              (state.mode == OralRecitationMode.firstWord &&
                  source.ordinal == 0) ||
              state.visibleWordIndices.contains(targetIndex) ||
              state.hintedWordIndices.contains(targetIndex)));
}

class _PageLine {
  const _PageLine(this.source, this.title, this.words);
  final PrintedMushafLine source;
  final String? title;
  final List<_PageWord> words;
}

List<_PageLine> _pageLines(
  MushafPageGeometry geometry,
  PrintedMushafPage page,
  QuranData quran,
  QuranOralRecitationState state,
) {
  final canonical = <int, List<String>>{
    for (final ayah in geometry.ayahs)
      ayah.globalAyah: quran
          .chapter(ayah.surah)
          .ayahs[ayah.ayah - 1]
          .split(RegExp(r'\s+'))
          .where(QuranRecitationText.hasArabicLetter)
          .toList(),
  };
  final targets = <int, List<int>>{};
  for (var index = 0; index < state.targetWords.length; index++) {
    (targets[state.targetWords[index].globalAyah] ??= []).add(index);
  }
  return [
    for (final line in page.lines)
      _PageLine(
        line,
        line.kind == PrintedMushafLineKind.surahTitle
            ? 'سورة ${quran.chapter(line.surah!).name}'
            : null,
        [
          for (final word in line.words)
            (() {
              final indices = targets[word.globalAyah] ?? const <int>[];
              final target = !word.isMarker && word.ordinal < indices.length
                  ? indices[word.ordinal]
                  : null;
              return _PageWord(
                source: word,
                canonicalText: word.isMarker
                    ? ''
                    : canonical[word.globalAyah]![word.ordinal],
                targetIndex: target,
              );
            })(),
        ],
      ),
  ];
}

String _arabic(int value) => value.toString().replaceAllMapped(
  RegExp(r'[0-9]'),
  (match) => String.fromCharCode(0x660 + int.parse(match[0]!)),
);

@immutable
class OralMushafPaintedWord {
  const OralMushafPaintedWord({
    required this.text,
    required this.targetIndex,
    required this.globalAyah,
    required this.visible,
    required this.mistake,
    required this.unresolved,
    required this.boxes,
    required this.lineNumbers,
    required this.baselines,
  });
  final String text;
  final int? targetIndex;
  final int globalAyah;
  final bool visible;
  final bool mistake;
  final bool unresolved;
  final List<Rect> boxes;
  final List<int> lineNumbers;
  final List<double> baselines;
}

class _PaintedRun {
  _PaintedRun(this.painter, this.offset, {this.word, this.wordIndex});
  final TextPainter painter;
  final Offset offset;
  final _PageWord? word;
  final int? wordIndex;
  final _colorVariants = <Color, TextPainter>{};

  void paint(Canvas canvas, {Color? color}) {
    if (color == null) {
      painter.paint(canvas, offset);
      return;
    }
    // A mistake or current ayah marker needs a paint variant, never another
    // page fit or new word positions. Cache it if that word is revisited.
    final variant = _colorVariants.putIfAbsent(color, () {
      final span = painter.text! as TextSpan;
      return TextPainter(
        text: TextSpan(
          text: span.text,
          style: span.style!.copyWith(color: color),
        ),
        textDirection: TextDirection.rtl,
        textScaler: TextScaler.noScaling,
      )..layout();
    });
    variant.paint(canvas, offset);
  }

  void dispose() {
    painter.dispose();
    for (final variant in _colorVariants.values) {
      variant.dispose();
    }
  }
}

class _WordGeometry {
  _WordGeometry(this.word, this.index);
  final _PageWord word;
  final int index;
  final boxes = <Rect>[];
  final lines = <int>[];
  final baselines = <double>[];
}

class _PageLayout {
  const _PageLayout({
    required this.runs,
    required this.words,
    required this.wordSources,
    required this.height,
    required this.minimumHeight,
    required this.fontSize,
    required this.lineCount,
    required this.canonicalText,
    required this.titleRules,
  });
  final List<_PaintedRun> runs;
  final List<OralMushafPaintedWord> words;
  final List<_PageWord> wordSources;
  final double height;
  final double minimumHeight;
  final double fontSize;
  final int lineCount;
  final String canonicalText;
  final List<(Offset, Offset)> titleRules;

  void dispose() {
    for (final run in runs) {
      run.dispose();
    }
  }

  List<OralMushafPaintedWord> displayWords(QuranOralRecitationState state) => [
    for (var index = 0; index < words.length; index++)
      (() {
        final geometry = words[index];
        final source = wordSources[index];
        final visible = source.isVisible(state);
        return OralMushafPaintedWord(
          text: geometry.text,
          targetIndex: geometry.targetIndex,
          globalAyah: geometry.globalAyah,
          visible: visible,
          mistake:
              visible && state.mistakeWordIndices.contains(source.targetIndex),
          unresolved:
              visible &&
              state.unresolvedMistakeWordIndices.contains(source.targetIndex),
          boxes: geometry.boxes,
          lineNumbers: geometry.lineNumbers,
          baselines: geometry.baselines,
        );
      })(),
  ];

  static TextPainter _text(String text, double fontSize, Color color) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'QpcHafs',
            fontSize: fontSize,
            color: color,
          ),
        ),
        textDirection: TextDirection.rtl,
        textScaler: TextScaler.noScaling,
      )..layout();

  static _PageLayout measure(
    List<_PageLine> lines, {
    required int page,
    required double width,
    required String canonicalText,
    required Color ink,
    required Color ornament,
  }) {
    final scale = width / 390;
    final horizontal = 18 * scale;
    final contentWidth = width - 2 * horizontal;
    final opening = page <= 2;
    final nominal = (opening ? 30.0 : 25.0) * scale;
    var fit = 1.0;
    // Fit one font size for the entire page, not a changing size per line.
    // Each word is shaped independently; no letter connects across a space.
    for (final line in lines) {
      var natural = 0.0;
      for (final word in line.words) {
        final painter = _text(word.source.text, nominal, ink);
        natural += painter.width;
        painter.dispose();
      }
      natural += math.max(0, line.words.length - 1) * nominal * .17;
      if (natural > contentWidth) fit = math.min(fit, contentWidth / natural);
    }
    final fontSize = nominal * fit;
    final height = width * (550 / 345);
    final rowHeight = (opening ? 43.0 : 34.0) * scale;
    final top = opening
        ? (height - rowHeight * lines.length) / 2 - 20 * scale
        : 31 * scale;
    final runs = <_PaintedRun>[];
    final geometry = <(int, int), _WordGeometry>{};
    final rules = <(Offset, Offset)>[];

    for (final line in lines) {
      final y = top + (line.source.number - 1) * rowHeight;
      final baseline = y + rowHeight * .78;
      if (line.source.kind != PrintedMushafLineKind.text) {
        final isTitle = line.source.kind == PrintedMushafLineKind.surahTitle;
        final painter = _text(
          isTitle ? line.title! : 'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ',
          (isTitle ? 20 : 22) * scale,
          isTitle ? ornament : ink,
        );
        final origin = Offset(
          (width - painter.width) / 2,
          baseline -
              painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        );
        runs.add(_PaintedRun(painter, origin));
        if (isTitle) {
          final ruleY = y + rowHeight * .52;
          final gap = 12 * scale;
          if (origin.dx > horizontal + gap) {
            rules.add((
              Offset(horizontal, ruleY),
              Offset(origin.dx - gap, ruleY),
            ));
            rules.add((
              Offset(origin.dx + painter.width + gap, ruleY),
              Offset(width - horizontal, ruleY),
            ));
          }
        }
        continue;
      }

      final painters = [
        for (final word in line.words)
          _text(
            word.source.text,
            fontSize,
            word.source.isMarker ? ornament : ink,
          ),
      ];
      final natural = painters.fold<double>(
        0,
        (total, painter) => total + painter.width,
      );
      final gap = line.source.centered
          ? fontSize * .17
          : (contentWidth - natural) / math.max(1, painters.length - 1);
      final lineWidth = natural + gap * math.max(0, painters.length - 1);
      var right = line.source.centered
          ? (width + lineWidth) / 2
          : width - horizontal;
      for (var index = 0; index < painters.length; index++) {
        final painter = painters[index];
        final word = line.words[index];
        final left = right - painter.width;
        final origin = Offset(
          left,
          baseline -
              painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        );
        int? wordIndex;
        if (!word.source.isMarker) {
          final key = (word.source.globalAyah, word.source.ordinal);
          final item = geometry.putIfAbsent(
            key,
            () => _WordGeometry(word, geometry.length),
          );
          wordIndex = item.index;
          // Tight selection boxes include the QPC diacritics and are also used
          // by automatic scrolling. Several printed parts may be one word.
          final boxes = painter.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: word.source.text.length),
          );
          item.boxes.addAll(boxes.map((box) => box.toRect().shift(origin)));
          item.baselines.addAll(boxes.map((_) => baseline));
          item.lines.add(line.source.number);
        }
        runs.add(
          _PaintedRun(painter, origin, word: word, wordIndex: wordIndex),
        );
        right = left - gap;
      }
    }
    return _PageLayout(
      runs: runs,
      words: [
        for (final item in geometry.values)
          OralMushafPaintedWord(
            text: item.word.canonicalText,
            targetIndex: item.word.targetIndex,
            globalAyah: item.word.source.globalAyah,
            visible: false,
            mistake: false,
            unresolved: false,
            boxes: List.unmodifiable(item.boxes),
            lineNumbers: List.unmodifiable(item.lines),
            baselines: List.unmodifiable(item.baselines),
          ),
      ],
      wordSources: [for (final item in geometry.values) item.word],
      height: height,
      minimumHeight:
          geometry.values
              .expand((item) => item.boxes)
              .fold<double>(0, (bottom, box) => math.max(bottom, box.bottom)) +
          20 * scale,
      fontSize: fontSize,
      lineCount: lines.length,
      canonicalText: canonicalText,
      titleRules: rules,
    );
  }
}

class OralRecitationWordsPainter extends CustomPainter {
  const OralRecitationWordsPainter._(
    this._layout, {
    required this.words,
    required this.currentGlobalAyah,
    required this.currentColor,
    required this.hiddenColor,
    required this.errorColor,
    required this.paperColor,
    required this.ornamentColor,
    required this.paperHeight,
  });
  final _PageLayout _layout;
  final int currentGlobalAyah;
  final Color currentColor;
  final Color hiddenColor;
  final Color errorColor;
  final Color paperColor;
  final Color ornamentColor;
  final double paperHeight;

  @visibleForTesting
  final List<OralMushafPaintedWord> words;
  @visibleForTesting
  Object get geometryIdentity => _layout;
  @visibleForTesting
  double get fontSize => _layout.fontSize;
  @visibleForTesting
  int get lineCount => _layout.lineCount;
  @visibleForTesting
  String get canonicalText => _layout.canonicalText;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 390;
    final page = Rect.fromLTWH(0, 0, size.width, paperHeight);
    canvas.drawRect(page, Paint()..color = paperColor);
    final bounds = page.deflate(6 * scale);
    final ornament = Paint()
      ..color = ornamentColor.withValues(alpha: .4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .65 * scale;
    canvas.drawRect(bounds, ornament);
    final corner = Paint()..color = ornamentColor.withValues(alpha: .58);
    for (final point in [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ]) {
      final radius = 2.6 * scale;
      canvas.drawPath(
        Path()
          ..moveTo(point.dx, point.dy - radius)
          ..lineTo(point.dx + radius, point.dy)
          ..lineTo(point.dx, point.dy + radius)
          ..lineTo(point.dx - radius, point.dy)
          ..close(),
        corner,
      );
    }
    for (final (start, end) in _layout.titleRules) {
      canvas.drawLine(start, end, ornament);
    }
    for (final run in _layout.runs) {
      final wordIndex = run.wordIndex;
      if (wordIndex != null) {
        final word = words[wordIndex];
        if (word.visible) {
          run.paint(canvas, color: word.mistake ? errorColor : null);
        }
      } else {
        run.paint(
          canvas,
          color: run.word?.source.globalAyah == currentGlobalAyah
              ? currentColor
              : null,
        );
      }
    }
    final mask = Paint()..color = hiddenColor;
    final errorLine = Paint()..color = errorColor;
    for (final word in words) {
      if (word.visible && !word.unresolved) continue;
      for (var index = 0; index < word.boxes.length; index++) {
        final box = word.boxes[index];
        if (box.width <= 1) continue;
        final inset = math.min(1.5 * scale, box.width / 8);
        final rect = Rect.fromLTWH(
          box.left + inset,
          word.unresolved
              ? box.bottom - _layout.fontSize * .27
              : word.baselines[index] - _layout.fontSize * .16,
          box.width - inset * 2,
          (word.unresolved ? 1.1 : 1.6) * scale,
        );
        if (word.unresolved) {
          for (var x = rect.left; x < rect.right; x += 5 * scale) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(
                  x,
                  rect.top,
                  math.min(2.6 * scale, rect.right - x),
                  rect.height,
                ),
                Radius.circular(scale),
              ),
              errorLine,
            );
          }
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(scale)),
            mask,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(OralRecitationWordsPainter oldDelegate) =>
      oldDelegate._layout != _layout ||
      !identical(oldDelegate.words, words) ||
      oldDelegate.currentGlobalAyah != currentGlobalAyah ||
      oldDelegate.currentColor != currentColor ||
      oldDelegate.hiddenColor != hiddenColor ||
      oldDelegate.errorColor != errorColor ||
      oldDelegate.paperColor != paperColor ||
      oldDelegate.ornamentColor != ornamentColor ||
      oldDelegate.paperHeight != paperHeight;
}
