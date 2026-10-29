import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/home_widget_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/home/presentation/cubit/home_cubit.dart';
import 'package:mishkat_app/features/home_widgets/presentation/pages/home_widgets_page.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

class _MemoryStorage implements LocalStorageService {
  final Map<String, dynamic> values = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from((values[key] as Map?) ?? {});

  @override
  List<dynamic> readList(String key) =>
      List<dynamic>.from((values[key] as List?) ?? []);

  @override
  int readInt(String key, [int fallback = 0]) =>
      (values[key] as num?)?.toInt() ?? fallback;

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    values[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    values[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'home widget gallery has no layout errors in ${brightness.name} mode',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 2600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final settingsCubit = SettingsCubit(
          storage: _MemoryStorage(),
          locationService: LocationService(),
          notifications: LocalNotificationService(),
        );
        final homeCubit = HomeCubit(const AppSettings());
        final widgetService = HomeWidgetService(
          adhkarRepository: AdhkarRepository(),
        );

        await tester.pumpWidget(
          RepositoryProvider<HomeWidgetService>.value(
            value: widgetService,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
                BlocProvider<HomeCubit>.value(value: homeCubit),
              ],
              child: MaterialApp(
                theme: brightness == Brightness.dark
                    ? AppTheme.dark()
                    : AppTheme.light(),
                home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: HomeWidgetsPage(),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.text('مواقيت الصلاة'), findsOneWidget);
        expect(find.text('بوصلة القبلة'), findsOneWidget);
        expect(find.text('ذِكر اليوم'), findsOneWidget);
        final actionCount =
            find.text('أضف للشاشة الرئيسية').evaluate().length +
            find.text('جارٍ التحقق…').evaluate().length;
        expect(actionCount, 3);

        await tester.pumpWidget(const SizedBox.shrink());
        await settingsCubit.close();
        await homeCubit.close();
      },
    );
  }
}
