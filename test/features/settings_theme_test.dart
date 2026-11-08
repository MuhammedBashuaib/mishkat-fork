import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_state.dart';
import 'package:mishkat_app/features/settings/presentation/pages/settings_page.dart';

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

class _TestSettingsApp extends StatelessWidget {
  const _TestSettingsApp();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) => MaterialApp(
          theme: AppTheme.light(1),
          darkTheme: AppTheme.dark(1),
          themeMode: state.settings.themeMode,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: SettingsPage(),
          ),
        ),
      );
}

void main() {
  test('Mushaf starts light for new and existing app settings', () {
    expect(const AppSettings().mushafTheme, MushafThemePreference.light);
    for (final appTheme in AppThemePreference.values) {
      final settings = AppSettings.fromJson({'theme': appTheme.name});
      expect(settings.theme, appTheme);
      expect(settings.mushafTheme, MushafThemePreference.light);
    }
    for (final invalidValue in [null, 'system', 'unsupported', true, 1]) {
      expect(
        AppSettings.fromJson({'mushafTheme': invalidValue}).mushafTheme,
        MushafThemePreference.light,
      );
    }
  });

  test('Mushaf appearance persists independently of app appearance', () async {
    final storage = _MemoryStorage();
    final cubit = SettingsCubit(
      storage: storage,
      locationService: LocationService(),
      notifications: LocalNotificationService(),
    );
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.setTheme(AppThemePreference.dark);
    expect(cubit.state.settings.mushafTheme, MushafThemePreference.light);

    final beforeToggle = cubit.state.settings;
    await cubit.setMushafTheme(MushafThemePreference.dark);
    expect(cubit.state.settings, isNot(beforeToggle));
    expect(cubit.state.settings.theme, AppThemePreference.dark);
    expect(storage.readMap('settings')['mushafTheme'], 'dark');
    expect(
      AppSettings.fromJson(cubit.state.settings.toJson()),
      cubit.state.settings,
    );

    await cubit.setTheme(AppThemePreference.light);
    expect(cubit.state.settings.mushafTheme, MushafThemePreference.dark);
    await cubit.load();
    expect(cubit.state.settings.theme, AppThemePreference.light);
    expect(cubit.state.settings.mushafTheme, MushafThemePreference.dark);

    await cubit.setMushafTheme(MushafThemePreference.light);
    await cubit.load();
    expect(cubit.state.settings.mushafTheme, MushafThemePreference.light);
    expect(storage.readMap('settings')['mushafTheme'], 'light');
  });

  test(
    'widget appearance defaults and persists independently from app theme',
    () {
      final settings = AppSettings.fromJson({'theme': 'dark'});
      expect(settings.theme, AppThemePreference.dark);
      expect(settings.widgetTheme, AppThemePreference.system);
      final updated = settings.copyWith(widgetTheme: AppThemePreference.light);
      expect(updated.theme, AppThemePreference.dark);
      expect(updated.widgetTheme, AppThemePreference.light);
      expect(updated, isNot(settings));
      expect(AppSettings.fromJson(updated.toJson()), updated);
      expect(
        AppSettings.fromJson({'widgetTheme': 'unsupported'}).widgetTheme,
        AppThemePreference.system,
      );
    },
  );

  testWidgets('theme selector applies and persists dark mode', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _MemoryStorage();
    final cubit = SettingsCubit(
      storage: storage,
      locationService: LocationService(),
      notifications: LocalNotificationService(),
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(
      BlocProvider.value(value: cubit, child: const _TestSettingsApp()),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final darkChoice = find.byKey(const ValueKey('theme-dark'));
    expect(darkChoice, findsOneWidget);
    await tester.tap(darkChoice);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(cubit.state.settings.theme, AppThemePreference.dark);
    expect(storage.readMap('settings')['theme'], 'dark');
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.dark,
    );
  });
}
