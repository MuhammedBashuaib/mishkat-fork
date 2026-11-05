import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../data/models/quran_audio_station.dart';
import '../../data/models/quran_models.dart';
import '../../data/services/haramain_live_service.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_state.dart';
import '../widgets/quran_mini_player.dart';
import 'haramain_live_page.dart';
import 'offline_audio_downloads_page.dart';

/// Dedicated Quran Audio Player page housing Recitations, Live Streams, and Quran Radios.
class QuranAudioPlayerPage extends StatefulWidget {
  const QuranAudioPlayerPage({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      builder: (_) => const QuranAudioPlayerPage(),
    );
  }

  @override
  State<QuranAudioPlayerPage> createState() => _QuranAudioPlayerPageState();
}

class _QuranAudioPlayerPageState extends State<QuranAudioPlayerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _reciterSearchController =
      TextEditingController();
  String _reciterFilter = '';
  String? _openingLiveId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reciterSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'المشغّل القرآني',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'التنزيلات دون إنترنت',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const OfflineAudioDownloadsPage(),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colors.primary,
          labelColor: colors.primary,
          unselectedLabelColor: colors.textSecondary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          tabs: const [
            Tab(
              text: 'القراء والتلاوات',
              icon: Icon(Icons.record_voice_over_rounded, size: 20),
            ),
            Tab(
              text: 'البث المباشر',
              icon: Icon(Icons.mosque_rounded, size: 20),
            ),
            Tab(
              text: 'إذاعات القرآن',
              icon: Icon(Icons.radio_rounded, size: 20),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRecitersTab(context),
                _buildLiveStreamsTab(context),
                _buildRadioStationsTab(context),
              ],
            ),
          ),
          // Persistent Mini Player at bottom of Audio Hub
          const SafeArea(
            top: false,
            child: QuranMiniPlayer(
              playbackOrigin: QuranPlaybackOrigin.audioPlayer,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: القراء والتلاوات
  // ---------------------------------------------------------------------------
  Widget _buildRecitersTab(BuildContext context) {
    final colors = context.mishkat;
    final cubit = context.watch<QuranCubit>();
    final currentReciterId = cubit.reciter;
    final quranData = cubit.state.data;

    final filteredReciters = _reciterFilter.isEmpty
        ? AppConstants.reciters
        : AppConstants.reciters
              .where(
                (r) => AppFormatters.normalizeArabic(r.name)
                    .contains(AppFormatters.normalizeArabic(_reciterFilter)),
              )
              .toList(growable: false);

    return ListView(
      padding: MishkatSpacing.page,
      children: [
        // Search Bar
        TextField(
          controller: _reciterSearchController,
          decoration: InputDecoration(
            hintText: 'ابحث عن قارئ...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            suffixIcon: _reciterFilter.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _reciterSearchController.clear();
                      setState(() => _reciterFilter = '');
                    },
                  )
                : null,
          ),
          onChanged: (val) => setState(() => _reciterFilter = val.trim()),
        ),
        const SizedBox(height: MishkatSpacing.base),

        // Active Reciter Info Card
        Builder(
          builder: (context) {
            final activeReciter = AppConstants.findReciter(currentReciterId);
            return MishkatCard(
              color: colors.primarySoft,
              borderColor: colors.primary.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(MishkatSpacing.base),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mic_external_on_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: MishkatSpacing.base),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'القارئ الحالي: ${activeReciter.name}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'سور كاملة بتلاوة متصلة',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (quranData != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text(
                        'اختيار سورة',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: () => _showSurahPickerSheet(
                        context,
                        quranData,
                        activeReciter,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: MishkatSpacing.lg),

        // Available Reciters Header
        Row(
          children: [
            Expanded(
              child: Text(
                'القراء المتاحون (${filteredReciters.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(MishkatRadius.xs),
              ),
              child: Text(
                'تشغيل مباشر',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: MishkatSpacing.sm),

        // List of Verified Reciters
        for (final reciter in filteredReciters)
          _ReciterTile(
            reciter: reciter,
            isSelected: reciter.id == currentReciterId,
            onSelect: () {
              if (quranData != null) {
                _showSurahPickerSheet(context, quranData, reciter);
              }
            },
            onPlaySurah: quranData == null
                ? null
                : () {
                    _showSurahPickerSheet(context, quranData, reciter);
                  },
          ),
        if (filteredReciters.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MishkatSpacing.xl),
            child: Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 36,
                  color: colors.textMuted,
                ),
                const SizedBox(height: MishkatSpacing.sm),
                Text(
                  'لا يوجد قارئ بهذا الاسم',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: البث المباشر
  // ---------------------------------------------------------------------------
  Widget _buildLiveStreamsTab(BuildContext context) {
    final colors = context.mishkat;

    final liveStreams = QuranAudioStation.defaultCatalog
        .where((s) => s.category == AudioStationCategory.liveStream)
        .toList(growable: false);

    return ListView(
      padding: MishkatSpacing.page,
      children: [
        // Live streams header banner
        MishkatCard(
          color: colors.surfaceVariant.withValues(alpha: 0.5),
          padding: const EdgeInsets.all(MishkatSpacing.base),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: colors.primary, size: 20),
              const SizedBox(width: MishkatSpacing.sm),
              Expanded(
                child: Text(
                  'البث المباشر المعتمد ينقل الصلوات والتلاوات من الحرمين الشريفين.',
                  style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MishkatSpacing.base),

        for (final station in liveStreams)
          _LiveStreamCard(
            station: station,
            isOpening: _openingLiveId == station.id,
            onWatch: () => _openLiveStream(context, station),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: إذاعات القرآن الكريم
  // ---------------------------------------------------------------------------
  Widget _buildRadioStationsTab(BuildContext context) {
    final colors = context.mishkat;
    final cubit = context.watch<QuranCubit>();
    final activeStation = cubit.state.activeStation;
    final isPlaying = cubit.state.audioStatus == QuranAudioStatus.playing;

    final radios = QuranAudioStation.defaultCatalog
        .where((s) => s.category == AudioStationCategory.radio)
        .toList(growable: false);

    return ListView(
      padding: MishkatSpacing.page,
      children: [
        // Radios header banner
        MishkatCard(
          color: colors.surfaceVariant.withValues(alpha: 0.5),
          padding: const EdgeInsets.all(MishkatSpacing.base),
          child: Row(
            children: [
              Icon(Icons.radio_rounded, color: colors.gold, size: 20),
              const SizedBox(width: MishkatSpacing.sm),
              Expanded(
                child: Text(
                  '${radios.length} محطات قرآنية مباشرة من مصادر رسمية وموثوقة.',
                  style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MishkatSpacing.base),

        for (final station in radios)
          _StationCard(
            station: station,
            isActive: activeStation?.id == station.id && isPlaying,
            onPlay: () => _handleStationPlay(context, station),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Handlers & Sheets
  // ---------------------------------------------------------------------------
  Future<void> _openLiveStream(
    BuildContext context,
    QuranAudioStation station,
  ) async {
    final rawUrl = station.watchUrl;
    final channelId = station.youtubeChannelId;
    if (rawUrl == null ||
        rawUrl.isEmpty ||
        channelId == null ||
        channelId.isEmpty ||
        _openingLiveId != null) {
      return;
    }

    setState(() => _openingLiveId = station.id);
    try {
      await context.read<QuranCubit>().stopAudio();
      if (!context.mounted) return;
      await Navigator.of(context).push(HaramainLivePage.route(station));
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر فتح مشغّل البث. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingLiveId = null);
    }
  }

  void _handleStationPlay(BuildContext context, QuranAudioStation station) {
    final cubit = context.read<QuranCubit>();
    final isActive =
        cubit.state.activeStation?.id == station.id &&
        cubit.state.audioStatus == QuranAudioStatus.playing;

    if (isActive) {
      cubit.stopAudio();
      return;
    }

    if (!station.isPlayable) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(station.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 18,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    station.availabilityLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                station.notes ?? 'رابط البث الرسمي قيد المراجعة والتوثيق التقني لضمان استقرار البث وسلامة المحتوى.',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      cubit.playStation(station);
      return;
    }

    cubit.playStation(station);
  }

  void _showSurahPickerSheet(
    BuildContext context,
    QuranData data,
    ReciterInfo reciter,
  ) {
    final cubit = context.read<QuranCubit>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MishkatRadius.xl),
        ),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(MishkatSpacing.base),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'اختر السورة للاستماع بصوت ${reciter.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: data.chapters.length,
                itemBuilder: (ctx, idx) {
                  final chapter = data.chapters[idx];
                  return ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ctx.mishkat.primarySoft,
                        borderRadius: BorderRadius.circular(MishkatRadius.sm),
                      ),
                      child: Text(
                        '${chapter.number}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: ctx.mishkat.primary,
                        ),
                      ),
                    ),
                    title: Text(
                      'سورة ${chapter.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${chapter.revelationType} · ${chapter.ayahs.length} آية · صفحة ${chapter.page}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.play_circle_fill_rounded),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      cubit.updateReciter(reciter.id, restartIfPlaying: false);
                      context.read<SettingsCubit>().setReciter(reciter.id);
                      cubit.playSurah(chapter.number);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Helper Widgets
// -----------------------------------------------------------------------------
class _ReciterTile extends StatelessWidget {
  const _ReciterTile({
    required this.reciter,
    required this.isSelected,
    required this.onSelect,
    required this.onPlaySurah,
  });

  final ReciterInfo reciter;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback? onPlaySurah;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;

    return Padding(
      padding: const EdgeInsets.only(bottom: MishkatSpacing.xs),
      child: MishkatCard(
        borderColor: isSelected ? colors.primary : null,
        padding: const EdgeInsets.symmetric(
          horizontal: MishkatSpacing.md,
          vertical: MishkatSpacing.sm,
        ),
        onTap: onSelect,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected ? colors.primary : colors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSelected ? Icons.check_rounded : Icons.person_outline_rounded,
                color: isSelected ? Colors.white : colors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: MishkatSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reciter.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'تلاوة السورة كاملة',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            if (onPlaySurah != null)
              IconButton(
                tooltip: 'اختيار سورة والاستماع',
                icon: Icon(
                  Icons.play_circle_outline_rounded,
                  color: colors.primary,
                  size: 26,
                ),
                onPressed: onPlaySurah,
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveStreamCard extends StatelessWidget {
  const _LiveStreamCard({
    required this.station,
    required this.isOpening,
    required this.onWatch,
  });

  final QuranAudioStation station;
  final bool isOpening;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final isMakkah = station.id == 'stream_haram_makkah';
    final accent = isMakkah ? colors.gold : const Color(0xFF65D6B4);

    return Padding(
      padding: const EdgeInsets.only(bottom: MishkatSpacing.base),
      child: Semantics(
        button: true,
        label: '${station.title}، مباشر الآن، مشاهدة البث الرسمي',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MishkatRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .16),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Material(
              color: const Color(0xFF092B24),
              borderRadius: BorderRadius.circular(MishkatRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isOpening ? null : onWatch,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _LiveThumbnail(station: station, accent: accent),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, .42, 1],
                          colors: [
                            Color(0x99000000),
                            Color(0x10000000),
                            Color(0xE6000000),
                          ],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 12,
                      start: 12,
                      end: 12,
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: _LiveBadge(
                                color: const Color(0xFFE13F45),
                                icon: Icons.circle,
                                label: 'مباشر الآن',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: _LiveBadge(
                                color: Colors.black.withValues(alpha: .48),
                                icon: Icons.verified_rounded,
                                label: 'مصدر رسمي',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PositionedDirectional(
                      start: 14,
                      end: 14,
                      bottom: 13,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  station.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  station.city ?? station.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(
                                MishkatRadius.pill,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: isOpening
                                ? const SizedBox.square(
                                    dimension: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF092B24),
                                    ),
                                  )
                                : const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.play_arrow_rounded,
                                        size: 19,
                                        color: Color(0xFF092B24),
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'شاهد البث',
                                        style: TextStyle(
                                          color: Color(0xFF092B24),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
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
}

class _LiveThumbnail extends StatelessWidget {
  const _LiveThumbnail({required this.station, required this.accent});

  final QuranAudioStation station;
  final Color accent;

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: HaramainLiveService.resolveVideoId(station),
    builder: (context, snapshot) {
      final fallback = _ThumbnailFallback(accent: accent);
      final videoId = snapshot.data;
      if (videoId == null) return fallback;

      return Stack(
        fit: StackFit.expand,
        children: [
          fallback,
          Image.network(
            HaramainLiveService.thumbnailUrl(videoId),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => fallback,
          ),
        ],
      );
    },
  );
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF174A43), Color(0xFF071F1A)],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.live_tv_rounded,
        color: accent.withValues(alpha: .8),
        size: 46,
      ),
    ),
  );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(MishkatRadius.pill),
      border: Border.all(color: Colors.white.withValues(alpha: .16)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: icon == Icons.circle ? 7 : 15, color: Colors.white),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.station,
    required this.isActive,
    required this.onPlay,
  });

  final QuranAudioStation station;
  final bool isActive;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final isLive = station.category == AudioStationCategory.liveStream;

    return Padding(
      padding: const EdgeInsets.only(bottom: MishkatSpacing.sm),
      child: MishkatCard(
        borderColor: isActive ? colors.primary : null,
        padding: const EdgeInsets.all(MishkatSpacing.base),
        onTap: onPlay,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isActive ? colors.primary : colors.primarySoft,
                borderRadius: BorderRadius.circular(MishkatRadius.md),
              ),
              child: Icon(
                isLive ? Icons.mosque_rounded : Icons.radio_rounded,
                color: isActive ? Colors.white : colors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: MishkatSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: station.isPlayable
                          ? colors.primarySoft
                          : Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(MishkatRadius.xs),
                    ),
                    child: Text(
                      station.availabilityLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: station.isPlayable
                            ? colors.primary
                            : Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    station.subtitle,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  if (station.sourceLabel != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          size: 13,
                          color: colors.gold,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            station.sourceLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: MishkatSpacing.xs),
            IconButton(
              tooltip: isActive ? 'إيقاف' : 'تشغيل',
              icon: Icon(
                isActive
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                color: colors.primary,
                size: 32,
              ),
              onPressed: onPlay,
            ),
          ],
        ),
      ),
    );
  }
}
