import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/navigation_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/quran_models.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_state.dart';
import 'quran_audio_player_page.dart';
import 'quran_index_page.dart';
import 'quran_memorization_page.dart';
import 'quran_reader_page.dart';
import 'quran_search_page.dart';

/// Calm entry point for the Quran area.
///
/// The hub deliberately exposes only the two universal shortcuts (search and
/// the latest bookmark) and the three main destinations. Browsing and feature
/// controls live in the destination pages where they have enough context.
class QuranPage extends StatelessWidget {
  const QuranPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuranCubit, QuranState>(
      builder: (context, state) {
        if (state.status == QuranStatus.loading ||
            state.status == QuranStatus.initial) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == QuranStatus.failure || state.data == null) {
          return ContentStatePanel(
            icon: Icons.menu_book_outlined,
            title: 'تعذّر فتح المصحف',
            message: state.error ?? 'حدث خطأ أثناء تحميل بيانات القرآن.',
            action: MishkatPrimaryButton(
              onPressed: context.read<QuranCubit>().load,
              label: 'إعادة المحاولة',
            ),
          );
        }
        return _QuranHub(state: state);
      },
    );
  }
}

class _QuranHub extends StatelessWidget {
  const _QuranHub({required this.state});

  final QuranState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      key: const PageStorageKey('quran-hub-landing'),
      padding: const EdgeInsets.fromLTRB(
        MishkatSpacing.base,
        MishkatSpacing.sm,
        MishkatSpacing.base,
        112,
      ),
      children: [
        Text(
          'القرآن الكريم',
          style: textTheme.headlineMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'مصحف المدينة · حفص عن عاصم',
          style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: MishkatSpacing.lg),
        _SearchEntry(
          onTap: () => Navigator.push(context, QuranSearchPage.route()),
        ),
        const SizedBox(height: MishkatSpacing.md),
        _LatestBookmarkEntry(
          state: state,
          onTap: () => _openLatestBookmark(context),
        ),
        const SizedBox(height: MishkatSpacing.xl),
        Text(
          'اختر وجهتك',
          style: textTheme.labelLarge?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: MishkatSpacing.md),
        _DestinationCard(
          title: 'المصحف الشريف',
          subtitle: 'اقرأ وتدبّر، وتابع من موضعك',
          actionLabel: 'فتح المصحف',
          icon: Icons.menu_book_rounded,
          emphasis: true,
          onTap: () => Navigator.push(
            context,
            QuranIndexPage.route(initialMode: QuranIndexMode.surahs),
          ),
        ),
        const SizedBox(height: MishkatSpacing.md),
        _DestinationCard(
          title: 'المشغّل القرآني',
          subtitle: 'استمع إلى التلاوات والإذاعات',
          actionLabel: 'فتح المشغّل القرآني',
          icon: Icons.headphones_rounded,
          onTap: () => Navigator.push(context, QuranAudioPlayerPage.route()),
        ),
        const SizedBox(height: MishkatSpacing.md),
        _DestinationCard(
          title: 'التحفيظ والمراجعة',
          subtitle: 'خطّط لحفظك، سمّع، وراجع تقدّمك',
          actionLabel: 'لوحة التحفيظ',
          icon: Icons.school_rounded,
          onTap: () => Navigator.push(context, QuranMemorizationPage.route()),
        ),
      ],
    );
  }

  Future<void> _openLatestBookmark(BuildContext context) async {
    final bookmarks = state.bookmarks;
    if (bookmarks.isEmpty) {
      await Navigator.push(
        context,
        QuranIndexPage.route(initialMode: QuranIndexMode.bookmarks),
      );
      return;
    }

    final latest = bookmarks.reduce(
      (current, next) =>
          current.createdAt.isAfter(next.createdAt) ? current : next,
    );
    await context.read<QuranCubit>().openPage(latest.page, point: latest.point);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QuranReaderPage(initialGlobalAyah: latest.point.global),
      ),
    );
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;

    return Semantics(
      button: true,
      label: 'البحث في القرآن',
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: MishkatRadius.brMd,
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MishkatSpacing.base,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 22,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: MishkatSpacing.md),
                  Expanded(
                    child: Text(
                      'ابحث عن سورة أو آية',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.textSecondary),
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

class _LatestBookmarkEntry extends StatelessWidget {
  const _LatestBookmarkEntry({required this.state, required this.onTap});

  final QuranState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final latest = _latestBookmark(state.bookmarks);
    final chapter = latest == null
        ? null
        : state.data?.chapter(latest.point.surah);
    final detail = latest == null
        ? 'لم تضف علامة بعد'
        : 'سورة ${chapter?.name ?? ''} · صفحة ${latest.page} · آية ${latest.point.ayah}';

    return Tooltip(
      message: 'آخر علامة مرجعية',
      child: Material(
        color: colors.primarySoft.withValues(alpha: 0.58),
        borderRadius: MishkatRadius.brMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MishkatSpacing.base,
              vertical: MishkatSpacing.md,
            ),
            child: Row(
              children: [
                Icon(
                  latest == null
                      ? Icons.bookmark_border_rounded
                      : Icons.bookmark_rounded,
                  color: colors.primary,
                  size: 23,
                ),
                const SizedBox(width: MishkatSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'آخر علامة',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MishkatSpacing.sm),
                Icon(
                  MishkatNavigationIcons.forward,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  QuranBookmark? _latestBookmark(List<QuranBookmark> bookmarks) {
    if (bookmarks.isEmpty) return null;
    return bookmarks.reduce(
      (current, next) =>
          current.createdAt.isAfter(next.createdAt) ? current : next,
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.icon,
    required this.onTap,
    this.emphasis = false,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onTap;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final textTheme = Theme.of(context).textTheme;
    final background = emphasis
        ? colors.primarySoft.withValues(alpha: 0.5)
        : colors.surface;

    return Semantics(
      button: true,
      label: actionLabel,
      child: MishkatCard(
        onTap: onTap,
        color: background,
        borderColor: emphasis
            ? colors.primary.withValues(alpha: 0.18)
            : colors.borderSubtle,
        padding: const EdgeInsets.all(MishkatSpacing.base),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: emphasis ? colors.primary : colors.primarySoft,
                borderRadius: MishkatRadius.brMd,
              ),
              child: Icon(
                icon,
                color: emphasis ? Colors.white : colors.primary,
                size: 25,
              ),
            ),
            const SizedBox(width: MishkatSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: MishkatSpacing.sm),
                  Text(
                    actionLabel,
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: MishkatSpacing.sm),
            Icon(
              MishkatNavigationIcons.forward,
              color: colors.primary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
