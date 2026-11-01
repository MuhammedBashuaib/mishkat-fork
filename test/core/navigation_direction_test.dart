import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/core/theme/navigation_icons.dart';
import 'package:mishkat_app/core/widgets/mishkat_widgets.dart';

void main() {
  for (final dark in [false, true]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
        'Arabic navigation keeps < for opening and > for returning ($platform, dark: $dark)',
        (tester) async {
          final theme = (dark ? AppTheme.dark() : AppTheme.light()).copyWith(
            platform: platform,
          );
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: theme,
              home: Scaffold(
                body: Builder(
                  builder: (context) => MishkatShortcutTile(
                    icon: Icons.favorite_outline,
                    title: 'أدعيتي',
                    subtitle: 'أدعية كتبتها لنفسك',
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('أدعيتي')),
                          body: const Text('تفاصيل الأدعية'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final forward = tester.widget<Icon>(
            find.byIcon(MishkatNavigationIcons.forward),
          );
          expect(
            Directionality.of(tester.element(find.byType(MishkatShortcutTile))),
            TextDirection.rtl,
          );
          expect(forward.icon, Icons.keyboard_arrow_left_rounded);
          expect(forward.icon!.matchTextDirection, isFalse);

          await tester.tap(find.text('أدعيتي'));
          await tester.pumpAndSettle();
          final back = tester.widget<Icon>(
            find.descendant(
              of: find.byType(BackButton),
              matching: find.byType(Icon),
            ),
          );
          expect(back.icon, Icons.keyboard_arrow_right_rounded);
          expect(back.icon!.matchTextDirection, isFalse);
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(find.byType(MishkatShortcutTile), findsOneWidget);
          expect(find.text('تفاصيل الأدعية'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
