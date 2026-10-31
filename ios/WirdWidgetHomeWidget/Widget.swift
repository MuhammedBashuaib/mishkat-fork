// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Placeholder SwiftUI widget.
//
// App Group ID used here: WirdWidgetHomeWidgetFlavor.appGroupId

import SwiftUI
import WidgetKit

enum WirdWidgetHomeWidgetFlavor {
  static let appGroupId = "group.com.dakomn.mishkatapp.widgets"
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> WirdWidgetHomeWidgetEntry {
    WirdWidgetHomeWidgetEntry(date: Date(), data: WirdWidgetData.previewFromUserDefaults(nil))
  }

  func getSnapshot(in context: Context, completion: @escaping (WirdWidgetHomeWidgetEntry) -> Void) {
    if context.isPreview {
      let prefs: UserDefaults? = UserDefaults(suiteName: WirdWidgetHomeWidgetFlavor.appGroupId)
      let data = WirdWidgetData.previewFromUserDefaults(prefs)
      completion(WirdWidgetHomeWidgetEntry(date: Date(), data: data))
      return
    }

    let prefs = UserDefaults(suiteName: WirdWidgetHomeWidgetFlavor.appGroupId)
    let data = WirdWidgetData.fromUserDefaults(prefs)

    completion(WirdWidgetHomeWidgetEntry(date: Date(), data: data))

  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let prefs = UserDefaults(suiteName: WirdWidgetHomeWidgetFlavor.appGroupId)
    let data = WirdWidgetData.fromUserDefaults(prefs)

    completion(Timeline(entries: [WirdWidgetHomeWidgetEntry(date: Date(), data: data)], policy: .atEnd))

  }
}

struct WirdWidgetHomeWidgetEntry: TimelineEntry {
  let date: Date
  let data: WirdWidgetData
}


struct WirdWidgetHomeWidgetEntryView: View {
  var entry: Provider.Entry

  @Environment(\.colorScheme) var colorScheme

  var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("مِشكاة • الورد اليومي")
                .font(.system(size: 11.0, weight: .bold)).foregroundColor((colorScheme == .dark ? Color(red: 0.6627450980392157, green: 0.8509803921568627, blue: 0.8, opacity: 1.0) : Color(red: 0.2823529411764706, green: 0.4196078431372549, blue: 0.396078431372549, opacity: 1.0)))
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(entry.data.wirdName ?? "")
                    .font(.system(size: 11.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.6627450980392157, green: 0.8509803921568627, blue: 0.8, opacity: 1.0) : Color(red: 0.2823529411764706, green: 0.4196078431372549, blue: 0.396078431372549, opacity: 1.0)))
                    .multilineTextAlignment(.trailing)
                Text(entry.data.wirdPages ?? "")
                    .font(.system(size: 23.0, weight: .heavy)).foregroundColor((colorScheme == .dark ? Color(red: 0.9647058823529412, green: 0.9568627450980393, blue: 0.9450980392156862, opacity: 1.0) : Color(red: 0.14901960784313725, green: 0.23137254901960785, blue: 0.20784313725490197, opacity: 1.0)))
                    .multilineTextAlignment(.trailing)
                Text(entry.data.wirdDetail ?? "")
                    .font(.system(size: 12.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.6627450980392157, green: 0.8509803921568627, blue: 0.8, opacity: 1.0) : Color(red: 0.2823529411764706, green: 0.4196078431372549, blue: 0.396078431372549, opacity: 1.0)))
                    .multilineTextAlignment(.trailing)
                Text(entry.data.wirdProgress ?? "")
                    .font(.system(size: 12.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.6627450980392157, green: 0.8509803921568627, blue: 0.8, opacity: 1.0) : Color(red: 0.2823529411764706, green: 0.4196078431372549, blue: 0.396078431372549, opacity: 1.0)))
                    .multilineTextAlignment(.trailing)
            }
            .padding(EdgeInsets(top: 8.0, leading: 12.0, bottom: 8.0, trailing: 12.0))
            .background(RoundedRectangle(cornerRadius: 18.0).fill((colorScheme == .dark ? Color(red: 0.13725490196078433, green: 0.24313725490196078, blue: 0.2, opacity: 1.0) : Color(red: 0.8862745098039215, green: 0.9333333333333333, blue: 0.9058823529411765, opacity: 1.0))))
            Spacer(minLength: 0)
            Text(entry.data.wirdAction ?? "")
                .font(.system(size: 10.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.6627450980392157, green: 0.8509803921568627, blue: 0.8, opacity: 1.0) : Color(red: 0.2823529411764706, green: 0.4196078431372549, blue: 0.396078431372549, opacity: 1.0)))
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    .applyContainerBackground((colorScheme == .dark ? Color(red: 0.08235294117647059, green: 0.1607843137254902, blue: 0.13725490196078433, opacity: 1.0) : Color(red: 0.9490196078431372, green: 0.9686274509803922, blue: 0.9529411764705882, opacity: 1.0)))
    .widgetURL(URL(string: "mishkat://wird?homeWidget"))
  }
}

struct WirdWidgetHomeWidget: Widget {
  let kind: String = "WirdWidgetHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      WirdWidgetHomeWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("الورد اليومي")
    .description("ورد ختمتك وموضع القراءة المحفوظ")
    .supportedFamilies([.systemMedium])
  }
}

extension View {
  @ViewBuilder
  func applyContainerBackground<T: View>(_ backgroundView: T) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      self.containerBackground(for: .widget) { backgroundView }
    } else {
      self.background(backgroundView)
    }
  }
}

struct WirdWidgetData {
  let wirdName: String?
  let wirdPages: String?
  let wirdDetail: String?
  let wirdProgress: String?
  let wirdAction: String?

  static let paramPrefix = "home_widget.WirdWidget"

  static func fromUserDefaults(_ defaults: UserDefaults?) -> WirdWidgetData {
    return WirdWidgetData(
      wirdName: (defaults?.string(forKey: "\(paramPrefix).wirdName") ?? "رحلتك مع القرآن"),
      wirdPages: (defaults?.string(forKey: "\(paramPrefix).wirdPages") ?? "ابدأ ختمتك الأولى"),
      wirdDetail: (defaults?.string(forKey: "\(paramPrefix).wirdDetail") ?? "حدّد خطتك ليظهر وردك هنا"),
      wirdProgress: (defaults?.string(forKey: "\(paramPrefix).wirdProgress") ?? "خطوة صغيرة كل يوم"),
      wirdAction: (defaults?.string(forKey: "\(paramPrefix).wirdAction") ?? "اضغط لإنشاء خطة"),
    )
  }

  static func previewFromUserDefaults(_ defaults: UserDefaults?) -> WirdWidgetData {
    return WirdWidgetData(
      wirdName: (defaults?.string(forKey: "\(paramPrefix).wirdName") ?? "ختمتي"),
      wirdPages: (defaults?.string(forKey: "\(paramPrefix).wirdPages") ?? "صفحة ٤٢ – ٦٢"),
      wirdDetail: (defaults?.string(forKey: "\(paramPrefix).wirdDetail") ?? "٢١ صفحة في وردك الحالي"),
      wirdProgress: (defaults?.string(forKey: "\(paramPrefix).wirdProgress") ?? "٧٪ من الختمة"),
      wirdAction: (defaults?.string(forKey: "\(paramPrefix).wirdAction") ?? "اضغط لمتابعة القراءة"),
    )
  }
}

