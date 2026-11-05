import 'package:home_widget_generator/home_widget_generator.dart';

// Design seed only: compact native layouts/progress ring are maintained
// separately. Read docs/HOME_WIDGETS.md before running the generator.

const _background = HWThemedColor(
  light: HWFixedColor(0xFFF8F3FC),
  dark: HWFixedColor(0xFF271E30),
);
const _accent = HWThemedColor(
  light: HWFixedColor(0xFF725387),
  dark: HWFixedColor(0xFFD7B8EE),
);
const _text = HWThemedColor(
  light: HWFixedColor(0xFF263B35),
  dark: HWFixedColor(0xFFF6F4F1),
);

@HomeWidget(
  name: 'المسبحة',
  description: 'ذكرك الحالي وعدّادك وهدفك في لمحة',
  widgetUrl: 'mishkat://tasbih',
  android: HomeWidgetAndroidConfiguration(
    minWidth: 110,
    minHeight: 110,
    minResizeWidth: 110,
    minResizeHeight: 110,
    targetCellWidth: 2,
    targetCellHeight: 2,
    resizeMode: HWAndroidResizeMode.horizontalAndVertical,
    widgetCategory: HWAndroidWidgetCategory.homeScreen,
    updatePeriodMillis: 1800000,
    backgroundColor: _background,
  ),
  iOS: HomeWidgetIOSConfiguration(
    groupId: 'group.com.dakomn.mishkatapp.widgets',
    supportedFamilies: [HWWidgetFamily.systemSmall],
    backgroundColor: _background,
  ),
  widget: HWSizedBox.expand(
    child: HWColumn(
      crossAxisAlignment: HWCrossAxisAlignment.center,
      mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
      children: [
        HWText.fixed(
          'مِشكاة • المسبحة',
          style: HWTextStyle(
            fontSize: 11,
            fontWeight: HWFontWeight.w700,
            color: _accent,
          ),
        ),
        HWDecoratedBox(
          decoration: HWBoxDecoration(
            color: HWThemedColor(
              light: HWFixedColor(0xFFEFE3F7),
              dark: HWFixedColor(0xFF3A2945),
            ),
            borderRadius: HWBorderRadius.circular(18),
          ),
          child: HWPadding(
            padding: HWEdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.center,
              children: [
                HWText(
                  HWString(
                    'tasbihDhikr',
                    defaultValue: 'سبحان الله',
                    previewValue: 'سبحان الله',
                  ),
                  style: HWTextStyle(
                    fontSize: 13,
                    fontWeight: HWFontWeight.w600,
                    color: _accent,
                  ),
                  textAlign: HWTextAlign.center,
                ),
                HWText(
                  HWString(
                    'tasbihCount',
                    defaultValue: '٠',
                    previewValue: '٢٤',
                  ),
                  style: HWTextStyle(
                    fontSize: 36,
                    fontWeight: HWFontWeight.w800,
                    color: _text,
                  ),
                  textAlign: HWTextAlign.center,
                ),
                HWText(
                  HWString(
                    'tasbihTarget',
                    defaultValue: 'الهدف ٣٣',
                    previewValue: 'الهدف ٣٣',
                  ),
                  style: HWTextStyle(
                    fontSize: 11,
                    fontWeight: HWFontWeight.w600,
                    color: _accent,
                  ),
                  textAlign: HWTextAlign.center,
                ),
                HWText(
                  HWTimedData(
                    HWString(
                      'tasbihToday',
                      defaultValue: 'اليوم ٠ تسبيحة',
                      previewValue: 'اليوم ٩٠ تسبيحة',
                    ),
                  ),
                  style: HWTextStyle(
                    fontSize: 11,
                    fontWeight: HWFontWeight.w600,
                    color: _accent,
                  ),
                  textAlign: HWTextAlign.center,
                ),
              ],
            ),
          ),
        ),
        HWText(
          HWString(
            'tasbihAction',
            defaultValue: 'اضغط لفتح المسبحة',
            previewValue: 'اضغط لفتح المسبحة',
          ),
          style: HWTextStyle(
            fontSize: 10,
            fontWeight: HWFontWeight.w600,
            color: _accent,
          ),
          textAlign: HWTextAlign.center,
        ),
      ],
    ),
  ),
)
class TasbihWidget {}
