import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';

class AboutMishkatDialog extends StatefulWidget {
  const AboutMishkatDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const AboutMishkatDialog(),
  );

  @override
  State<AboutMishkatDialog> createState() => _AboutMishkatDialogState();
}

class _AboutMishkatDialogState extends State<AboutMishkatDialog> {
  late Future<PackageInfo> _packageInfo;

  @override
  void initState() {
    super.initState();
    _packageInfo = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final text = Theme.of(context).textTheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: MishkatRadius.brXl),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text('عن مشكاة', style: text.titleMedium)),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: MishkatRadius.brLg,
                        child: Image.asset(
                          'assets/icons/icon-512.png',
                          width: 72,
                          height: 72,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'مِشكاة',
                      textAlign: TextAlign.center,
                      style: text.headlineMedium?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'من نور الآية جاء الاسم',
                      textAlign: TextAlign.center,
                      style: text.labelLarge?.copyWith(color: colors.primary),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colors.primarySoft,
                        borderRadius: MishkatRadius.brLg,
                      ),
                      child: Column(
                        children: [
                          Text(
                            '﴿ مَثَلُ نُورِهِ كَمِشْكَاةٍ فِيهَا مِصْبَاحٌ ﴾',
                            textAlign: TextAlign.center,
                            style: text.bodyLarge?.copyWith(
                              color: colors.primary,
                              fontSize: 20,
                              height: 1.9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'سورة النور، الآية ٣٥',
                            style: text.bodySmall?.copyWith(
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'من آية النور استُلهم اسم «مشكاة»؛ ليكون رفيقًا يقرّبك من القرآن والصلاة والذكر، ويجمع ما تحتاجه في يومك في مساحة هادئة وواضحة.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(height: 1.8),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (icon, label) in const [
                          (Icons.menu_book_rounded, 'القرآن'),
                          (Icons.mosque_outlined, 'الصلاة'),
                          (Icons.spa_outlined, 'الأذكار'),
                        ])
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceVariant,
                              borderRadius: MishkatRadius.brPill,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 16, color: colors.primary),
                                const SizedBox(width: 6),
                                Text(label, style: text.labelMedium),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'المصحف برواية حفص عن عاصم، والأذكار من حصن المسلم.\nالمصحف والأذكار متاحان دون إنترنت، ويمكن تنزيل التلاوات للاستماع إليها لاحقًا.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(height: 1.8),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('إصدار التطبيق', style: text.bodySmall),
                  const SizedBox(height: 4),
                  FutureBuilder<PackageInfo>(
                    future: _packageInfo,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return TextButton.icon(
                          onPressed: () => setState(
                            () => _packageInfo = PackageInfo.fromPlatform(),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('إعادة قراءة الإصدار'),
                        );
                      }
                      final info = snapshot.data;
                      if (info == null) {
                        return Text(
                          'جارٍ قراءة الإصدار…',
                          style: text.bodySmall,
                        );
                      }
                      final version = info.version;
                      final build = info.buildNumber;
                      final versionStyle = text.titleMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      );
                      // Keep the version before the build in the Arabic layout.
                      return Semantics(
                        key: const ValueKey('about-app-version'),
                        label:
                            'الإصدار $version${build.isEmpty ? '' : ' ($build)'}',
                        child: ExcludeSemantics(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              textDirection: TextDirection.ltr,
                              children: [
                                Text(
                                  version,
                                  textDirection: TextDirection.ltr,
                                  style: versionStyle,
                                ),
                                if (build.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '($build)',
                                    textDirection: TextDirection.ltr,
                                    style: versionStyle,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
