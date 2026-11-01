import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/navigation_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../data/models/quran_audio_station.dart';
import '../../data/services/haramain_live_service.dart';

/// An in-app, distraction-free viewer for the official Haramain broadcasts.
class HaramainLivePage extends StatefulWidget {
  const HaramainLivePage({super.key, required this.station});

  final QuranAudioStation station;

  static Route<void> route(QuranAudioStation station) =>
      MaterialPageRoute<void>(
        builder: (_) => HaramainLivePage(station: station),
      );

  @override
  State<HaramainLivePage> createState() => _HaramainLivePageState();
}

class _HaramainLivePageState extends State<HaramainLivePage>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  int _loadingProgress = 0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF071612))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _loadingProgress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _hasError = false;
              _loadingProgress = 0;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loadingProgress = 100);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !mounted) return;
            setState(() => _hasError = true);
          },
          onNavigationRequest: (request) {
            final host = Uri.tryParse(request.url)?.host.toLowerCase() ?? '';
            final isYouTube =
                host == 'youtube.com' ||
                host.endsWith('.youtube.com') ||
                host == 'youtube-nocookie.com' ||
                host.endsWith('.youtube-nocookie.com');
            return isYouTube
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
    _loadBroadcast();
  }

  Future<void> _loadBroadcast() async {
    if (mounted) {
      setState(() {
        _hasError = false;
        _loadingProgress = 0;
      });
    }
    final videoId = await HaramainLiveService.resolveVideoId(widget.station);
    if (!mounted) return;

    if (videoId != null) {
      await _controller.loadHtmlString(
        _playerHtml(videoId),
        baseUrl: 'https://www.youtube-nocookie.com',
      );
      return;
    }

    final fallbackUrl = widget.station.watchUrl;
    if (fallbackUrl != null) {
      await _controller.loadRequest(Uri.parse(fallbackUrl));
    } else {
      setState(() => _hasError = true);
    }
  }

  String _playerHtml(String videoId) =>
      '''
<!doctype html>
<html dir="rtl">
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    html, body { margin: 0; width: 100%; height: 100%; background: #071612; overflow: hidden; }
    iframe { position: fixed; inset: 0; width: 100%; height: 100%; border: 0; }
  </style>
</head>
<body>
  <iframe
    id="haramain-player"
    src="https://www.youtube-nocookie.com/embed/$videoId?autoplay=1&playsinline=1&rel=0&modestbranding=1&enablejsapi=1"
    title="${widget.station.title}"
    allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
    referrerpolicy="strict-origin-when-cross-origin"
    allowfullscreen>
  </iframe>
</body>
</html>
''';

  Future<void> _pauseVideo() async {
    try {
      await _controller.runJavaScript('''
        document.getElementById('haramain-player')?.contentWindow?.postMessage(
          '{"event":"command","func":"pauseVideo","args":""}', '*'
        );
      ''');
    } on Object {
      // The controller may already be detached while the route is closing.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pauseVideo();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final isMakkah = widget.station.id == 'stream_haram_makkah';
    final accent = isMakkah ? colors.gold : const Color(0xFF65D6B4);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _pauseVideo();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF071612),
        appBar: AppBar(
          backgroundColor: const Color(0xFF071612),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'العودة',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(MishkatNavigationIcons.back),
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.station.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                widget.station.city ?? '',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'إعادة تحميل البث',
              onPressed: _loadBroadcast,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!_hasError) WebViewWidget(controller: _controller),
                    if (_loadingProgress < 100 && !_hasError)
                      ColoredBox(
                        color: const Color(0xFF071612),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: accent),
                              const SizedBox(height: 16),
                              const Text(
                                'جارٍ الاتصال بالبث المباشر…',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_hasError)
                      _BroadcastError(accent: accent, onRetry: _loadBroadcast),
                    PositionedDirectional(
                      top: 14,
                      start: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD94343),
                          borderRadius: BorderRadius.circular(
                            MishkatRadius.pill,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Colors.white, size: 7),
                            SizedBox(width: 5),
                            Text(
                              'مباشر',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B241D),
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: .08)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified_rounded, color: accent, size: 20),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.station.sourceLabel ?? 'المصدر الرسمي',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'يُعرض الفيديو داخل مشكاة دون مغادرة التطبيق',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BroadcastError extends StatelessWidget {
  const _BroadcastError({required this.accent, required this.onRetry});

  final Color accent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF071612),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, color: accent, size: 42),
            const SizedBox(height: 14),
            const Text(
              'تعذّر الاتصال بالبث',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'تحقق من اتصال الإنترنت ثم أعد المحاولة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: const Color(0xFF092B24),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    ),
  );
}
