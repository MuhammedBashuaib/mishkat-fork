import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/core/widgets/app_exit_confirmation.dart';

Widget _app() => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: AppTheme.light(),
  home: AppExitConfirmation(
    child: Builder(
      builder: (context) => Scaffold(
        body: Column(
          children: [
            const TextField(),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('صفحة داخلية')),
                ),
              ),
              child: const Text('فتح صفحة'),
            ),
            TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => const Text('قائمة'),
              ),
              child: const Text('فتح قائمة'),
            ),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  int exitRequests() => platformCalls
      .where((call) => call.method == 'SystemNavigator.pop')
      .length;

  testWidgets('root back requires confirmation and cancel preserves state', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.enterText(find.byType(TextField), 'موضعي الحالي');
    tester.testTextInput.hide();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('هل أنت متأكد من الخروج من تطبيق مشكاة؟'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(AlertDialog))),
      TextDirection.rtl,
    );
    expect(exitRequests(), 0);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('موضعي الحالي'), findsOneWidget);
    expect(exitRequests(), 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('only explicit confirmation requests a native exit', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('موافق، خروج'));
    await tester.pumpAndSettle();

    expect(exitRequests(), 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('rapid back presses do not stack dialogs or exit', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.binding.handlePopRoute();
    await tester.pump();
    final scope = tester.widget<PopScope<Object?>>(
      find.byType(PopScope<Object?>),
    );
    scope.onPopInvokedWithResult!(false, null);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(exitRequests(), 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(exitRequests(), 0);
  });

  testWidgets('tapping outside the dialog cancels exit', (tester) async {
    await tester.pumpWidget(_app());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(exitRequests(), 0);
  });

  testWidgets('back from a page or sheet returns without exit confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    for (final label in ['فتح صفحة', 'فتح قائمة']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('فتح صفحة'), findsOneWidget);
      expect(exitRequests(), 0);
    }
  });

  testWidgets('iOS root navigation keeps the platform behavior', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final scope = tester.widget<PopScope<Object?>>(
      find.byType(PopScope<Object?>),
    );

    expect(scope.canPop, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(exitRequests(), 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
