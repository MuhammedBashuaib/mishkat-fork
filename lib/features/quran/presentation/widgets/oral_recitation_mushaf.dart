import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/mushaf_layout_models.dart';
import '../../data/models/printed_mushaf_models.dart';
import '../../data/models/quran_models.dart';
import '../../data/repositories/mushaf_layout_repository.dart';
import '../../data/repositories/printed_mushaf_repository.dart';
import '../../data/repositories/quran_repository.dart';
import '../cubit/quran_oral_recitation_state.dart';
import 'oral_recitation_word_page.dart';

/// A local Mushaf with the verified printed page and line boundaries.
/// Words keep their positions when concealed, revealed or marked for review.
class OralRecitationMushaf extends StatefulWidget {
  const OralRecitationMushaf({
    super.key,
    required this.state,
    this.layoutRepository,
    this.quranRepository,
  });

  final QuranOralRecitationState state;
  final MushafLayoutRepository? layoutRepository;
  final QuranRepository? quranRepository;

  static final _canonicalRepository = QuranRepository();
  static Future<QuranData>? _canonicalLoad;
  static QuranData? _canonicalData;

  /// Shares the canonical page text across recitation routes and sessions.
  /// Callers may warm it while preparing a session, before mounting the page.
  /// This cache owns decoded data, independently of the asset string cache.
  static Future<QuranData> preloadCanonicalText() {
    final data = _canonicalData;
    // Return a fresh completion in the caller's zone, including widget tests'
    // fake clock. Only an in-flight asset read is shared as a Future.
    if (data != null) return Future.value(data);
    return _canonicalLoad ??= _loadCanonicalText();
  }

  static Future<QuranData> _loadCanonicalText() async {
    try {
      final loaded = await Future.wait<Object>([
        _canonicalRepository.load(),
        PrintedMushafRepository.instance.load(),
      ]);
      final data = loaded[0] as QuranData;
      _canonicalData = data;
      return data;
    } catch (_) {
      // A transient asset failure must not poison every later page or retry.
      _canonicalLoad = null;
      rethrow;
    }
  }

  @override
  State<OralRecitationMushaf> createState() => _OralRecitationMushafState();
}

