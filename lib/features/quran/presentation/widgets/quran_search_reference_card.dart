import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/quran_search_models.dart';

/// Interactive high-priority direct navigation card displayed when the user enters
/// a recognized Quranic address (e.g. "2:255", "البقرة 255", "صفحة 255").
class QuranSearchReferenceCard extends StatelessWidget {
  const QuranSearchReferenceCard({
    super.key,
    required this.reference,
    required this.onTap,
  });

  final QuranParsedReference reference;
  final VoidCallback onTap;

  IconData _getIcon() {
    switch (reference.type) {
      case QuranReferenceType.surah:
        return Icons.auto_stories_rounded;
      case QuranReferenceType.ayah:
        return Icons.pin_drop_rounded;
      case QuranReferenceType.page:
        return Icons.menu_book_rounded;
      case QuranReferenceType.globalAyah:
        return Icons.format_list_numbered_rounded;
    }
  }

  String _getBadgeLabel() {
    switch (reference.type) {
      case QuranReferenceType.surah:
        return 'سورة';
      case QuranReferenceType.ayah:
        return 'انتقال مباشر لآية';
      case QuranReferenceType.page:
        return 'انتقال لصفحة';
      case QuranReferenceType.globalAyah:
        return 'رقم شامل';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MishkatCard(
      color: context.mishkat.primarySoft,
      borderColor: context.mishkat.primary.withValues(alpha: 0.35),
      onTap: onTap,
      padding: const EdgeInsets.all(MishkatSpacing.base),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.mishkat.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(_getIcon(), color: Colors.white, size: 22),
          ),
          const SizedBox(width: MishkatSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: MishkatSpacing.xs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.mishkat.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(MishkatRadius.xs),
                      ),
                      child: Text(
                        _getBadgeLabel(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.mishkat.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: MishkatSpacing.xs),
                    Text(
                      'صفحة ${reference.page}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.mishkat.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  reference.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.mishkat.primary,
                  ),
                ),
                Text(
                  reference.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.mishkat.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: context.mishkat.primary,
          ),
        ],
      ),
    );
  }
}
