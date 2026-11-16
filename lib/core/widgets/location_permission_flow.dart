import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/settings/presentation/cubit/settings_cubit.dart';
import '../../features/settings/presentation/cubit/settings_state.dart';
import '../services/location_service.dart';

/// Keeps location permission and recovery at the feature that needs them.
class LocationPermissionFlow {
  static final _active = <SettingsCubit>{};

  static Future<bool> useCurrentLocation(BuildContext context) async {
    final settings = context.read<SettingsCubit>();
    if (settings.isClosed ||
        settings.state.status == SettingsStatus.locating ||
        !_active.add(settings)) {
      return false;
    }
    try {
      while (context.mounted && !settings.isClosed) {
        final failure = await settings.useCurrentLocation(reportFailure: false);
        if (!context.mounted || settings.isClosed) return false;
        if (failure == null) return settings.state.settings.hasLocation;
        final action = await showDialog<_LocationAction>(
          context: context,
          builder: (_) => _LocationRecoveryDialog(failure: failure),
        );
        if (!context.mounted || settings.isClosed) return false;
        if (action == _LocationAction.city) {
          final city = await showDialog<NearbyCity>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('اختر مدينتك'),
              content: SizedBox(
                width: 320,
                height: 340,
                child: ListView.builder(
                  itemCount: LocationService.cities.length,
                  itemBuilder: (_, index) {
                    final city = LocationService.cities[index];
                    return ListTile(
                      title: Text(city.name),
                      onTap: () => Navigator.pop(dialogContext, city),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          );
          if (city == null || !context.mounted || settings.isClosed) {
            return false;
          }
          await settings.selectCity(city);
          return true;
        }
        if (action != _LocationAction.retry) return false;
      }
      return false;
    } finally {
      _active.remove(settings);
    }
  }
}

enum _LocationAction { retry, city }

class _LocationRecoveryDialog extends StatefulWidget {
  const _LocationRecoveryDialog({required this.failure});

  final LocationFailure failure;

  @override
  State<_LocationRecoveryDialog> createState() =>
      _LocationRecoveryDialogState();
}

class _LocationRecoveryDialogState extends State<_LocationRecoveryDialog> {
  bool _openingSettings = false;
  String? _settingsMessage;

  bool get _needsSettings =>
      widget.failure.reason == LocationFailureReason.serviceDisabled ||
      widget.failure.reason == LocationFailureReason.permanentlyDenied;

  Future<void> _openSettings() async {
    setState(() => _openingSettings = true);
    var opened = false;
    try {
      opened = widget.failure.reason == LocationFailureReason.serviceDisabled
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
    } on Object {
      // The platform may not provide a settings destination (for example web).
    }
    if (!mounted) return;
    setState(() {
      _openingSettings = false;
      _settingsMessage = opened
          ? 'بعد السماح بالموقع، عد إلى مشكاة واضغط «إعادة المحاولة».'
          : 'تعذّر فتح إعدادات الجهاز. يمكنك اختيار مدينتك هنا أو السماح بالموقع من إعدادات الجهاز.';
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.location_on_outlined),
    title: const Text('الموقع للصلاة والقبلة'),
    scrollable: true,
    content: Text(_settingsMessage ?? widget.failure.message),
    actions: [
      TextButton(
        onPressed: _openingSettings ? null : () => Navigator.pop(context),
        child: const Text('لاحقًا'),
      ),
      TextButton(
        onPressed: _openingSettings
            ? null
            : () => Navigator.pop(context, _LocationAction.city),
        child: const Text('اختيار مدينة'),
      ),
      if (_needsSettings && !kIsWeb)
        OutlinedButton(
          onPressed: _openingSettings ? null : _openSettings,
          child: const Text('فتح إعدادات الجهاز'),
        ),
      FilledButton(
        onPressed: _openingSettings
            ? null
            : () => Navigator.pop(context, _LocationAction.retry),
        child: const Text('إعادة المحاولة'),
      ),
    ],
  );
}
