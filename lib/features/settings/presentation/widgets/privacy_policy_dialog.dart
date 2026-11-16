import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../pages/privacy_policy_page.dart';

class PrivacyPolicyDialog extends StatelessWidget {
  const PrivacyPolicyDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const PrivacyPolicyDialog(),
  );

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
              padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      namesRoute: true,
                      header: true,
                      child: Text('سياسة الخصوصية', style: text.titleMedium),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.borderSubtle),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('privacy-policy-scroll'),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.primarySoft,
                          borderRadius: MishkatRadius.brMd,
                        ),
                        child: Icon(
                          Icons.verified_user_outlined,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const PrivacyPolicyContent(),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('تم'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
