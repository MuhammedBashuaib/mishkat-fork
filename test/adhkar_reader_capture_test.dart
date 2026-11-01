import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';
import 'package:mishkat_app/features/adhkar/presentation/pages/adhkar_reader_page.dart';

// Run when reviewing the reader visually:
// flutter test --dart-define=CAPTURE_ADHKAR_READER=true test/adhkar_reader_capture_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const captureEnabled = bool.fromEnvironment('CAPTURE_ADHKAR_READER');
  final repository = AdhkarRepository();

  setUpAll(() async {
    if (!captureEnabled) return;
    final cairo = FontLoader('Cairo');
    for (final weight in ['Regular', 'SemiBold', 'Bold', 'Black']) {
      cairo.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await cairo.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await repository.load();
    await Directory('screenshots').create(recursive: true);
  });

  for (final (name, dark, size, scale) in [
    ('light', false, const Size(390, 844), 1.0),
    ('dark', true, const Size(390, 844), 1.0),
    ('small_large_text', false, const Size(320, 568), 2.0),
  ]) {
    testWidgets('capture adhkar reader: $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cubit = AdhkarCubit(repository, _CaptureStorage());
      await cubit.load();
      cubit.select(1);
      addTearDown(cubit.close);
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  padding: const EdgeInsets.only(top: 24, bottom: 20),
                ),
                child: child!,
              ),
              home: const AdhkarReaderPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> capture(String state) async {
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('screenshots/adhkar_reader_${name}_$state.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      await capture('first');
      if (name == 'light') {
        await tester.tap(find.byKey(const ValueKey('dhikr-counter')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 210));
        await capture('completed');
        await tester.pump(const Duration(milliseconds: 90));
        await tester.pump(const Duration(milliseconds: 180));
        await capture('transition');
        await tester.pumpAndSettle();
      }

      // Choose a concise real dhikr, keeping the source data unchanged.
      final items = cubit.state.selected!.items;
      final shortestIndex = items.indexed
          .reduce(
            (shortest, candidate) =>
                candidate.$2.text.length < shortest.$2.text.length
                ? candidate
                : shortest,
          )
          .$1;
      tester
          .widget<PageView>(find.byType(PageView))
          .controller!
          .jumpToPage(shortestIndex);
      await tester.pumpAndSettle();
      await capture('short');
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: !captureEnabled);
  }
}

class _CaptureStorage implements LocalStorageService {
  final _values = <String, dynamic>{};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from(_values[key] as Map? ?? const {});

  @override
  List<dynamic> readList(String key) =>
      List<dynamic>.from(_values[key] as List? ?? const []);

  @override
  int readInt(String key, [int fallback = 0]) =>
      (_values[key] as num?)?.toInt() ?? fallback;

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _values[key] = value;
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _values[key] = value;
  }

  @override
  Future<void> writeInt(String key, int value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();
}
