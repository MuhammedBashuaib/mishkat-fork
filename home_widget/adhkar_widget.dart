import 'package:home_widget_generator/home_widget_generator.dart';

const _background = HWThemedColor(
  light: HWFixedColor(0xFFFFF8F2),
  dark: HWFixedColor(0xFF211A18),
);
const _primary = HWThemedColor(
  light: HWFixedColor(0xFF8B5D43),
  dark: HWFixedColor(0xFFE8C19F),
);
const _text = HWThemedColor(
  light: HWFixedColor(0xFF3E2C24),
  dark: HWFixedColor(0xFFF7EEE8),
);
const _secondary = HWThemedColor(
  light: HWFixedColor(0xFF7A6559),
  dark: HWFixedColor(0xFFC2ACA0),
);
const _soft = HWThemedColor(
  light: HWFixedColor(0xFFF3E6DE),
  dark: HWFixedColor(0xFF3B2C27),
);

@HomeWidget(
  name: 'ذِكر اليوم',
  description: 'ذكر مناسب لوقتك من أذكار مشكاة',
  widgetUrl: 'mishkat://adhkar',
  android: HomeWidgetAndroidConfiguration(
    minWidth: 250,
    minHeight: 110,
    minResizeWidth: 180,
    minResizeHeight: 90,
    targetCellWidth: 4,
    targetCellHeight: 2,
    resizeMode: HWAndroidResizeMode.horizontalAndVertical,
    widgetCategory: HWAndroidWidgetCategory.homeScreen,
    updatePeriodMillis: 21600000,
    backgroundColor: _background,
  ),
  iOS: HomeWidgetIOSConfiguration(
    groupId: 'group.com.dakomn.mishkatapp.widgets',
    supportedFamilies: [HWWidgetFamily.systemMedium],
    backgroundColor: _background,
  ),
  widget: HWSizedBox.expand(
    child: HWColumn(
      crossAxisAlignment: HWCrossAxisAlignment.end,
      mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
      children: [
        HWRow(
          mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
          children: [
            HWDecoratedBox(
              decoration: HWBoxDecoration(
                color: _soft,
                borderRadius: HWBorderRadius.circular(999),
              ),
              child: HWPadding(
                padding: HWEdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: HWText(
                  HWTimedData(
                    HWString(
                      'dhikrCount',
                      defaultValue: 'مرة واحدة',
                      previewValue: '٣ مرات',
                    ),
                  ),
                  style: HWTextStyle(
                    fontSize: 10,
                    fontWeight: HWFontWeight.w700,
                    color: _primary,
                  ),
                ),
              ),
            ),
            HWText(
              HWTimedData(
                HWString(
                  'dhikrCategory',
                  defaultValue: 'ذِكر اليوم',
                  previewValue: 'أذكار المساء',
                ),
              ),
              style: HWTextStyle(
                fontSize: 12,
                fontWeight: HWFontWeight.w800,
                color: _primary,
              ),
              textAlign: HWTextAlign.end,
            ),
          ],
        ),
        HWDecoratedBox(
          decoration: HWBoxDecoration(
            color: _soft,
            borderRadius: HWBorderRadius.circular(14),
          ),
          child: HWPadding(
            padding: HWEdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: HWText(
              HWTimedData(
                HWString(
                  'dhikrText',
                  defaultValue: 'سبحان الله وبحمده، سبحان الله العظيم.',
                  previewValue: 'رَضِيتُ بِاللَّهِ رَبًّا، وَبِالإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ ﷺ نَبِيًّا.',
                ),
              ),
              style: HWTextStyle(
                fontSize: 15,
                fontWeight: HWFontWeight.w600,
                color: _text,
              ),
              textAlign: HWTextAlign.end,
            ),
          ),
        ),
        HWText.fixed(
          '← اضغط للمتابعة داخل مشكاة',
          style: HWTextStyle(fontSize: 10, color: _secondary),
          textAlign: HWTextAlign.end,
        ),
      ],
    ),
  ),
)
class AdhkarWidget {}
