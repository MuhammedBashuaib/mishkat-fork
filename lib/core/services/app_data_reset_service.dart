import 'package:flutter/foundation.dart';

import '../../features/adhkar/presentation/cubit/adhkar_cubit.dart';
import '../../features/khatma/presentation/cubit/khatma_cubit.dart';
import '../../features/library/presentation/cubit/library_cubit.dart';
import '../../features/quran/presentation/cubit/quran_cubit.dart';
import '../../features/quran/presentation/cubit/quran_memorization_cubit.dart';
import '../../features/settings/presentation/cubit/settings_cubit.dart';
import '../../features/shell/presentation/cubit/shell_cubit.dart';
import '../../features/tasbih/presentation/cubit/tasbih_cubit.dart';
import 'home_widget_service.dart';
import 'local_notification_service.dart';
import 'offline_audio_download_controller.dart';

/// Coordinates the single user-requested reset across disk, live state and
/// native widgets. The UI must block interaction until the future completes.
class AppDataResetService extends ChangeNotifier {
  AppDataResetService({
    required this.settings,
    required this.quran,
    required this.memorization,
    required this.adhkar,
    required this.tasbih,
    required this.khatma,
    required this.library,
    required this.shell,
    required this.downloads,
    required this.widgets,
  });

  final SettingsCubit settings;
  final QuranCubit quran;
  final QuranMemorizationCubit memorization;
  final AdhkarCubit adhkar;
  final TasbihCubit tasbih;
  final KhatmaCubit khatma;
  final LibraryCubit library;
  final ShellCubit shell;
  final OfflineAudioDownloadController downloads;
  final HomeWidgetService widgets;
  Future<void>? _pending;
  int _generation = 0;

  bool get isResetting => _pending != null;
  int get generation => _generation;

  Future<void> clearAllData() {
    final pending = _pending;
    if (pending != null) return pending;
    final operation = _clear();
    _pending = operation;
    return operation.whenComplete(() => _pending = null);
  }

  Future<void> _clear() async {
    // Invalidate delayed reads, permission prompts and native callbacks before
    // yielding. They must not write old data while storage.clear is in flight.
    settings.invalidatePendingOperations();
    quran.invalidatePendingOperations();
    memorization.invalidatePendingOperations();
    adhkar.invalidatePendingOperations();
    library.invalidatePendingOperations();
    khatma.invalidatePendingOperations();
    // Stop producers before removing their output. In particular, the legacy
    // memorization-history write must finish before the shared store is erased.
    try {
      await quran.stopAudio();
      await downloads.clearAllDownloads();
      await memorization.finishPendingWrites();
      await settings.clearAllData();
    } on Object {
      // A failed deletion must not strand a cancelled initial load or location
      // request in its loading state. Recover from the surviving durable data.
      khatma.load();
      await Future.wait([
        settings.load(),
        quran.load(),
        memorization.load(),
        adhkar.load(),
        library.load(),
      ]);
      rethrow;
    }

    final defaults = settings.state.settings;
    quran.resetLocalData(
      reciter: defaults.reciter,
      fontSize: defaults.quranFont,
    );
    memorization.resetLocalData();
    adhkar.resetLocalData();
    tasbih.resetLocalData();
    khatma.resetLocalData();
    library.resetLocalData();
    shell.select(0);
    notificationTapPayload.value = null;
    homeWidgetLaunchUri.value = null;

    // Keep bundled content available even if reset interrupted its first load.
    await Future.wait([quran.load(), adhkar.load(), library.load()]);
    await Future.wait([
      widgets.sync(defaults),
      widgets.syncWird(null),
      widgets.syncTasbih(tasbih.state),
    ]);
    ++_generation;
    notifyListeners();
  }
}
