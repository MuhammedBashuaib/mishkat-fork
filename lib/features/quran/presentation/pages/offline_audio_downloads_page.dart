import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/offline_audio_download_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../cubit/quran_cubit.dart';
import '../services/quran_surah_search.dart';

class OfflineAudioDownloadsPage extends StatefulWidget {
  const OfflineAudioDownloadsPage({super.key});

  @override
  State<OfflineAudioDownloadsPage> createState() =>
      _OfflineAudioDownloadsPageState();
}

class _OfflineAudioDownloadsPageState extends State<OfflineAudioDownloadsPage> {
  late String _reciterId;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reciterId = context.read<QuranCubit>().reciter;
    if (AppConstants.findReciter(_reciterId).source ==
        ReciterAudioSource.segmentedSurah) {
      _reciterId = AppConstants.reciters
          .firstWhere((r) => r.source != ReciterAudioSource.segmentedSurah)
          .id;
    }
    context.read<OfflineAudioDownloadController>().initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<OfflineAudioDownloadController>();
    final data = context.watch<QuranCubit>().state.data;
    final reciter = AppConstants.findReciter(_reciterId);
    final chapters = data == null
        ? null
        : QuranSurahSearch.findChapters(data.chapters, _query);
    return Scaffold(
      appBar: AppBar(title: const Text('المحتوى دون إنترنت')),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) => ListView(
                padding: MishkatSpacing.page,
                children: [
                  _OfflineIntro(sizeMb: controller.cache.currentCacheSizeMb),
                  const SizedBox(height: MishkatSpacing.base),
                  DropdownButtonFormField<String>(
                    initialValue: _reciterId,
                    decoration: const InputDecoration(
                      labelText: 'القارئ للتنزيل',
                      prefixIcon: Icon(Icons.record_voice_over_rounded),
                    ),
                    items: [
                      for (final item in AppConstants.reciters)
                        if (item.source != ReciterAudioSource.segmentedSurah)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                    ],
                    onChanged: controller.state.isRunning
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _reciterId = value);
                            }
                          },
                  ),
                  if (controller.state.status !=
                      OfflineDownloadStatus.idle) ...[
                    const SizedBox(height: MishkatSpacing.base),
                    _DownloadProgressCard(controller: controller),
                  ],
                  const SectionHeading(
                    title: 'السور',
                    padding: EdgeInsets.only(top: 22, bottom: 2),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'نزّل ما تحتاجه فقط، وسيعمل الصوت بلا شبكة',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.mishkat.textSecondary,
                      ),
                    ),
                  ),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم السورة أو رقمها',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: MishkatSpacing.sm),
                  if (chapters!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('لا توجد سور مطابقة لبحثك')),
                    ),
                  for (final chapter in chapters)
                    Builder(
                      builder: (context) {
                        final saved = controller.cachedCountNow(
                          reciter: reciter.id,
                          startAyah: chapter.globalStart,
                          endAyah:
                              chapter.globalStart + chapter.ayahs.length - 1,
                        );
                        final total = chapter.ayahs.length;
                        final complete = saved == total;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: complete
                                ? context.mishkat.primary
                                : context.mishkat.primarySoft,
                            foregroundColor: complete
                                ? Colors.white
                                : context.mishkat.primary,
                            child: complete
                                ? const Icon(
                                    Icons.offline_pin_rounded,
                                    size: 20,
                                  )
                                : Text('${chapter.number}'),
                          ),
                          title: Text('سورة ${chapter.name}'),
                          subtitle: Text(
                            complete
                                ? 'محفوظة بالكامل · $total آية'
                                : saved > 0
                                ? 'محفوظ $saved من $total'
                                : '$total آية',
                          ),
                          trailing: IconButton(
                            tooltip: complete ? 'حذف التنزيل' : 'تنزيل السورة',
                            onPressed: controller.state.isRunning
                                ? null
                                : () async {
                                    if (complete) {
                                      await controller.removeRange(
                                        reciter: reciter.id,
                                        startAyah: chapter.globalStart,
                                        endAyah:
                                            chapter.globalStart + total - 1,
                                      );
                                      if (mounted) setState(() {});
                                    } else {
                                      await controller.downloadSurah(
                                        reciter: reciter,
                                        chapter: chapter,
                                      );
                                    }
                                  },
                            icon: Icon(
                              complete
                                  ? Icons.delete_outline_rounded
                                  : Icons.download_for_offline_outlined,
                              color: complete
                                  ? context.mishkat.textSecondary
                                  : context.mishkat.primary,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}

class _OfflineIntro extends StatelessWidget {
  const _OfflineIntro({required this.sizeMb});
  final double sizeMb;

  @override
  Widget build(BuildContext context) => MishkatCard(
    color: context.mishkat.primarySoft,
    padding: const EdgeInsets.all(MishkatSpacing.base),
    child: Row(
      children: [
        Icon(
          Icons.cloud_done_rounded,
          color: context.mishkat.primary,
          size: 32,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'المصحف والأذكار جاهزان دائمًا',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'الصوت المحفوظ: ${sizeMb.toStringAsFixed(1)} م.ب · التنزيلات اليدوية لا تُحذف تلقائيًا',
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
  );
}

class _DownloadProgressCard extends StatelessWidget {
  const _DownloadProgressCard({required this.controller});
  final OfflineAudioDownloadController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final isSuccess = state.status == OfflineDownloadStatus.completed;
    final color = state.status == OfflineDownloadStatus.failed
        ? Theme.of(context).colorScheme.error
        : context.mishkat.primary;
    return MishkatCard(
      padding: const EdgeInsets.all(MishkatSpacing.base),
      borderColor: color.withValues(alpha: .35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSuccess
                    ? Icons.check_circle_rounded
                    : Icons.downloading_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSuccess ? 'اكتمل حفظ ${state.label}' : 'حفظ ${state.label}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (state.isRunning)
                TextButton(
                  onPressed: controller.cancel,
                  child: const Text('إلغاء'),
                ),
            ],
          ),
          if (state.total > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: state.progress.clamp(0, 1)),
            const SizedBox(height: 5),
            Text(
              '${state.completed} من ${state.total} آية',
              style: TextStyle(
                fontSize: 12,
                color: context.mishkat.textSecondary,
              ),
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 6),
            Text(state.error!, style: TextStyle(fontSize: 12, color: color)),
          ],
        ],
      ),
    );
  }
}
