import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../khatma/data/models/khatma_plan.dart';
import '../../../khatma/presentation/cubit/khatma_cubit.dart';
import '../../../khatma/presentation/cubit/khatma_state.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/cubit/settings_state.dart';
import '../../data/models/mushaf_layout_models.dart';
import '../../data/models/quran_models.dart';
import '../../data/repositories/mushaf_layout_repository.dart';
import '../cubit/mushaf_interaction_cubit.dart';
import '../cubit/mushaf_interaction_state.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_memorization_cubit.dart';
import '../cubit/quran_state.dart';
import '../cubit/quran_visual_recall_cubit.dart';
import '../cubit/quran_visual_recall_state.dart';
import '../widgets/ayah_action_sheet.dart';
import '../widgets/mushaf_ayah_overlay.dart';
import '../widgets/mushaf_interaction_layer.dart';
import '../widgets/mushaf_visual_mask_overlay.dart';
import '../widgets/mushaf_visual_recall_interaction_layer.dart';
import '../widgets/quran_mini_player.dart';
import '../widgets/tafsir_knowledge_sheet.dart';
import '../widgets/visual_recall_bottom_bar.dart';

QuranVisualRecallCubit? _tryGetVisualRecallCubit(BuildContext context) {
  try {
    return BlocProvider.of<QuranVisualRecallCubit>(context, listen: false);
  } catch (_) {
    return null;
  }
}

class QuranReaderPage extends StatefulWidget {
  const QuranReaderPage({
    super.key,
    this.initialGlobalAyah,
    this.visualRecallInitialQueue,
    this.visualRecallPlanId,
    this.startRangeSelection,
    this.khatmaPlanId,
    this.khatmaPlanName,
    this.khatmaStartPage,
    this.khatmaTargetPage,
  });

  final int? initialGlobalAyah;
  final List<int>? visualRecallInitialQueue;
  final String? visualRecallPlanId;
  final bool? startRangeSelection;
  final String? khatmaPlanId;
  final String? khatmaPlanName;
  final int? khatmaStartPage;
  final int? khatmaTargetPage;

  @override
  State<QuranReaderPage> createState() => _QuranReaderPageState();
}

class _QuranReaderPageState extends State<QuranReaderPage> {
  late final PageController _controller;
  late final QuranCubit _quranCubit;
  bool _focus = false;
  bool _isPageZoomed = false;
  int? _lastKhatmaPage;

  @override
  void initState() {
    super.initState();
    _quranCubit = context.read<QuranCubit>();
    int initialPage = _quranCubit.state.currentPage - 1;
    final targetGlobal =
        widget.initialGlobalAyah ??
        (widget.visualRecallInitialQueue != null &&
                widget.visualRecallInitialQueue!.isNotEmpty
            ? widget.visualRecallInitialQueue!.first
            : null);
    if (targetGlobal != null) {
      final layoutRepo = MushafLayoutRepository.instance;
      final targetPage = layoutRepo.isLoaded
          ? layoutRepo.pageForAyah(targetGlobal)
          : null;
      if (targetPage != null) {
        initialPage = targetPage - 1;
      }
    }
    _controller = PageController(initialPage: initialPage);
    if (widget.khatmaPlanId != null) {
      _lastKhatmaPage = initialPage + 1;
    }
  }

  QuranVisualRecallCubit? _scopedRecallCubit;
  MushafInteractionCubit? _scopedInteractionCubit;

  @override
  void dispose() {
    unawaited(_quranCubit.stopAudioIfOwnedBy(QuranPlaybackOrigin.mushaf));
    _scopedRecallCubit?.close();
    _scopedInteractionCubit?.close();
    _controller.dispose();
    super.dispose();
  }

  void _handleZoomChanged(bool isZoomed) {
    if (_isPageZoomed != isZoomed) {
      setState(() => _isPageZoomed = isZoomed);
    }
  }

  void _setReaderScale(BuildContext context, double scale) {
    final fontSize = (scale.clamp(1.0, 1.875) * 32).clamp(32, 60).toDouble();
    context.read<QuranCubit>().setFontSize(fontSize);
    context.read<SettingsCubit>().setQuranFont(fontSize);
  }

