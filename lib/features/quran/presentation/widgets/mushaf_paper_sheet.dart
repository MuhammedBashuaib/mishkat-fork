import 'package:flutter/material.dart';

/// An edge-to-edge Mushaf canvas with a quiet folio at the screen bottom.
class MushafPaperSheet extends StatelessWidget {
  const MushafPaperSheet({
    super.key,
    required this.page,
    required this.surahName,
    required this.juz,
    required this.child,
    required this.onExit,
  });

  final int page;
  final String surahName;
  final int juz;
  final Widget child;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = dark ? const Color(0xFF121C17) : const Color(0xFFF6F1E8);
    final ornament = dark ? const Color(0xFF9B906E) : const Color(0xFF8A7651);
    final ink = dark ? const Color(0xFFECE5D8) : const Color(0xFF56492F);
    final number = _arabic(page);

    return SizedBox.expand(
      key: ValueKey('mushaf-paper-$page'),
      child: ColoredBox(
        color: paper,
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Column(
            children: [
              SizedBox(
                height: 26,
                child: Row(
                  textDirection: TextDirection.ltr,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'سورة $surahName',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: ornament,
                      ),
                    ),
                    Text(
                      'الجزء ${_arabic(juz)}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: ornament,
                      ),
                    ),
                  ],
                ),
              ),
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
    );
  }

  static String _arabic(int value) => value
      .toString()
      .split('')
      .map((digit) => String.fromCharCode(0x0660 + int.parse(digit)))
      .join();
}
