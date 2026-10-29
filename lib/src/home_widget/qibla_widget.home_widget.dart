// dart format off
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:io';
import 'package:home_widget/home_widget.dart';

class QiblaWidgetHomeWidget {
  const QiblaWidgetHomeWidget._();

  static const String _$appGroupId = 'group.com.dakomn.mishkatapp.widgets';

  static const String _$paramPrefix = 'home_widget.QiblaWidget';

  static Future<void> saveData({
    String? qiblaArrow,
    String? qiblaBearing,
    String? qiblaDistance,
  }) {
    return Future.wait([
      if (qiblaArrow != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.qiblaArrow', qiblaArrow, appGroupId: _$appGroupId),
      if (qiblaBearing != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.qiblaBearing', qiblaBearing, appGroupId: _$appGroupId),
      if (qiblaDistance != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.qiblaDistance', qiblaDistance, appGroupId: _$appGroupId),
    ]);
  }

  static Future<void> deleteData({
    bool qiblaArrow = false,
    bool qiblaBearing = false,
    bool qiblaDistance = false,
  }) {
    return Future.wait([
      if (qiblaArrow) HomeWidget.saveWidgetData('${_$paramPrefix}.qiblaArrow', null, appGroupId: _$appGroupId),
      if (qiblaBearing) HomeWidget.saveWidgetData('${_$paramPrefix}.qiblaBearing', null, appGroupId: _$appGroupId),
      if (qiblaDistance) HomeWidget.saveWidgetData('${_$paramPrefix}.qiblaDistance', null, appGroupId: _$appGroupId),
    ]);
  }

  static Future<({String? qiblaArrow, String? qiblaBearing, String? qiblaDistance})> getData() async {
    return (
      qiblaArrow: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.qiblaArrow', defaultValue: '↑', appGroupId: _$appGroupId),
      qiblaBearing: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.qiblaBearing', defaultValue: 'حدّد موقعك', appGroupId: _$appGroupId),
      qiblaDistance: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.qiblaDistance', defaultValue: 'افتح مشكاة للبوصلة الحية', appGroupId: _$appGroupId),
    );
  }


  static Future<bool?> updateWidget() {
    return HomeWidget.updateWidget(
      androidName: 'QiblaWidgetHomeWidgetReceiver',
      iOSName: 'QiblaWidgetHomeWidget',
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
      androidName: 'QiblaWidgetHomeWidgetReceiver',
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
      androidName: 'QiblaWidgetHomeWidgetReceiver',
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
      return androidClassName.endsWith('.QiblaWidgetHomeWidgetReceiver');
    }
    return info.iOSKind == 'QiblaWidgetHomeWidget';
  }

  /// The URL a tap on the widget opens the app with, as the app
  /// will receive it.
  ///
  /// The configured `widgetUrl` carrying the `homeWidget` query
  /// parameter, parsed — so its scheme is lower-cased, exactly like
  /// the URL handed to the app.
  static final Uri widgetUrl = Uri.parse('mishkat://qibla?homeWidget');

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
