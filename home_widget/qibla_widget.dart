import 'package:home_widget_generator/home_widget_generator.dart';

const _background = HWThemedColor(
  light: HWFixedColor(0xFF214F44),
  dark: HWFixedColor(0xFF0E2821),
);
const _white = HWFixedColor(0xFFF4FAF7);
const _whiteMuted = HWFixedColor(0xFFB7D0C7);
const _gold = HWFixedColor(0xFFF0CF82);
const _compassSurface = HWThemedColor(
  light: HWFixedColor(0xFF315F54),
  dark: HWFixedColor(0xFF1B4036),
);

@HomeWidget(
  name: 'بوصلة القبلة',
  description: 'اتجاه القبلة من موقعك مع انتقال للبوصلة الحية',
  widgetUrl: 'mishkat://qibla',
  android: HomeWidgetAndroidConfiguration(
    minWidth: 110,
    minHeight: 110,
    minResizeWidth: 90,
    minResizeHeight: 90,
    targetCellWidth: 2,
    targetCellHeight: 2,
    resizeMode: HWAndroidResizeMode.none,
    widgetCategory: HWAndroidWidgetCategory.homeScreen,
    updatePeriodMillis: 86400000,
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
          'مِشكاة • القبلة',
          style: HWTextStyle(
            fontSize: 12,
            fontWeight: HWFontWeight.w700,
            color: _whiteMuted,
          ),
        ),
        HWDecoratedBox(
          decoration: HWBoxDecoration(
            color: _compassSurface,
            border: HWBoxBorder(thickness: 1, color: _gold),
            borderRadius: HWBorderRadius.circular(999),
          ),
          child: HWPadding(
            padding: HWEdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: HWText(
              HWString('qiblaArrow', defaultValue: '↑', previewValue: '↗'),
              style: HWTextStyle(
                fontSize: 42,
                fontWeight: HWFontWeight.w400,
                color: _gold,
              ),
            ),
          ),
        ),
        HWColumn(
          spacing: 1,
          children: [
            HWText(
              HWString(
                'qiblaBearing',
                defaultValue: 'حدّد موقعك',
                previewValue: '٢٧٧° شمال غربي',
              ),
              style: HWTextStyle(
                fontSize: 13,
                fontWeight: HWFontWeight.w700,
                color: _white,
              ),
            ),
            HWText(
              HWString(
                'qiblaDistance',
                defaultValue: 'افتح مشكاة للبوصلة الحية',
                previewValue: '٨٢٣ كم إلى الكعبة',
              ),
              style: HWTextStyle(fontSize: 10, color: _whiteMuted),
            ),
          ],
        ),
      ],
    ),
  ),
)
class QiblaWidget {}
