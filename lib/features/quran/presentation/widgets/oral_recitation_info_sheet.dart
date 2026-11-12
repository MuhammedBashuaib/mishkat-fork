import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/repositories/quran_repository.dart';
import '../pages/quran_oral_recitation_page.dart';
import '../pages/quran_reader_page.dart';
import '../services/speech_recognition_service.dart';

/// A short introduction before entering the selected recitation range.
class OralRecitationInfoSheet extends StatelessWidget {
  const OralRecitationInfoSheet({
    super.key,
    this.surahNumber = 1,
    this.startGlobalAyah,
    this.endGlobalAyah,
    this.startPage,
    this.endPage,
    this.planId,
  });

  final int surahNumber;
  final int? startGlobalAyah;
  final int? endGlobalAyah;
  final int? startPage;
  final int? endPage;
  final String? planId;

  static Future<void> show(
    BuildContext context, {
    int surahNumber = 1,
    int? startGlobalAyah,
    int? endGlobalAyah,
    int? startPage,
    int? endPage,
    String? planId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MishkatRadius.xl),
        ),
      ),
      builder: (_) => OralRecitationInfoSheet(
        surahNumber: surahNumber,
        startGlobalAyah: startGlobalAyah,
        endGlobalAyah: endGlobalAyah,
        startPage: startPage,
        endPage: endPage,
        planId: planId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MishkatSpacing.lg,
          MishkatSpacing.md,
          MishkatSpacing.lg,
          MishkatSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: MishkatSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colors.primarySoft,
                      borderRadius: BorderRadius.circular(MishkatRadius.md),
                    ),
                    child: Icon(
                      Icons.record_voice_over_rounded,
                      color: colors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: MishkatSpacing.base),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'التسميع الشفهي الذكي',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ثبّت حفظك مع متابعة التلاوة كلمةً كلمة.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MishkatSpacing.base),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: MishkatRadius.brMd,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      color: colors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'سمّع على صفحات المصحف بسطورها الثابتة، مع خطوط خافتة مكان الكلمات المخفية وأرقام الآيات في مواضعها. تظهر الكلمات مع تلاوتك، ويمكنك طلب تلميح أو كشف الآية مؤقتاً بالضغط المطوّل.',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12.5,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'يُعالج الصوت على جهازك أثناء الجلسة، ولا يُرفع أو يُحفظ تسجيلك.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Icon(
                    Icons.offline_pin_outlined,
                    size: 15,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'نموذج التسميع مضمّن في نسختي Android وiPhone: يعمل دون إنترنت ودون تنزيل حزمة صوتية من إعدادات الجهاز.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'عند عدم وضوح الصوت نطلب إعادة الموضع. المتابعة تساعدك على الحفظ، ولا تُقيّم أحكام التجويد.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: MishkatSpacing.base),
              MishkatPrimaryAction(
                onPressed: () {
                  final navigator = Navigator.of(context);
                  final quranRepo = context.read<QuranRepository>();
                  SpeechRecognitionService? speechService;
                  try {
                    speechService = context.read<SpeechRecognitionService>();
                  } catch (_) {}
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => QuranOralRecitationPage(
                        surahNumber: surahNumber,
                        startGlobalAyah: startGlobalAyah,
                        endGlobalAyah: endGlobalAyah,
                        startPage: startPage,
                        endPage: endPage,
                        planId: planId,
                        quranRepository: quranRepo,
                        speechService: speechService,
                      ),
                    ),
                  );
                },
                label: 'بدء التسميع الشفهي الآن',
                icon: const Icon(Icons.mic_rounded),
                isFullWidth: true,
              ),
              const SizedBox(height: 8),
              MishkatSecondaryAction(
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const QuranReaderPage(startRangeSelection: true),
                    ),
                  );
                },
                label: 'التسميع والاستحضار البصري في المصحف',
                icon: const Icon(Icons.visibility_off_rounded),
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