  @override
  Widget build(BuildContext context) {
    final ancestorRecallCubit = _tryGetVisualRecallCubit(context);
    QuranMemorizationCubit? memCubit;
    try {
      memCubit = context.read<QuranMemorizationCubit>();
    } catch (_) {}

    _scopedInteractionCubit ??= () {
      final cubit = MushafInteractionCubit()..load();
      if (widget.initialGlobalAyah != null &&
          (widget.visualRecallInitialQueue == null ||
              widget.visualRecallInitialQueue!.isEmpty) &&
          widget.startRangeSelection != true) {
        cubit.selectAyahByGlobal(widget.initialGlobalAyah!);
      }
      return cubit;
    }();

    if (ancestorRecallCubit == null && memCubit != null) {
      _scopedRecallCubit ??= () {
        final quranCubit = context.read<QuranCubit>();
        final cubit = QuranVisualRecallCubit(
          memorizationCubit: memCubit!,
          storage: memCubit.repository.storage,
          audioService: quranCubit.audioService,
          reciter: quranCubit.reciter,
        );
        if (widget.visualRecallInitialQueue != null &&
            widget.visualRecallInitialQueue!.isNotEmpty) {
          cubit.startJourney(
            widget.visualRecallInitialQueue!,
            planId: widget.visualRecallPlanId,
          );
        } else if (widget.startRangeSelection == true &&
            widget.initialGlobalAyah != null) {
          cubit.enterRangeSelection(widget.initialGlobalAyah!);
        }
        return cubit;
      }();
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider<MushafInteractionCubit>.value(
          value: _scopedInteractionCubit!,
        ),
        if (ancestorRecallCubit == null && _scopedRecallCubit != null)
          BlocProvider<QuranVisualRecallCubit>.value(
            value: _scopedRecallCubit!,
          ),
      ],
      child: Builder(
        builder: (context) {
          final visualRecallCubit = _tryGetVisualRecallCubit(context);
          if (ancestorRecallCubit != null &&
              widget.visualRecallInitialQueue != null &&
              widget.visualRecallInitialQueue!.isNotEmpty &&
              !ancestorRecallCubit.state.hasActiveSession) {
            ancestorRecallCubit.startJourney(
              widget.visualRecallInitialQueue!,
              planId: widget.visualRecallPlanId,
            );
          }

          return MultiBlocListener(
            listeners: [
              BlocListener<MushafInteractionCubit, MushafInteractionState>(
                listenWhen: (previous, current) =>
                    !previous.isActionSheetOpen &&
                    current.isActionSheetOpen &&
                    current.selectedAyah != null,
                listener: (context, state) async {
                  final quranData = context.read<QuranCubit>().state.data;
                  if (quranData == null || state.selectedAyah == null) return;

                  final result = await AyahActionSheet.show(
                    context: context,
                    ayah: state.selectedAyah!,
                    quranData: quranData,
                    playbackOrigin: QuranPlaybackOrigin.mushaf,
                  );

                  if (result == 'tafsir' && context.mounted) {
                    await TafsirKnowledgeSheet.show(
                      context: context,
                      ayah: state.selectedAyah!,
                      quranData: quranData,
                    );
                  } else if (result == 'visual_recall_single' &&
                      context.mounted) {
                    final recall = _tryGetVisualRecallCubit(context);
                    if (recall != null) {
                      context.read<MushafInteractionCubit>().clearSelection();
                      await recall.startSingleAyah(
                        state.selectedAyah!.globalAyah,
                      );
                    }
                  } else if (result == 'visual_recall_range' &&
                      context.mounted) {
                    final recall = _tryGetVisualRecallCubit(context);
                    if (recall != null) {
                      context.read<MushafInteractionCubit>().clearSelection();
                      recall.enterRangeSelection(
                        state.selectedAyah!.globalAyah,
                      );
                    }
                  }

                  if (context.mounted) {
                    context.read<MushafInteractionCubit>().setActionSheetOpen(
                      false,
                    );
                  }
                },
              ),
              if (visualRecallCubit != null)
                BlocListener<QuranVisualRecallCubit, QuranVisualRecallState>(
                  bloc: visualRecallCubit,
                  listenWhen: (previous, current) =>
                      previous.currentGlobalAyah != current.currentGlobalAyah &&
                      current.currentGlobalAyah != null,
                  listener: (context, state) {
                    final nextAyah = state.currentGlobalAyah;
                    if (nextAyah == null) return;
                    final layoutRepo = MushafLayoutRepository.instance;
                    final targetPage = layoutRepo.isLoaded
                        ? layoutRepo.pageForAyah(nextAyah)
                        : null;
                    if (targetPage != null) {
                      final targetIndex = targetPage - 1;
                      if (_controller.hasClients &&
                          (_controller.page?.round() ?? targetIndex) !=
                              targetIndex) {
                        _controller.animateToPage(
                          targetIndex,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOutCubic,
                        );
                      }
                    }
                  },
                ),
              BlocListener<QuranCubit, QuranState>(
                listenWhen: (previous, current) =>
                    previous.audioGlobalAyah != current.audioGlobalAyah ||
                    previous.audioStatus != current.audioStatus,
                listener: (context, state) {
                  final activeAyah =
                      (state.audioStatus == QuranAudioStatus.playing ||
                          state.audioStatus == QuranAudioStatus.loading ||
                          state.audioStatus == QuranAudioStatus.paused)
                      ? state.audioGlobalAyah
                      : null;
                  context.read<MushafInteractionCubit>().setPlayingAyah(
                    activeAyah,
                  );
                },
              ),
            ],
            child: BlocConsumer<QuranCubit, QuranState>(
              listenWhen: (previous, current) =>
                  previous.currentPage != current.currentPage,
              listener: (context, state) {
                final target = state.currentPage - 1;
                if (_controller.hasClients &&
                    (_controller.page?.round() ?? target) != target) {
                  _controller.animateToPage(
                    target,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                  );
                }
              },
              buildWhen: (previous, current) =>
                  previous.currentPage != current.currentPage ||
                  previous.fontSize != current.fontSize ||
                  previous.bookmarks != current.bookmarks ||
                  previous.status != current.status ||
                  previous.data != current.data,
              builder: (context, state) {
                final data = state.data!;
                final point = data.page(state.currentPage).first;
                final chapter = data.chapter(point.surah);
                final colors = context.mishkat;
                final readerScale = (state.fontSize / 32).clamp(1.0, 1.875);
                return Scaffold(
                  backgroundColor: colors.surfaceMuted,
                  appBar: _focus
                      ? null
                      : AppBar(
                          toolbarHeight: 64,
                          centerTitle: true,
                          backgroundColor: colors.surface,
                          surfaceTintColor: Colors.transparent,
                          scrolledUnderElevation: 0,
                          leading: IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded),
                            tooltip: 'العودة إلى الفهرس',
                            onPressed: () => Navigator.pop(context),
                          ),
                          title: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'سورة ${chapter.name}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'صفحة ${state.currentPage} من 604 · الجزء ${_juzFor(data, point.global)}',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.textSecondary),
                              ),
                            ],
                          ),
                          actions: [
                            IconButton(
                              tooltip: state.isCurrentPageBookmarked
                                  ? 'حذف العلامة'
                                  : 'حفظ علامة',
                              onPressed: context
                                  .read<QuranCubit>()
                                  .toggleBookmark,
                              icon: Icon(
                                state.isCurrentPageBookmarked
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                              ),
                            ),
                            IconButton(
                              tooltip: 'ملء الشاشة',
                              onPressed: () => setState(() => _focus = true),
                              icon: const Icon(Icons.fullscreen_rounded),
                            ),
                          ],
                          bottom: PreferredSize(
                            preferredSize: const Size.fromHeight(58),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                border: Border(
                                  bottom: BorderSide(color: colors.border),
                                ),
                              ),
                              child: Center(
                                child: _ZoomLensControl(
                                  scale: readerScale,
                                  onDecrease: () => _setReaderScale(
                                    context,
                                    readerScale - .1,
                                  ),
                                  onReset: () => _setReaderScale(context, 1),
                                  onIncrease: () => _setReaderScale(
                                    context,
                                    readerScale + .1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                  body: Stack(
                    children: [
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: PageView.builder(
                          controller: _controller,
                          physics: _isPageZoomed
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                          itemCount: 604,
                          onPageChanged: (index) {
                            final page = index + 1;
                            _trackKhatmaPage(context, page);
                            final recall = _tryGetVisualRecallCubit(context);
                            final isRecallActive =
                                recall != null &&
                                (recall.state.hasActiveSession ||
                                    recall.state.isRangeSelecting);
                            if (!isRecallActive) {
                              context.read<QuranCubit>().openPage(page);
                            }
                            context
                                .read<MushafInteractionCubit>()
                                .onPageChanged(page);
                          },
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  MishkatRadius.lg,
                                ),
                                border: Border.all(color: colors.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .07),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  MishkatRadius.lg,
                                ),
                                child: _MushafPage(
                                  key: ValueKey('mushaf-page-${index + 1}'),
                                  page: index + 1,
                                  scale: readerScale,
                                  isCurrent: (index + 1) == state.currentPage,
                                  onZoomChanged: _handleZoomChanged,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_focus)
                        Positioned(
                          top: MediaQuery.paddingOf(context).top + 60,
                          left: 16,
                          right: 16,
                          child: _ZoomLensControl(
                            scale: readerScale,
                            onDecrease: () =>
                                _setReaderScale(context, readerScale - .1),
                            onReset: () => _setReaderScale(context, 1),
                            onIncrease: () =>
                                _setReaderScale(context, readerScale + .1),
                          ),
                        ),
                      if (_focus)
                        PositionedDirectional(
                          top: MediaQuery.paddingOf(context).top + 8,
                          start: 8,
                          child: Material(
                            color: Theme.of(context).colorScheme.surface
                                .withValues(alpha: .9),
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'إنهاء ملء الشاشة',
                              onPressed: () => setState(() => _focus = false),
                              icon: const Icon(Icons.fullscreen_exit),
                            ),
                          ),
                        ),
                    ],
                  ),
                  bottomNavigationBar: _focus ? null : _buildBottomBar(context),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final recallCubit = _tryGetVisualRecallCubit(context);
    if (recallCubit != null) {
      return BlocBuilder<QuranVisualRecallCubit, QuranVisualRecallState>(
        bloc: recallCubit,
        buildWhen: (prev, curr) =>
            prev.phase != curr.phase ||
            prev.hasActiveSession != curr.hasActiveSession ||
            prev.isRangeSelecting != curr.isRangeSelecting ||
            prev.isCompleted != curr.isCompleted ||
            prev.isLoading != curr.isLoading ||
            prev.error != curr.error ||
            prev.currentIndex != curr.currentIndex,
        builder: (context, recallState) {
          if (recallState.hasActiveSession ||
              recallState.isRangeSelecting ||
              recallState.isCompleted) {
            return VisualRecallBottomBar(cubit: recallCubit);
          }
          return _buildRegularBottomBar(context);
        },
      );
    }
    return _buildRegularBottomBar(context);
  }

  Widget _buildRegularBottomBar(BuildContext context) {
    final readerBar = _ReaderBottomBar(onOptions: () => _showOptions(context));
    final planId = widget.khatmaPlanId;
    final startPage = widget.khatmaStartPage;
    final targetPage = widget.khatmaTargetPage;
    if (planId == null || startPage == null || targetPage == null) {
      return readerBar;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BlocBuilder<KhatmaCubit, KhatmaState>(
          buildWhen: (previous, current) => previous.plans != current.plans,
          builder: (context, khatmaState) {
            final plan = khatmaState.plans
                .where((item) => item.id == planId)
                .firstOrNull;
            if (plan == null) return const SizedBox.shrink();
            return BlocBuilder<QuranCubit, QuranState>(
              buildWhen: (previous, current) =>
                  previous.currentPage != current.currentPage,
              builder: (context, quranState) => _KhatmaReaderProgressBar(
                plan: plan,
                planName: widget.khatmaPlanName ?? plan.name,
                startPage: startPage,
                targetPage: targetPage,
                currentPage: quranState.currentPage,
              ),
            );
          },
        ),
        readerBar,
      ],
    );
  }

  void _trackKhatmaPage(BuildContext context, int page) {
    final planId = widget.khatmaPlanId;
    final startPage = widget.khatmaStartPage;
    final targetPage = widget.khatmaTargetPage;
    if (planId == null || startPage == null || targetPage == null) return;

    final previousPage = _lastKhatmaPage;
    _lastKhatmaPage = page;
    final isSequentialForward =
        previousPage != null &&
        page == previousPage + 1 &&
        previousPage >= startPage &&
        previousPage <= targetPage;
    final savedPage = page.clamp(startPage, targetPage).toInt();
    unawaited(
      context.read<KhatmaCubit>().recordReadingPosition(
        planId: planId,
        currentPage: savedPage,
        completedThrough: isSequentialForward ? previousPage : null,
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

  Future<void> _showOptions(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: context.read<QuranCubit>()),
        BlocProvider.value(value: context.read<SettingsCubit>()),
      ],
      child: const _ReaderOptionsSheet(),
    ),
  );
}

class _ZoomLensControl extends StatelessWidget {
  const _ZoomLensControl({
    required this.scale,
    required this.onDecrease,
    required this.onReset,
    required this.onIncrease,
  });

  final double scale;
  final VoidCallback onDecrease;
  final VoidCallback onReset;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final percent = (scale * 100).round();

    return Material(
      color: colors.surfaceMuted,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MishkatRadius.pill),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        label: 'حجم المصحف $percent بالمئة',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search_rounded, color: colors.primary, size: 19),
            const SizedBox(width: 6),
            Text(
              'حجم الصفحة',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 22, color: colors.border),
            IconButton(
              tooltip: 'تصغير المصحف',
              onPressed: scale > 1.005 ? onDecrease : null,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_rounded),
            ),
            InkWell(
              onTap: onReset,
              borderRadius: BorderRadius.circular(MishkatRadius.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                child: Text(
                  '$percent%',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'تكبير المصحف',
              onPressed: scale < 1.87 ? onIncrease : null,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class MushafThemeColors {
  const MushafThemeColors._();

  static const lightBackground = Color(0xFFF6F1E8);
  static const lightInk = Color(0xFF231F20);

  static const darkBackground = Color(0xFF121C17);
  static const darkInk = Color(0xFFECE5D8);
}

typedef _MushafPage = MushafPage;

class MushafPage extends StatefulWidget {
  const MushafPage({
    super.key,
    required this.page,
    required this.scale,
    required this.isCurrent,
    this.onZoomChanged,
  });

  final int page;
  final double scale;
  final bool isCurrent;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<_MushafPage> {
  late final TransformationController _transformationController;
  bool _isZoomed = false;
  Size _viewportSize = Size.zero;
  double? _appliedScale;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController()
      ..addListener(_onTransformationChanged);
  }

  @override
  void didUpdateWidget(covariant _MushafPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyScale(widget.scale);
      });
    }
    if (oldWidget.isCurrent != widget.isCurrent) {
      if (widget.isCurrent && !oldWidget.isCurrent) {
        widget.onZoomChanged?.call(_isZoomed);
      }
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    _updateZoomState();
  }

  void _updateZoomState() {
    final matrixScale = _transformationController.value.getMaxScaleOnAxis();
    final isZoomed = matrixScale > 1.05;
    if (_isZoomed != isZoomed) {
      _isZoomed = isZoomed;
      if (widget.isCurrent) {
        widget.onZoomChanged?.call(_isZoomed);
      }
    }
  }

  void _resetZoom() {
    try {
      context.read<QuranCubit>().setFontSize(32);
      context.read<SettingsCubit>().setQuranFont(32);
    } catch (_) {
      _applyScale(1);
    }
  }

  void _applyScale(double requestedScale) {
    if (_viewportSize.isEmpty) return;
    final targetScale = requestedScale.clamp(1.0, 1.875).toDouble();
    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    if ((currentScale - targetScale).abs() < .005 &&
        _appliedScale == targetScale) {
      return;
    }

    final center = _viewportSize.center(Offset.zero);
    final sceneCenter = _transformationController.toScene(center);
    final next = Matrix4.identity()
      ..setEntry(0, 0, targetScale)
      ..setEntry(1, 1, targetScale)
      ..setEntry(0, 3, center.dx - targetScale * sceneCenter.dx)
      ..setEntry(1, 3, center.dy - targetScale * sceneCenter.dy);
    _appliedScale = targetScale;
    _transformationController.value = next;
    _updateZoomState();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = context.mishkat;
    final colorFilter = isDark
        ? const ColorFilter.mode(MushafThemeColors.darkInk, BlendMode.srcIn)
        : null;

    final hasInteractionCubit =
        context
            .findAncestorWidgetOfExactType<
              BlocProvider<MushafInteractionCubit>
            >() !=
        null;

    Widget buildPageContent(
      AyahBounds? selectedAyah,
      AyahBounds? playingAyah,
      List<AyahBounds> bookmarkedAyahs,
      MushafLayoutRepository? layoutRepo,
    ) {
      final effectiveLayoutRepo =
          layoutRepo ??
          (MushafLayoutRepository.instance.isLoaded
              ? MushafLayoutRepository.instance
              : null);
      final pageGeom = effectiveLayoutRepo?.getPageGeometry(widget.page);
      final viewBox =
          pageGeom?.viewBox ??
          (widget.page <= 2
              ? const Rect.fromLTWH(-53.3109, -198.4777, 345, 550)
              : const Rect.fromLTWH(0, 0, 345, 550));

      final visualRecallCubit = _tryGetVisualRecallCubit(context);

      Widget stack = Stack(
        fit: StackFit.expand,
        children: [
          SvgPicture.asset(
            'assets/mushaf/pages/${widget.page.toString().padLeft(3, '0')}.svg',
            fit: BoxFit.contain,
            colorFilter: colorFilter,
            placeholderBuilder: (_) =>
                const Center(child: CircularProgressIndicator()),
          ),
          if (selectedAyah != null ||
              playingAyah != null ||
              bookmarkedAyahs.isNotEmpty)
            MushafAyahOverlay(
              selectedAyah: selectedAyah,
              playingAyah: playingAyah,
              bookmarkedAyahs: bookmarkedAyahs,
              viewBox: viewBox,
            ),
          if (visualRecallCubit != null)
            BlocSelector<
              QuranVisualRecallCubit,
              QuranVisualRecallState,
              ({Set<int> maskedGlobals, int? currentGlobalAyah})
            >(
              bloc: visualRecallCubit,
              selector: (state) => (
                maskedGlobals: state.activeMaskedGlobals,
                currentGlobalAyah: state.currentGlobalAyah,
              ),
              builder: (context, maskState) {
                if (maskState.maskedGlobals.isEmpty ||
                    effectiveLayoutRepo == null ||
                    !effectiveLayoutRepo.isLoaded) {
                  return const SizedBox.shrink();
                }
                final geom = effectiveLayoutRepo.getPageGeometry(widget.page);
                if (geom == null) return const SizedBox.shrink();

                final pageMaskedAyahs = geom.ayahs
                    .where(
                      (ayah) =>
                          maskState.maskedGlobals.contains(ayah.globalAyah),
                    )
                    .toList();

                if (pageMaskedAyahs.isEmpty) return const SizedBox.shrink();

                return MushafVisualMaskOverlay(
                  maskedAyahs: pageMaskedAyahs,
                  currentAyah: pageMaskedAyahs
                      .where(
                        (ayah) =>
                            ayah.globalAyah == maskState.currentGlobalAyah,
                      )
                      .firstOrNull,
                  viewBox: viewBox,
                  maskColor: isDark
                      ? MushafThemeColors.darkBackground
                      : MushafThemeColors.lightBackground,
                  currentNumberOutlineColor: colors.primary,
                );
              },
            ),
        ],
      );

      if (visualRecallCubit != null) {
        stack = MushafVisualRecallInteractionLayer(
          page: widget.page,
          visualRecallCubit: visualRecallCubit,
          effectiveLayoutRepo: effectiveLayoutRepo,
          viewBox: viewBox,
          onDoubleTap: _resetZoom,
          child: stack,
        );
      }

      if (hasInteractionCubit) {
        if (visualRecallCubit == null) {
          stack = MushafInteractionLayer(
            page: widget.page,
            onDoubleTap: _resetZoom,
            child: stack,
          );
        } else {
          final visualRecallStack = stack;
          stack =
              BlocSelector<
                QuranVisualRecallCubit,
                QuranVisualRecallState,
                bool
              >(
                bloc: visualRecallCubit,
                selector: (state) =>
                    state.hasActiveSession || state.isRangeSelecting,
                builder: (context, isVisualRecallActive) {
                  if (isVisualRecallActive) return visualRecallStack;
                  return MushafInteractionLayer(
                    page: widget.page,
                    onDoubleTap: _resetZoom,
                    child: visualRecallStack,
                  );
                },
              );
        }
      }

      return stack;
    }

    return ColoredBox(
      color: isDark
          ? MushafThemeColors.darkBackground
          : MushafThemeColors.lightBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final nextSize = Size(constraints.maxWidth, constraints.maxHeight);
          if (_viewportSize != nextSize || _appliedScale == null) {
            _viewportSize = nextSize;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _applyScale(widget.scale);
            });
          }
          return InteractiveViewer(
            transformationController: _transformationController,
            constrained: false,
            minScale: 1,
            maxScale: 3,
            boundaryMargin: const EdgeInsets.all(56),
            panEnabled: _isZoomed,
            onInteractionEnd: (_) {
              _appliedScale = _transformationController.value
                  .getMaxScaleOnAxis();
              _updateZoomState();
            },
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: hasInteractionCubit
                    ? BlocSelector<
                        MushafInteractionCubit,
                        MushafInteractionState,
                        ({AyahBounds? selectedAyah, AyahBounds? playingAyah})
                      >(
                        selector: (state) {
                          final selected = state.selectedPage == widget.page
                              ? state.selectedAyah
                              : null;
                          final playingGlobal = state.playingAyah;
                          final layoutRepo = context
                              .read<MushafInteractionCubit>()
                              .layoutRepository;
                          AyahBounds? playing;
                          if (playingGlobal != null && layoutRepo.isLoaded) {
                            final ayah = layoutRepo.getAyah(playingGlobal);
                            if (ayah?.page == widget.page) {
                              playing = ayah;
                            }
                          }
                          return (selectedAyah: selected, playingAyah: playing);
                        },
                        builder: (context, highlights) {
                          final bookmarks = context
                              .select<QuranCubit, List<QuranBookmark>>(
                                (cubit) => cubit.state.getBookmarksForPage(
                                  widget.page,
                                ),
                              );
                          final layoutRepo = context
                              .read<MushafInteractionCubit>()
                              .layoutRepository;
                          final List<AyahBounds> bookmarkedBounds = [];
                          if (bookmarks.isNotEmpty && layoutRepo.isLoaded) {
                            for (final b in bookmarks) {
                              final bounds = layoutRepo.getAyah(b.point.global);
                              if (bounds != null &&
                                  bounds.page == widget.page) {
                                bookmarkedBounds.add(bounds);
                              }
                            }
                          }
                          return buildPageContent(
                            highlights.selectedAyah,
                            highlights.playingAyah,
                            bookmarkedBounds,
                            layoutRepo,
                          );
                        },
                      )
                    : buildPageContent(null, null, const [], null),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KhatmaReaderProgressBar extends StatelessWidget {
  const _KhatmaReaderProgressBar({
    required this.plan,
    required this.planName,
    required this.startPage,
    required this.targetPage,
    required this.currentPage,
  });

  final KhatmaPlan plan;
  final String planName;
  final int startPage;
  final int targetPage;
  final int currentPage;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final total = math.max(1, targetPage - startPage + 1);
    final completed = (math.min(plan.progressPage, targetPage) - startPage + 1)
        .clamp(0, total);
    final effectivePage = currentPage.clamp(startPage, targetPage).toInt();
    final atTarget = effectivePage >= targetPage;
    final currentSaved = plan.progressPage >= effectivePage;
    final wardCompleted = plan.progressPage >= targetPage;

    return Material(
      color: colors.primarySoft,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
          child: Row(
            children: [
              Icon(Icons.route_rounded, size: 21, color: colors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ورد $planName · $completed من $total صفحة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(MishkatRadius.pill),
                      child: LinearProgressIndicator(
                        value: completed / total,
                        minHeight: 4,
                        backgroundColor: colors.surface,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                ),
                onPressed: plan.status != KhatmaStatus.active || currentSaved
                    ? null
                    : () async {
                        await context.read<KhatmaCubit>().completeReadingPage(
                          planId: plan.id,
                          page: effectivePage,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              atTarget
                                  ? 'تم تسجيل وردك اليوم — تقبّل الله منك.'
                                  : 'تم حفظ القراءة حتى صفحة $effectivePage.',
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  wardCompleted
                      ? 'تم الورد'
                      : currentSaved
                      ? 'محفوظ'
                      : atTarget
                      ? 'إتمام الورد'
                      : 'أتممت الصفحة',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({required this.onOptions});
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state.settings;
    final cubit = context.read<QuranCubit>();
    return BlocBuilder<QuranCubit, QuranState>(
      buildWhen: (previous, current) =>
          previous.audioStatus != current.audioStatus ||
          previous.currentPage != current.currentPage,
      builder: (context, state) {
        final playing = state.audioStatus == QuranAudioStatus.playing;
        final loading = state.audioStatus == QuranAudioStatus.loading;
        final colors = context.mishkat;
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(MishkatRadius.lg),
            ),
            border: Border(top: BorderSide(color: colors.border)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 22,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const QuranMiniPlayer(
                  playbackOrigin: QuranPlaybackOrigin.mushaf,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Row(
                    children: [
                      _ReaderDockButton(
                        tooltip: 'الصفحة السابقة',
                        onPressed: state.currentPage > 1
                            ? () => cubit.openPage(state.currentPage - 1)
                            : null,
                        icon: Icons.chevron_right_rounded,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Material(
                          color: colors.surfaceMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              MishkatRadius.md,
                            ),
                            side: BorderSide(color: colors.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onOptions,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 7),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.menu_book_rounded,
                                        size: 18,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        'صفحة ${state.currentPage}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      Text(
                                        '  من 604',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: colors.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: state.currentPage / 604,
                                      minHeight: 3,
                                      backgroundColor: colors.border,
                                      color: colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ReaderDockButton(
                        tooltip: 'الصفحة التالية',
                        onPressed: state.currentPage < 604
                            ? () => cubit.openPage(state.currentPage + 1)
                            : null,
                        icon: Icons.chevron_left_rounded,
                      ),
                      const SizedBox(width: 10),
                      SizedBox.square(
                        dimension: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: const CircleBorder(),
                          ),
                          onPressed: loading
                              ? null
                              : () => cubit.toggleAudio(
                                  continuous: settings.quranContinuous,
                                  autoScroll: settings.quranAutoScroll,
                                  origin: QuranPlaybackOrigin.mushaf,
                                ),
                          child: loading
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 28,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReaderDockButton extends StatelessWidget {
  const _ReaderDockButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Material(
      color: colors.surfaceMuted,
      shape: CircleBorder(side: BorderSide(color: colors.border)),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _ReaderOptionsSheet extends StatefulWidget {
  const _ReaderOptionsSheet();

  @override
  State<_ReaderOptionsSheet> createState() => _ReaderOptionsSheetState();
}

class _ReaderOptionsSheetState extends State<_ReaderOptionsSheet> {
  late final TextEditingController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = TextEditingController(
      text: '${context.read<QuranCubit>().state.currentPage}',
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuranCubit, QuranState>(
      builder: (context, quran) {
        return BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, settingsState) {
            final settings = settingsState.settings;
            final effectiveFontSize = quran.fontSize.clamp(32.0, 60.0);
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.mishkat.border,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'خيارات القراءة',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('تم'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'حجم المصحف · ${(effectiveFontSize / 32 * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Row(
                    children: [
                      const Text('أ', style: TextStyle(fontSize: 14)),
                      Expanded(
                        child: Slider(
                          min: 32,
                          max: 60,
                          value: effectiveFontSize,
                          onChanged: (value) {
                            context.read<QuranCubit>().setFontSize(value);
                            context.read<SettingsCubit>().setQuranFont(value);
                          },
                        ),
                      ),
                      const Text('أ', style: TextStyle(fontSize: 28)),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final preset in const [
                        (32, 'ملائم'),
                        (44, 'كبير'),
                        (60, 'كبير جدًا'),
                      ])
                        ChoiceChip(
                          label: Text(preset.$2),
                          selected: quran.fontSize.round() == preset.$1,
                          onSelected: (_) {
                            context.read<QuranCubit>().setFontSize(
                              preset.$1.toDouble(),
                            );
                            context.read<SettingsCubit>().setQuranFont(
                              preset.$1.toDouble(),
                            );
                          },
                        ),
                    ],
                  ),
                  const Divider(height: 32),
                  TextField(
                    controller: _pageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'انتقال مباشر إلى صفحة',
                      suffixIcon: IconButton(
                        onPressed: () {
                          final page = int.tryParse(_pageController.text);
                          if (page != null) {
                            context.read<QuranCubit>().openPage(page);
                            Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: settings.reciter,
                    decoration: const InputDecoration(labelText: 'القارئ'),
                    items: [
                      for (final reciter in AppConstants.reciters)
                        DropdownMenuItem(
                          value: reciter.id,
                          child: Text(reciter.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      context.read<SettingsCubit>().setReciter(value);
                      context.read<QuranCubit>().updateReciter(value);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('متابعة التلاوة تلقائيًا'),
                    value: settings.quranContinuous,
                    onChanged: context.read<SettingsCubit>().setContinuousAudio,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تتبّع موضع التلاوة'),
                    value: settings.quranAutoScroll,
                    onChanged: context.read<SettingsCubit>().setAutoScroll,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
