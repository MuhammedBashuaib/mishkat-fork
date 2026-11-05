// dart format off
// CUSTOMIZED generated bridge: native progress field is maintained by hand.
// See docs/HOME_WIDGETS.md before regenerating.
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class TasbihWidgetHomeWidget {
  const TasbihWidgetHomeWidget._();

  static const String _$appGroupId = 'group.com.dakomn.mishkatapp.widgets';

  static const String _$paramPrefix = 'home_widget.TasbihWidget';

  static Future<void> saveData({
    String? tasbihDhikr,
    String? tasbihCount,
    String? tasbihTarget,
    String? tasbihAction,
    double? tasbihProgressValue,
    Map<DateTime, TasbihWidgetTimedData>? timedData,
  }) {
    return Future.wait([
      if (tasbihDhikr != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.tasbihDhikr', tasbihDhikr, appGroupId: _$appGroupId),
      if (tasbihCount != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.tasbihCount', tasbihCount, appGroupId: _$appGroupId),
      if (tasbihTarget != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.tasbihTarget', tasbihTarget, appGroupId: _$appGroupId),
      if (tasbihAction != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.tasbihAction', tasbihAction, appGroupId: _$appGroupId),
      if (tasbihProgressValue != null) HomeWidget.saveWidgetData<double>('${_$paramPrefix}.tasbihProgressValue', tasbihProgressValue, appGroupId: _$appGroupId),
      if (timedData != null) () async {
        final _timedTimes = timedData.keys.toList()..sort();
        if (_timedTimes.isEmpty) {
          await HomeWidget.saveWidgetData('${_$paramPrefix}.timedData', null, appGroupId: _$appGroupId);
          try {
            await HomeWidget.cancelScheduledWidgetUpdates(androidName: 'TasbihWidgetHomeWidgetReceiver');
          } catch (error, stackTrace) {
            // Cancelling is best effort; the data was deleted.
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'home_widget',
                context: ErrorDescription('cancelling scheduled updates for the TasbihWidget widget'),
              ),
            );
          }
          return;
        }
        final _timedJson = <String, dynamic>{
          for (final _time in _timedTimes)
            _time.toUtc().millisecondsSinceEpoch.toString(): timedData[_time]!.toJson(),
        };
        await HomeWidget.saveFile('${_$paramPrefix}.timedData', Uint8List.fromList(utf8.encode(jsonEncode(_timedJson))), extension: 'json', appGroupId: _$appGroupId);
        try {
          await HomeWidget.scheduleWidgetUpdates(_timedTimes, androidName: 'TasbihWidgetHomeWidgetReceiver');
        } catch (error, stackTrace) {
          // Scheduling is best effort; the data was saved.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'home_widget',
              context: ErrorDescription('scheduling updates for the TasbihWidget widget'),
            ),
          );
        }
      }(),
    ]);
  }

  static Future<void> deleteData({
    bool tasbihDhikr = false,
    bool tasbihCount = false,
    bool tasbihTarget = false,
    bool tasbihAction = false,
    bool tasbihProgressValue = false,
    bool timedData = false,
  }) {
    return Future.wait([
      if (tasbihDhikr) HomeWidget.saveWidgetData('${_$paramPrefix}.tasbihDhikr', null, appGroupId: _$appGroupId),
      if (tasbihCount) HomeWidget.saveWidgetData('${_$paramPrefix}.tasbihCount', null, appGroupId: _$appGroupId),
      if (tasbihTarget) HomeWidget.saveWidgetData('${_$paramPrefix}.tasbihTarget', null, appGroupId: _$appGroupId),
      if (tasbihAction) HomeWidget.saveWidgetData('${_$paramPrefix}.tasbihAction', null, appGroupId: _$appGroupId),
      if (tasbihProgressValue) HomeWidget.saveWidgetData('${_$paramPrefix}.tasbihProgressValue', null, appGroupId: _$appGroupId),
      if (timedData) () async {
        await HomeWidget.saveWidgetData('${_$paramPrefix}.timedData', null, appGroupId: _$appGroupId);
        try {
          await HomeWidget.cancelScheduledWidgetUpdates(androidName: 'TasbihWidgetHomeWidgetReceiver');
        } catch (error, stackTrace) {
          // Cancelling is best effort; the data was deleted.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'home_widget',
              context: ErrorDescription('cancelling scheduled updates for the TasbihWidget widget'),
            ),
          );
        }
      }(),
    ]);
  }

  /// Reads every stored value back.
  ///
  /// The keys of [timedData] are local-time [DateTime]s, so they compare equal to a
  /// local [DateTime] for the same instant. Timestamps are stored as epoch
  /// milliseconds: sub-millisecond precision of the saved keys is not preserved.
  /// Keys are compared by instant, so a local [DateTime] and its `toUtc()` twin
  /// denote the same entry and only one of them survives a save.
  static Future<({String? tasbihDhikr, String? tasbihCount, String? tasbihTarget, String? tasbihAction, double? tasbihProgressValue, Map<DateTime, TasbihWidgetTimedData>? timedData})> getData() async {
    final _timedDataPath = await HomeWidget.getWidgetData<String>('${_$paramPrefix}.timedData', appGroupId: _$appGroupId);
    Map<DateTime, TasbihWidgetTimedData>? timedData;
    if (_timedDataPath != null) {
      try {
        final raw = await File(_timedDataPath).readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final entries = <DateTime, TasbihWidgetTimedData>{};
          for (final entry in decoded.entries) {
            final millis = int.tryParse(entry.key);
            if (millis == null) continue;
            final value = entry.value;
            entries[DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal()] = TasbihWidgetTimedData.fromJson(value is Map<String, dynamic> ? value : null);
          }
          timedData = entries;
        }
      } on Exception {
        timedData = null;
      }
    }
    return (
      tasbihDhikr: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.tasbihDhikr', defaultValue: 'سبحان الله', appGroupId: _$appGroupId),
      tasbihCount: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.tasbihCount', defaultValue: '٠', appGroupId: _$appGroupId),
      tasbihTarget: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.tasbihTarget', defaultValue: 'الهدف ٣٣', appGroupId: _$appGroupId),
      tasbihAction: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.tasbihAction', defaultValue: 'اضغط لفتح المسبحة', appGroupId: _$appGroupId),
      tasbihProgressValue: await HomeWidget.getWidgetData<double>('${_$paramPrefix}.tasbihProgressValue', defaultValue: 0, appGroupId: _$appGroupId),
      timedData: timedData,
    );
  }


  static Future<bool?> updateWidget() {
    return HomeWidget.updateWidget(
      androidName: 'TasbihWidgetHomeWidgetReceiver',
      iOSName: 'TasbihWidgetHomeWidget',
    );
  }

  /// Asks the launcher to re-render this widget's gallery preview.
  ///
  /// Android 15 and newer only; returns false elsewhere and when the system
  /// rate limit (about two updates per hour and widget) was hit. The plugin
  /// registers the preview automatically when the app starts, so this is only
  /// needed after data changes that should show in the gallery right away.
  static Future<bool> updatePreview() async {
    return await HomeWidget.updateWidgetPreview(
      androidName: 'TasbihWidgetHomeWidgetReceiver',
    ) ?? false;
  }

  /// Whether the launcher lets the app ask to add this widget to the home
  /// screen: Android 8 or newer with a launcher that supports pinning. Always
  /// false on iOS.
  static Future<bool> isRequestPinWidgetSupported() async {
    return await HomeWidget.isRequestPinWidgetSupported() ?? false;
  }

  /// Asks the launcher to add this widget to the home screen.
  ///
  /// Shows the system pin dialog where [isRequestPinWidgetSupported] is true
  /// and does nothing anywhere else.
  static Future<void> requestPinWidget() {
    return HomeWidget.requestPinWidget(
      androidName: 'TasbihWidgetHomeWidgetReceiver',
    );
  }

  /// Every instance of this widget currently placed on a home screen.
  ///
  /// Android reports one entry per placed instance, iOS one entry per family
  /// the widget is placed in.
  static Future<List<HomeWidgetInfo>> getInstalledWidgets() async {
    final widgets = await HomeWidget.getInstalledWidgets();
    return widgets.where(_$isThisWidget).toList();
  }

  /// Whether at least one instance of this widget is on a home screen.
  static Future<bool> isInstalled() async {
    return (await getInstalledWidgets()).isNotEmpty;
  }

  /// Whether [info] describes this widget.
  ///
  /// Android reports the provider's short class name — `.Receiver` when it
  /// lives in the package of the application id, and the qualified name
  /// otherwise — which is why the suffix is matched.
  static bool _$isThisWidget(HomeWidgetInfo info) {
    final androidClassName = info.androidClassName;
    if (androidClassName != null) {
      return androidClassName.endsWith('.TasbihWidgetHomeWidgetReceiver');
    }
    return info.iOSKind == 'TasbihWidgetHomeWidget';
  }

  /// The URL a tap on the widget opens the app with, as the app
  /// will receive it.
  ///
  /// The configured `widgetUrl` carrying the `homeWidget` query
  /// parameter, parsed — so its scheme is lower-cased, exactly like
  /// the URL handed to the app.
  static final Uri widgetUrl = Uri.parse('mishkat://tasbih?homeWidget');

  /// The URL the app was launched with by a tap on the widget, or null
  /// when it was started any other way.
  ///
  /// Only the URL this widget opens on the platform the app is running
  /// on is reported; a tap on any other widget is not.
  static Future<Uri?> initiallyLaunchedFromWidget() async {
    final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (uri == null || !_$matchesWidgetUrl(uri)) {
      return null;
    }
    return uri;
  }

  /// The URL of every tap on the widget while the app is running.
  ///
  /// A tap that started the app in the first place is not replayed here
  /// — read [initiallyLaunchedFromWidget] for that one, or listen to
  /// [launchedFromWidget] for both.
  ///
  /// Only the URL this widget opens on the platform the app is running
  /// on is reported; a tap on any other widget is not.
  static Stream<Uri> get widgetClicked =>
      HomeWidget.widgetClicked
          .where((uri) => uri != null && _$matchesWidgetUrl(uri))
          .cast<Uri>();

  /// Every tap on the widget, launch included.
  ///
  /// Yields the launch URL first when the app was started by a tap on
  /// the widget, then every tap that follows while it runs. Taps landing
  /// while the launch URL is still being read are kept, not dropped.
  ///
  /// Only the URL this widget opens on the platform the app is running
  /// on is reported; a tap on any other widget is not.
  static Stream<Uri> launchedFromWidget() async* {
    final clicks = StreamController<Uri>();
    final subscription = HomeWidget.widgetClicked.listen(
      (uri) {
        if (uri != null && _$matchesWidgetUrl(uri)) clicks.add(uri);
      },
      onDone: clicks.close,
    );
    try {
      final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initial != null && _$matchesWidgetUrl(initial)) yield initial;
      yield* clicks.stream;
    } finally {
      await subscription.cancel();
      await clicks.close();
    }
  }

  /// Whether [uri] is the URL this platform's widget opens.
  ///
  /// Schemes are compared case-insensitively: the URL reaches the app parsed,
  /// which lower-cases the scheme it was written with.
  static bool _$matchesWidgetUrl(Uri uri) {
    final url = _$platformWidgetUrl;
    if (url == null) return false;
    return _$lowerCaseScheme(uri) == _$lowerCaseScheme(url);
  }

  /// The URL the widget opens on the platform the app is running on, or
  /// null where it opens none.
  static Uri? get _$platformWidgetUrl {
    if (Platform.isAndroid) return widgetUrl;
    if (Platform.isIOS) return widgetUrl;
    return null;
  }

  static String _$lowerCaseScheme(Uri uri) {
    final text = uri.toString();
    return uri.scheme.toLowerCase() + text.substring(uri.scheme.length);
  }
}

class TasbihWidgetTimedData {
  final String? tasbihToday;

  const TasbihWidgetTimedData({
    this.tasbihToday,
  });

  factory TasbihWidgetTimedData.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return TasbihWidgetTimedData(
      tasbihToday: _readString(json['tasbihToday']) ?? 'اليوم ٠ تسبيحة',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (tasbihToday != null) 'tasbihToday': tasbihToday,
    };
  }
}

String? _readString(Object? value) => value is String ? value : null;
