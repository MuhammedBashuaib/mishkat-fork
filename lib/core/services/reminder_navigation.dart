import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../utils/app_formatters.dart';
import '../../features/home/presentation/pages/charity_reminder_page.dart';
import '../../features/home/presentation/pages/friday_dua_reminder_page.dart';
import '../../features/khatma/data/models/khatma_plan.dart';
import '../../features/khatma/presentation/cubit/khatma_cubit.dart';
import '../../features/quran/presentation/cubit/quran_cubit.dart';
import '../../features/quran/presentation/cubit/quran_state.dart';
import '../../features/quran/presentation/pages/quran_reader_page.dart';
import '../../features/tasbih/presentation/cubit/tasbih_cubit.dart';
import '../../features/tasbih/presentation/pages/tasbih_page.dart';

/// Shares the actual tap behavior with navigation regression tests.
class ReminderNavigation {
  const ReminderNavigation._();

  static Future<void> open(
    BuildContext context,
    String payload, {
    bool Function()? canNavigate,
  }) async {
    // A reset can begin while a cold-start load or persistence operation is
    // pending. Check again before issuing another mutation or opening a route.
    bool canProceed() => context.mounted && (canNavigate?.call() ?? true);
    if (!canProceed()) return;
    final destination = payload.split(':').first;
    final navigator = Navigator.of(context);
    switch (destination) {
      case 'quran':
        if (payload != 'quran:kahf') return;
        final quran = context.read<QuranCubit>();
        if (quran.isClosed) return;
        if (quran.state.status == QuranStatus.loading) {
          // Cold-start taps share the load already started by the app. A
          // second load could restore an old reading position after routing.
          await quran.stream.firstWhere(
            (state) => state.status != QuranStatus.loading,
            orElse: () => quran.state,
          );
        } else if (quran.state.data == null) {
          await quran.load();
        }
        if (!context.mounted || !canProceed() || quran.isClosed) return;
        final data = quran.state.data;
        if (data == null) {
          context.showMessage('تعذّر فتح سورة الكهف الآن. حاول مجددًا.');
          return;
        }
        final firstAyah = data.globalFor(18, 1);
        await quran.openSurah(18);
        if (!context.mounted || !canProceed()) return;
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => QuranReaderPage(initialGlobalAyah: firstAyah),
          ),
        );
        break;
      case 'friday':
        if (payload != 'friday:dua') return;
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const FridayDuaReminderPage(),
          ),
        );
        break;
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
        if (!context.mounted || !canProceed()) return;
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
            if (!context.mounted || !canProceed()) return;
          }
        }
        final plan = context.read<KhatmaCubit>().state.active;
        if (plan != null && plan.status == KhatmaStatus.active) {
          final page = plan.resumePage.clamp(plan.nextPage, plan.todayEnd);
          await context.read<QuranCubit>().openPage(page);
          if (!context.mounted || !canProceed()) return;
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
