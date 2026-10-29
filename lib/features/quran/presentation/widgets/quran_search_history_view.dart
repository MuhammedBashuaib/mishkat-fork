import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';

/// Widget presenting recent search history and popular Quranic discovery suggestions.
class QuranSearchHistoryView extends StatelessWidget {
  const QuranSearchHistoryView({
    super.key,
    required this.recentSearches,
    required this.onSelectQuery,
    required this.onRemoveRecent,
    required this.onClearAll,
  });

  final List<String> recentSearches;
  final ValueChanged<String> onSelectQuery;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearAll;

  static const _suggestions = <({String label, String query})>[
    (label: 'آية الكرسي (2:255)', query: '2:255'),
    (label: 'سورة الكهف', query: 'الكهف'),
    (label: 'سورة يس', query: 'يس'),
    (label: 'سورة الملك', query: 'الملك'),
    (label: 'آخر البقرة (2:285)', query: '2:285'),
    (label: 'صفحة 604', query: 'ص 604'),
    (label: 'الحمد لله رب العالمين', query: 'الحمد لله'),
    (label: 'الله نور السماوات', query: 'الله نور السماوات'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: MishkatSpacing.page,
      children: [
        if (recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'عمليات البحث الأخيرة',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.mishkat.textSecondary,
                ),
              ),
              TextButton(
                onPressed: onClearAll,
                child: const Text('مسح الكل', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.xs),
          Wrap(
            spacing: MishkatSpacing.xs,
            runSpacing: MishkatSpacing.xs,
            children: [
              for (final query in recentSearches)
                InputChip(
                  label: Text(query),
                  avatar: const Icon(Icons.history_rounded, size: 16),
                  onPressed: () => onSelectQuery(query),
                  onDeleted: () => onRemoveRecent(query),
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                ),
            ],
          ),
          const SizedBox(height: MishkatSpacing.lg),
        ],

        // Suggestions
        Text(
          'اقتراحات وتنقّل سريع',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: context.mishkat.textSecondary,
          ),
        ),
        const SizedBox(height: MishkatSpacing.sm),
        for (final item in _suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: MishkatSpacing.xs),
            child: MishkatCard(
              padding: const EdgeInsets.symmetric(
                horizontal: MishkatSpacing.md,
                vertical: MishkatSpacing.sm,
              ),
              onTap: () => onSelectQuery(item.query),
              child: Row(
                children: [
                  Icon(
                    Icons.trending_up_rounded,
                    size: 18,
                    color: context.mishkat.primary,
                  ),
                  const SizedBox(width: MishkatSpacing.md),
                  Expanded(
                    child: Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    item.query,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.mishkat.textSecondary,
                    ),
                  ),
                  const SizedBox(width: MishkatSpacing.xs),
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: context.mishkat.textMuted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
