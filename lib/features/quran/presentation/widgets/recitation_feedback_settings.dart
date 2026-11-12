import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../settings/data/models/app_settings.dart';

/// Quiet, full-width options remain readable with enlarged Arabic text.
class RecitationFeedbackSettings extends StatelessWidget {
  const RecitationFeedbackSettings({
    super.key,
    required this.mode,
    required this.onChanged,
    required this.canPreview,
    required this.onPreview,
  });

  final RecitationFeedbackMode mode;
  final ValueChanged<RecitationFeedbackMode> onChanged;
  final bool canPreview;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'تنبيهات التسميع',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'تنبيه عند الخطأ المؤكد وإشارة عند تصحيحه.',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Column(
              children: [
                for (final option in RecitationFeedbackMode.values) ...[
                  if (option != RecitationFeedbackMode.values.first)
                    Divider(height: 1, color: colors.border),
                  _FeedbackOption(
                    mode: option,
                    selected: mode == option,
                    onTap: () => onChanged(option),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('recitation-feedback-preview'),
            onPressed: canPreview && mode != RecitationFeedbackMode.silent
                ? onPreview
                : null,
            icon: Icon(
              mode == RecitationFeedbackMode.vibration
                  ? Icons.vibration_rounded
                  : Icons.volume_up_outlined,
              size: 19,
            ),
            label: const Text('تجربة التنبيه'),
            style: TextButton.styleFrom(
              foregroundColor: colors.primaryStrong,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        if (!canPreview)
          Text(
            'أوقف التسميع مؤقتًا لتجربة التنبيه.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
          const SizedBox(height: 4),
          Text(
            'لسماع التنبيهات، ارفع صوت الوسائط وأوقف وضع الصامت أو الاهتزاز و«عدم الإزعاج» في الهاتف.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
          const SizedBox(height: 4),
          Text(
            'على iPhone، تتبع التنبيهات أثناء التسميع مستوى صوت الوسائط حتى مع تفعيل مفتاح الصامت. لإيقاف صوتها اختر «اهتزاز» أو «صامت».',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ],
    );
  }
}

class _FeedbackOption extends StatelessWidget {
  const _FeedbackOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final RecitationFeedbackMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final (label, icon) = switch (mode) {
      RecitationFeedbackMode.sound => ('صوت هادئ', Icons.volume_up_outlined),
      RecitationFeedbackMode.vibration => ('اهتزاز', Icons.vibration_rounded),
      RecitationFeedbackMode.silent => ('صامت', Icons.volume_off_outlined),
    };
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? colors.surfaceVariant : colors.surface,
        child: InkWell(
          key: ValueKey('recitation-feedback-${mode.name}'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(icon, size: 20, color: colors.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ExcludeSemantics(
                    child: Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 20,
                      color: selected
                          ? colors.primaryStrong
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
