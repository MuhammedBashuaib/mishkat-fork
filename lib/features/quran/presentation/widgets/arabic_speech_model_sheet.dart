import 'dart:async';

import 'package:flutter/material.dart';

import '../services/arabic_speech_model_service.dart';

class ArabicSpeechModelSheet extends StatefulWidget {
  const ArabicSpeechModelSheet({
    super.key,
    required this.service,
    required this.openSettings,
  });

  final ArabicSpeechModelService service;
  final Future<void> Function() openSettings;

  @override
  State<ArabicSpeechModelSheet> createState() => _ArabicSpeechModelSheetState();
}

class _ArabicSpeechModelSheetState extends State<ArabicSpeechModelSheet>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.service.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.service.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _description(ArabicSpeechModelStatus status) {
    if (status.reason == 'iosManagedBySystem') {
      return 'خدمة الصوت الحالية في iOS لا تتيح تنزيل حزمة العربية من داخل التطبيق. التسميع دون إنترنت متاح فقط عندما يوفّر النظام التعرف المحلي بالعربية على جهازك.';
    }
    if (status.reason == 'requiresAndroid13') {
      return 'التنزيل المباشر يحتاج أندرويد 13 أو أحدث وخدمة صوت تدعم العربية محليًا. يمكنك التحقق من حزم اللغات في إعدادات الإدخال الصوتي على جهازك.';
    }
    if (status.reason == 'downloadFailed') {
      return 'تعذّر تنزيل الحزمة. تحقق من الاتصال والمساحة المتاحة، ثم أعد الفحص أو افتح إعدادات خدمة الصوت.';
    }
    return switch (status.availability) {
      ArabicSpeechModelAvailability.installed =>
        'حزمة العربية جاهزة. سيستخدمها التسميع تلقائيًا للتعرف على تلاوتك دون إنترنت.',
      ArabicSpeechModelAvailability.downloadable =>
        'يمكن تنزيل حزمة العربية من هنا. تحتاج اتصالًا أثناء التنزيل فقط؛ بعد اكتماله سيستخدمها التسميع تلقائيًا دون إنترنت.',
      ArabicSpeechModelAvailability.pending =>
        'طلب تنزيل العربية قيد التنفيذ لدى خدمة الصوت. أبقِ الاتصال متاحًا؛ قد يؤجّل النظام التنزيل حتى يتوفر اتصال مناسب. ستظهر الجاهزية بعد التحقق من تثبيت الحزمة.',
      ArabicSpeechModelAvailability.unsupported =>
        'خدمة الصوت على هذا الجهاز لا تتيح حزمة عربية للتنزيل المباشر. تحقق من حزم اللغات أو اختر خدمة صوت تدعم العربية من إعدادات الجهاز.',
      ArabicSpeechModelAvailability.unknown =>
        'تعذّر التحقق من حزمة العربية حاليًا. اسمح بالميكروفون وفعّل خدمة التعرف على الكلام، ثم أعد الفحص. لن تظهر الحزمة كجاهزة قبل التحقق منها.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final service = widget.service;
        final status = service.status;
        final checking = service.isChecking;
        final requesting = service.isRequestingDownload;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.offline_pin_outlined),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('حزمة العربية للتسميع',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  checking && status.availability == ArabicSpeechModelAvailability.unknown
                      ? 'جارٍ التحقق من حزمة العربية…'
                      : _description(status),
                  style: const TextStyle(height: 1.6),
                ),
                if (checking || requesting || status.isPending) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: status.isPending && status.progress != null
                        ? status.progress! / 100
                        : null,
                    semanticsLabel: 'تنزيل حزمة العربية',
                  ),
                  if (status.isPending && status.progress != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${status.progress}٪', textAlign: TextAlign.center),
                    ),
                ],
                const SizedBox(height: 20),
                if (status.canDownload)
                  FilledButton.icon(
                    onPressed: requesting || checking ? null : () => service.download(),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(requesting ? 'جارٍ طلب التنزيل…' : 'تحميل حزمة اللغة العربية'),
                  ),
                if (status.isInstalled || service.offlineOnly)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('التسميع دون إنترنت فقط'),
                    subtitle: const Text('إذا لم تتوفر الحزمة، يتوقف التسميع دون استخدام خدمة عبر الإنترنت.'),
                    value: service.offlineOnly,
                    onChanged: (value) => service.offlineOnly = value,
                  ),
                OutlinedButton.icon(
                  onPressed: checking || requesting ? null : () => service.refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة فحص الحزمة'),
                ),
                if (!status.isInstalled)
                  TextButton.icon(
                    onPressed: widget.openSettings,
                    icon: const Icon(Icons.settings_voice_rounded),
                    label: const Text('فتح إعدادات خدمة الصوت'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