class _OralRecitationMushafState extends State<OralRecitationMushaf> {
  late MushafLayoutRepository _repository;
  late QuranRepository _quranRepository;
  QuranData? _quran;
  PageController? _controller;
  List<int> _pages = const [];
  Set<int> _targets = const {};
  int _index = 0;
  int _loadGeneration = 0;
  int _navigationGeneration = 0;
  bool _loading = true;
  bool _failed = false;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.layoutRepository ?? MushafLayoutRepository.instance;
    _quranRepository =
        widget.quranRepository ?? OralRecitationMushaf._canonicalRepository;
    _load();
  }

  @override
  void didUpdateWidget(covariant OralRecitationMushaf oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repository =
        widget.layoutRepository ?? MushafLayoutRepository.instance;
    if (!identical(repository, _repository) ||
        !identical(oldWidget.quranRepository, widget.quranRepository)) {
      _repository = repository;
      _quranRepository =
          widget.quranRepository ?? OralRecitationMushaf._canonicalRepository;
      _load();
      return;
    }
    if (_loading || _failed) return;
    final newSession = oldWidget.state.sessionId != widget.state.sessionId;
    final newTargets = !identical(
      oldWidget.state.targetWords,
      widget.state.targetWords,
    );
    final newAyah =
        oldWidget.state.currentGlobalAyah != widget.state.currentGlobalAyah;
    if (newSession || newTargets) {
      final changedPages = _updatePages();
      if (newSession || changedPages) {
        _zoomed = false;
        _followCurrent();
      }
    } else if (newAyah) {
      _followCurrent();
    }
    if (!newSession) {
      // A requested hint is an explicit navigation intent, even when the
      // confirmed reading position still belongs to the preceding page.
      final revealed = widget.state.revealedGlobals.difference(
        oldWidget.state.revealedGlobals,
      );
      final hinted = widget.state.hintedWordIndices.difference(
        oldWidget.state.hintedWordIndices,
      );
      final requestedGlobals = <int>{
        ...revealed,
        for (final index in hinted)
          if (index >= 0 && index < widget.state.targetWords.length)
            widget.state.targetWords[index].globalAyah,
      };
      for (final global in requestedGlobals) {
        if (!_targets.contains(global)) continue;
        final page = _repository.pageForAyah(global);
        final index = _pages.indexOf(page ?? -1);
        if (index >= 0) {
          _browse(index);
          break;
        }
      }
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    _navigationGeneration++;
    _loading = true;
    _failed = false;
    try {
      final loaded = await Future.wait<Object>([
        _repository.load(),
        widget.quranRepository == null
            ? OralRecitationMushaf.preloadCanonicalText()
            : _quranRepository.load(),
        PrintedMushafRepository.instance.load(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      _quran = loaded[1] as QuranData;
      setState(() {
        _loading = false;
        _updatePages();
        _index = _activeIndex;
        _controller ??= PageController(initialPage: _index);
      });
      _followCurrent();
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  bool _updatePages() {
    _targets = widget.state.targetWords.map((word) => word.globalAyah).toSet();
    final pages = <int>{};
    for (final global in _targets) {
      final page = _repository.pageForAyah(global);
      if (page != null) pages.add(page);
    }
    final sorted = pages.toList()..sort();
    final changed = !listEquals(sorted, _pages);
    _pages = sorted;
    if (_pages.isNotEmpty) _index = _index.clamp(0, _pages.length - 1);
    return changed;
  }

  int get _activeIndex {
    final page = _repository.pageForAyah(widget.state.currentGlobalAyah);
    final index = page == null ? -1 : _pages.indexOf(page);
    return index < 0 ? 0 : index;
  }

  void _followCurrent() {
    if (_pages.isEmpty) return;
    final index = _activeIndex;
    final generation = ++_navigationGeneration;
    if (_index != index) _zoomed = false;
    _index = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _navigationGeneration) return;
      if (_controller?.hasClients ?? false) _controller!.jumpToPage(index);
    });
  }

  void _browse(int index) {
    if (index < 0 || index >= _pages.length || index == _index) return;
    _navigationGeneration++;
    setState(() {
      _index = index;
      _zoomed = false;
    });
    _controller?.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _loadGeneration++;
    _navigationGeneration++;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final background = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF111C18)
        : const Color(0xFFF6F3EB);
    if (_loading) {
      // Never mount the text until page boundaries and canonical text are ready.
      return ColoredBox(
        color: background,
        child: const Center(
          child: CircularProgressIndicator(key: Key('oral-mushaf-loading')),
        ),
      );
    }
    if (_failed || _pages.isEmpty) {
      return ColoredBox(
        color: background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_outlined),
                const SizedBox(height: 8),
                const Text(
                  'تعذّر تجهيز صفحة المصحف',
                  textAlign: TextAlign.center,
                ),
                TextButton.icon(
                  key: const Key('oral-mushaf-retry'),
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _failed = false;
                    });
                    _load();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final activeIndex = _activeIndex;
    return ColoredBox(
      color: background,
      child: Column(
        children: [
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: PageView.builder(
                key: ValueKey(('oral-mushaf-pages', widget.state.sessionId)),
                controller: _controller,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                itemCount: _pages.length,
                onPageChanged: (index) {
                  if (_index == index) return;
                  setState(() {
                    _index = index;
                    _zoomed = false;
                  });
                },
                itemBuilder: (context, index) {
                  final geometry = _repository.getPageGeometry(_pages[index])!;
                  return _OralMushafSheet(
                    key: ValueKey((widget.state.sessionId, geometry.page)),
                    geometry: geometry,
                    printedPage: PrintedMushafRepository.instance.page(
                      geometry.page,
                    )!,
                    state: widget.state,
                    quran: _quran!,
                    isCurrent: index == _index,
                    onZoomChanged: (zoomed) {
                      if (index != _index || zoomed == _zoomed) return;
                      setState(() => _zoomed = zoomed);
                    },
                  );
                },
              ),
            ),
          ),
          Directionality(
            textDirection: TextDirection.rtl,
            child: SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 108),
                    child: Text(
                      'صفحة ${_arabic(_pages[_index])} من ٦٠٤',
                      key: const Key('oral-mushaf-page-caption'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 12),
                      IconButton(
                        key: const Key('oral-mushaf-previous'),
                        tooltip: 'الصفحة السابقة في المقطع',
                        onPressed: _index > 0
                            ? () => _browse(_index - 1)
                            : null,
                        icon: const Icon(
                          Icons.chevron_right_rounded,
                          textDirection: TextDirection.ltr,
                        ),
                        iconSize: 22,
                        color: colors.textSecondary,
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                      ),
                      const Spacer(),
                      if (_index != activeIndex)
                        IconButton(
                          key: const Key('oral-mushaf-return'),
                          tooltip: 'العودة إلى موضع التسميع',
                          onPressed: () => _browse(activeIndex),
                          icon: const Icon(Icons.my_location_rounded),
                          color: colors.primary,
                          iconSize: 19,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                        ),
                      IconButton(
                        key: const Key('oral-mushaf-next'),
                        tooltip: 'الصفحة التالية في المقطع',
                        onPressed: _index < _pages.length - 1
                            ? () => _browse(_index + 1)
                            : null,
                        icon: const Icon(
                          Icons.chevron_left_rounded,
                          textDirection: TextDirection.ltr,
                        ),
                        iconSize: 22,
                        color: colors.textSecondary,
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _arabic(int number) => number
    .toString()
    .split('')
    .map((digit) => String.fromCharCode(0x0660 + int.parse(digit)))
    .join();

class _OralMushafSheet extends StatefulWidget {
  const _OralMushafSheet({
    super.key,
    required this.geometry,
    required this.printedPage,
    required this.state,
    required this.quran,
    required this.isCurrent,
    required this.onZoomChanged,
  });

  final MushafPageGeometry geometry;
  final PrintedMushafPage printedPage;
  final QuranOralRecitationState state;
  final QuranData quran;
  final bool isCurrent;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_OralMushafSheet> createState() => _OralMushafSheetState();
}

class _OralMushafSheetState extends State<_OralMushafSheet> {
  final _transformation = TransformationController();
  bool _zoomed = false;

  @override
  void didUpdateWidget(covariant _OralMushafSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCurrent && !widget.isCurrent) _resetZoom(notify: false);
  }

  void _resetZoom({bool notify = true}) {
    _transformation.value = Matrix4.identity();
    _zoomed = false;
    if (notify) widget.onZoomChanged(false);
  }

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: ClipRect(
        child: InteractiveViewer(
          transformationController: _transformation,
          minScale: 1,
          maxScale: 2.5,
          panEnabled: _zoomed,
          onInteractionUpdate: (_) {
            final zoomed = _transformation.value.getMaxScaleOnAxis() > 1.05;
            if (zoomed != _zoomed) {
              setState(() => _zoomed = zoomed);
              widget.onZoomChanged(zoomed);
            }
          },
          onInteractionEnd: (_) {
            if (!_zoomed) _resetZoom();
          },
          // Height only changes the viewport. Printed line positions remain
          // stable when a correction or the controls take more room.
          child: GestureDetector(
            onDoubleTap: () => setState(_resetZoom),
            child: RepaintBoundary(
              child: OralRecitationWordPage(
                key: Key('oral-mushaf-page-${widget.geometry.page}'),
                geometry: widget.geometry,
                printedPage: widget.printedPage,
                quran: widget.quran,
                state: widget.state,
                isCurrent: widget.isCurrent,
                scrollEnabled: !_zoomed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
