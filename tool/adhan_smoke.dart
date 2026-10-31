// Device-only diagnostic entry point; never used by the production build.
// flutter run -t tool/adhan_smoke.dart
import 'package:flutter/material.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = LocalNotificationService();
  await service.initialize();
  runApp(MaterialApp(home: _Smoke(service)));
}

class _Smoke extends StatefulWidget {
  const _Smoke(this.service);
  final LocalNotificationService service;
  @override
  State<_Smoke> createState() => _SmokeState();
}

class _SmokeState extends State<_Smoke> {
  String status = 'Choose an offline adhan test, then leave the app.';
  Future<void> schedule(String name) async {
    if (!await widget.service.requestPermission()) return;
    final at = DateTime.now().add(const Duration(seconds: 20));
    await widget.service.scheduleAll([
      ScheduledAppNotification(
        id: 100001,
        title: 'اختبار الأذان',
        body: name,
        at: at,
        soundName: name,
        payload: 'prayer:fajr',
        kind: AppNotificationKind.adhan,
      ),
    ]);
    if (mounted) setState(() => status = '$name scheduled at $at');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Adhan device verification')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(status),
          for (final voice in ['adhan1', 'adhan2', 'adhan4']) ...[
            ElevatedButton(
              onPressed: () => schedule(voice),
              child: Text('$voice full in 20s'),
            ),
            ElevatedButton(
              onPressed: () => schedule('${voice}_short'),
              child: Text('$voice short in 20s'),
            ),
          ],
          ElevatedButton(
            onPressed: widget.service.stopTest,
            child: const Text('Stop playback'),
          ),
          ElevatedButton(
            onPressed: widget.service.cancelAll,
            child: const Text('Cancel alarms'),
          ),
        ],
      ),
    ),
  );
}
