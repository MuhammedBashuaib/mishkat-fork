// dart format off
// Generated bridge with maintained native widget fields.
// See docs/HOME_WIDGETS.md before regenerating.
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:io';
import 'package:home_widget/home_widget.dart';

class WirdWidgetHomeWidget {
  const WirdWidgetHomeWidget._();

  static const String _$appGroupId = 'group.com.dakomn.mishkatapp.widgets';

  static const String _$paramPrefix = 'home_widget.WirdWidget';

  static Future<void> saveData({
    String? wirdName,
    String? wirdPages,
    String? wirdDetail,
    String? wirdProgress,
    String? wirdAction,
    double? wirdProgressValue,
    String? wirdCompletedPages,
    String? wirdRemainingPages,
  }) {
    return Future.wait([
      if (wirdName != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.wirdName', wirdName, appGroupId: _$appGroupId),
      if (wirdPages != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.wirdPages', wirdPages, appGroupId: _$appGroupId),
      if (wirdDetail != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.wirdDetail', wirdDetail, appGroupId: _$appGroupId),
      if (wirdProgress != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.wirdProgress', wirdProgress, appGroupId: _$appGroupId),
      if (wirdAction != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.wirdAction', wirdAction, appGroupId: _$appGroupId),
      if (wirdProgressValue != null) HomeWidget.saveWidgetData<double>('${_$paramPrefix}.wirdProgressValue', wirdProgressValue, appGroupId: _$appGroupId),
      if (wirdCompletedPages != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.wirdCompletedPages', wirdCompletedPages, appGroupId: _$appGroupId),
      if (wirdRemainingPages != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.wirdRemainingPages', wirdRemainingPages, appGroupId: _$appGroupId),
    ]);
  }

  static Future<void> deleteData({
    bool wirdName = false,
    bool wirdPages = false,
    bool wirdDetail = false,
    bool wirdProgress = false,
    bool wirdAction = false,
    bool wirdProgressValue = false,
    bool wirdCompletedPages = false,
    bool wirdRemainingPages = false,
  }) {
    return Future.wait([
      if (wirdName) HomeWidget.saveWidgetData('${_$paramPrefix}.wirdName', null, appGroupId: _$appGroupId),
      if (wirdPages) HomeWidget.saveWidgetData('${_$paramPrefix}.wirdPages', null, appGroupId: _$appGroupId),
      if (wirdDetail) HomeWidget.saveWidgetData('${_$paramPrefix}.wirdDetail', null, appGroupId: _$appGroupId),
      if (wirdProgress) HomeWidget.saveWidgetData('${_$paramPrefix}.wirdProgress', null, appGroupId: _$appGroupId),
      if (wirdAction) HomeWidget.saveWidgetData('${_$paramPrefix}.wirdAction', null, appGroupId: _$appGroupId),
      if (wirdProgressValue) HomeWidget.saveWidgetData('${_$paramPrefix}.wirdProgressValue', null, appGroupId: _$appGroupId),
      if (wirdCompletedPages) HomeWidget.saveWidgetData('${_$paramPrefix}.wirdCompletedPages', null, appGroupId: _$appGroupId),
      if (wirdRemainingPages) HomeWidget.saveWidgetData('${_$paramPrefix}.wirdRemainingPages', null, appGroupId: _$appGroupId),
    ]);
  }

  static Future<({String? wirdName, String? wirdPages, String? wirdDetail, String? wirdProgress, String? wirdAction, double? wirdProgressValue, String? wirdCompletedPages, String? wirdRemainingPages})> getData() async {
    return (
      wirdName: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.wirdName', defaultValue: 'رحلتك مع القرآن', appGroupId: _$appGroupId),
      wirdPages: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.wirdPages', defaultValue: 'ابدأ ختمتك الأولى', appGroupId: _$appGroupId),
      wirdDetail: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.wirdDetail', defaultValue: 'حدّد خطتك ليظهر وردك هنا', appGroupId: _$appGroupId),
      wirdProgress: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.wirdProgress', defaultValue: 'خطوة صغيرة كل يوم', appGroupId: _$appGroupId),
      wirdAction: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.wirdAction', defaultValue: 'اضغط لإنشاء خطة', appGroupId: _$appGroupId),
      wirdProgressValue: await HomeWidget.getWidgetData<double>('${_$paramPrefix}.wirdProgressValue', defaultValue: 0, appGroupId: _$appGroupId),
      wirdCompletedPages: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.wirdCompletedPages', defaultValue: 'أنجزت ٠ صفحة', appGroupId: _$appGroupId),
      wirdRemainingPages: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.wirdRemainingPages', defaultValue: 'باقي ٠ صفحة', appGroupId: _$appGroupId),
    );
  }


  static Future<bool?> updateWidget() {
    return HomeWidget.updateWidget(
      qualifiedAndroidName: 'com.dakomn.mishkatapp.WirdWidgetHomeWidgetReceiver',
      iOSName: 'WirdWidgetHomeWidget',
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
      qualifiedAndroidName: 'com.dakomn.mishkatapp.WirdWidgetHomeWidgetReceiver',
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
      qualifiedAndroidName: 'com.dakomn.mishkatapp.WirdWidgetHomeWidgetReceiver',
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
      return androidClassName.endsWith('.WirdWidgetHomeWidgetReceiver');
    }
    return info.iOSKind == 'WirdWidgetHomeWidget';
  }

  /// The URL a tap on the widget opens the app with, as the app
  /// will receive it.
  ///
  /// The configured `widgetUrl` carrying the `homeWidget` query
  /// parameter, parsed — so its scheme is lower-cased, exactly like
  /// the URL handed to the app.
  static final Uri widgetUrl = Uri.parse('mishkat://wird?homeWidget');

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
