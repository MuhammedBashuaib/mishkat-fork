import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Confirms Android back navigation from the app's root route.
class AppExitConfirmation extends StatefulWidget {
  const AppExitConfirmation({super.key, required this.child});

  final Widget child;

  @override
  State<AppExitConfirmation> createState() => _AppExitConfirmationState();
}

class _AppExitConfirmationState extends State<AppExitConfirmation> {
  bool _confirmationPending = false;

  Future<void> _confirmExit() async {
    if (_confirmationPending || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    _confirmationPending = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.exit_to_app_rounded),
          title: const Text('الخروج من التطبيق'),
          content: const Text('هل أنت متأكد من الخروج من تطبيق مشكاة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('موافق، خروج'),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        await SystemNavigator.pop();
      }
    } finally {
      _confirmationPending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmExit =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return PopScope<Object?>(
      canPop: !confirmExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && confirmExit) _confirmExit();
      },
      child: widget.child,
    );
  }
}
