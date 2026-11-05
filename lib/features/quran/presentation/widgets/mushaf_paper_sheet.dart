import 'package:flutter/material.dart';

/// An edge-to-edge Mushaf canvas with a quiet folio at the screen bottom.
class MushafPaperSheet extends StatelessWidget {
  const MushafPaperSheet({
    super.key,
    required this.page,
    required this.child,
    required this.onExit,
  });

  final int page;
  final Widget child;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = dark ? const Color(0xFF121C17) : const Color(0xFFF6F1E8);
    final ornament = dark ? const Color(0xFF9B906E) : const Color(0xFF8A7651);
    final ink = dark ? const Color(0xFFECE5D8) : const Color(0xFF56492F);
    final number = page
        .toString()
        .split('')
        .map((digit) => String.fromCharCode(0x0660 + int.parse(digit)))
        .join();

    return SizedBox.expand(
      key: ValueKey('mushaf-paper-$page'),
      child: ColoredBox(
        color: paper,
        child: CustomPaint(
          foregroundPainter: _PaperFramePainter(ornament),
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Column(
              children: [
                Expanded(
                  child: SizedBox.expand(
                    key: ValueKey('mushaf-paper-body-$page'),
                    child: child,
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Semantics(
                            label: 'صفحة $page',
                            excludeSemantics: true,
                            child: Text(
                              number,
                              key: ValueKey('mushaf-page-number-$page'),
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                height: 1.2,
                                color: ink.withValues(alpha: .65),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: 'إنهاء ملء الشاشة',
                          onPressed: onExit,
                          color: ornament.withValues(alpha: .75),
                          iconSize: 18,
                          icon: const Icon(Icons.fullscreen_exit_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperFramePainter extends CustomPainter {
  const _PaperFramePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds.deflate(3), line);
    canvas.drawRect(bounds.deflate(7), line..strokeWidth = .5);

    // Small geometric corner pieces echo a printed Mushaf without competing
    // with the original surah ornaments in the SVG artwork.
    for (final corner in [
      const Offset(7, 7),
      Offset(size.width - 7, 7),
      Offset(7, size.height - 7),
      Offset(size.width - 7, size.height - 7),
    ]) {
      final diamond = Path()
        ..moveTo(corner.dx, corner.dy - 3)
        ..lineTo(corner.dx + 3, corner.dy)
        ..lineTo(corner.dx, corner.dy + 3)
        ..lineTo(corner.dx - 3, corner.dy)
        ..close();
      canvas.drawPath(diamond, line..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_PaperFramePainter oldDelegate) =>
      color != oldDelegate.color;
}
