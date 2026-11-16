import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/local_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../cubit/settings_cubit.dart';

/// One permission journey shared by onboarding and reminder entry points.
class NotificationPermissionFlow {
  static const firstLaunchKey = 'notification_permission_intro_version';
  static final _pending = Expando<Future<bool>>();

  static Future<bool> enable(BuildContext context) => _show(context);

  /// Feature switches recheck revoked OS permission without showing a dialog
  /// to somebody whose reminders are already enabled and authorized.
  static Future<bool> ensureEnabled(BuildContext context) async {
    final cubit = context.read<SettingsCubit>();
    final pending = _pending[cubit];
    if (pending != null) return pending;
    if (cubit.state.settings.notificationsEnabled) {
      try {
        if (await cubit.areNotificationsAllowed()) return true;
      } on Object {
        // The explicit activation flow can retry a failed platform check.
      }
    }
    return context.mounted && !cubit.isClosed ? _show(context) : false;
  }

  static Future<void> testNotification(BuildContext context) async {
    final cubit = context.read<SettingsCubit>();
    if (await ensureEnabled(context) && context.mounted && !cubit.isClosed) {
      await cubit.testNotification(permissionAlreadyGranted: true);
    }
  }

  static Future<void> showOnFirstLaunch(
    BuildContext context,
    LocalStorageService storage,
  ) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    // Never turn an upgrade or a previously declined prompt into a new opt-in.
    if (storage.readInt(firstLaunchKey) > 0 ||
        storage.readInt('onboarding_version') > 0 ||
        storage.readMap('settings').isNotEmpty) {
      return;
    }
    try {
      // Persist before presenting: denial/dismissal must not nag on restart.
      await storage.writeInt(firstLaunchKey, 1);
    } on Object {
      // Storage failure must not prevent entering the app.
      return;
    }
    if (context.mounted) await _show(context, firstLaunch: true);
  }

  static Future<bool> _show(BuildContext context, {bool firstLaunch = false}) {
    final cubit = context.read<SettingsCubit>();
    final pending = _pending[cubit];
    if (pending != null) return pending;
    final operation =
        showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => _NotificationPermissionDialog(
                cubit: cubit,
                firstLaunch: firstLaunch,
              ),
            )
            .then((value) => value ?? false)
            .whenComplete(() => _pending[cubit] = null);
    _pending[cubit] = operation;
    return operation;
  }
}

class _NotificationPermissionDialog extends StatefulWidget {
  const _NotificationPermissionDialog({
    required this.cubit,
    required this.firstLaunch,
  });
  final SettingsCubit cubit;
  final bool firstLaunch;

  @override
  State<_NotificationPermissionDialog> createState() =>
      _NotificationPermissionDialogState();
}

class _NotificationPermissionDialogState
    extends State<_NotificationPermissionDialog>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _permissionDenied = false;
  bool _waitingForSettings = false;
  Future<bool>? _openingSettings;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.firstLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_activate());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForSettings) {
      _waitingForSettings = false;
      unawaited(_checkAfterSettings());
    }
  }

  Future<void> _checkAfterSettings() async {
    try {
      await _openingSettings;
      if (!mounted || widget.cubit.isClosed) return;
      // A return with permission still denied must not trigger another prompt.
      if (await widget.cubit.areNotificationsAllowed() && mounted) {
        await _activate();
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'تعذّر التحقق من الإذن. حاول مجددًا.');
      }
    }
  }

  Future<void> _activate() async {
    if (_busy || widget.cubit.isClosed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final enabled = await widget.cubit.setNotificationsEnabled(true);
    if (!mounted) return;
    if (enabled) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _permissionDenied = widget.cubit.state.notificationPermissionDenied;
      _error = _permissionDenied
          ? 'لم يُمنح الإذن. حاول مجددًا أو افتح أذونات الجهاز.'
          : widget.cubit.state.message ?? 'تعذّر تفعيل الإشعارات. حاول مجددًا.';
    });
  }

  Future<void> _openSettings() async {
    if (_busy) return;
    setState(() => _busy = true);
    _waitingForSettings = true;
    try {
      _openingSettings = widget.cubit.openNotificationSettings();
      if (!await _openingSettings! && mounted) {
        _waitingForSettings = false;
        setState(() => _error = 'تعذّر فتح أذونات الجهاز. حاول مجددًا.');
      }
    } on Object {
      _waitingForSettings = false;
      if (mounted) {
        setState(() => _error = 'تعذّر فتح أذونات الجهاز. حاول مجددًا.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        key: const ValueKey('notification-permission-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: MishkatRadius.brXl),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: 40,
                  color: colors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'تفعيل الإشعارات',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.firstLaunch
                      ? 'لتصلك تنبيهات الصلاة والأذكار وتذكيرات الخير.'
                      : 'اسمح بالإشعارات لتصلك تذكيراتك.',
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('notification-permission-enable'),
                  onPressed: _busy ? null : _activate,
                  child: Text(
                    _busy
                        ? 'جارٍ التفعيل…'
                        : _error != null
                        ? 'المحاولة مجددًا'
                        : 'تفعيل الإشعارات',
                  ),
                ),
                if (_permissionDenied)
                  OutlinedButton(
                    key: const ValueKey('notification-permission-settings'),
                    onPressed: _busy ? null : _openSettings,
                    child: const Text('فتح أذونات الجهاز'),
                  ),
                TextButton(
                  key: const ValueKey('notification-permission-later'),
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('ليس الآن'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
