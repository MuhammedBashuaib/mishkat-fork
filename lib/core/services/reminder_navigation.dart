import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/home/presentation/pages/charity_reminder_page.dart';
import '../../features/khatma/data/models/khatma_plan.dart';
import '../../features/khatma/presentation/cubit/khatma_cubit.dart';
import '../../features/quran/presentation/cubit/quran_cubit.dart';
import '../../features/quran/presentation/pages/quran_reader_page.dart';
import '../../features/tasbih/presentation/cubit/tasbih_cubit.dart';
import '../../features/tasbih/presentation/pages/tasbih_page.dart';

/// Shares the actual tap behavior with navigation regression tests.
class ReminderNavigation {
  const ReminderNavigation._();

  static Future<void> open(BuildContext context, String payload) async {
    final destination = payload.split(':').first;
    final navigator = Navigator.of(context);
    switch (destination) {
      case 'charity':
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const CharityReminderPage()),
        );
        break;
      case 'tasbih':
        final parts = payload.split(':');
        if (parts.length > 1) {
          await context.read<TasbihCubit>().selectDhikr(parts[1]);
        }
        if (!context.mounted) return;
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const TasbihPage()),
        );
        break;
      case 'khatma':
      case 'wird':
        if (destination == 'khatma') {
          final parts = payload.split(':');
          if (parts.length > 1) {
            await context.read<KhatmaCubit>().setActive(parts[1]);
            if (!context.mounted) return;
          }
        }
        final plan = context.read<KhatmaCubit>().state.active;
        if (plan != null && plan.status == KhatmaStatus.active) {
          final page = plan.resumePage.clamp(plan.nextPage, plan.todayEnd);
          await context.read<QuranCubit>().openPage(page);
          if (!context.mounted) return;
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => QuranReaderPage(
                khatmaPlanId: plan.id,
                khatmaPlanName: plan.name,
                khatmaStartPage: page,
                khatmaTargetPage: plan.todayEnd,
              ),
            ),
          );
        } else {
          final lastRead = context.read<QuranCubit>().state.lastRead;
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  QuranReaderPage(initialGlobalAyah: lastRead?.global),
            ),
          );
        }
        break;
    }
  }
}
