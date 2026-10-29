// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Placeholder SwiftUI widget.
//
// App Group ID used here: QiblaWidgetHomeWidgetFlavor.appGroupId

import SwiftUI
import WidgetKit

enum QiblaWidgetHomeWidgetFlavor {
  static let appGroupId = "group.com.dakomn.mishkatapp.widgets"
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> QiblaWidgetHomeWidgetEntry {
    QiblaWidgetHomeWidgetEntry(date: Date(), data: QiblaWidgetData.previewFromUserDefaults(nil))
  }

  func getSnapshot(in context: Context, completion: @escaping (QiblaWidgetHomeWidgetEntry) -> Void) {
    if context.isPreview {
      let prefs: UserDefaults? = UserDefaults(suiteName: QiblaWidgetHomeWidgetFlavor.appGroupId)
      let data = QiblaWidgetData.previewFromUserDefaults(prefs)
      completion(QiblaWidgetHomeWidgetEntry(date: Date(), data: data))
      return
    }

    let prefs = UserDefaults(suiteName: QiblaWidgetHomeWidgetFlavor.appGroupId)
    let data = QiblaWidgetData.fromUserDefaults(prefs)

    completion(QiblaWidgetHomeWidgetEntry(date: Date(), data: data))

  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let prefs = UserDefaults(suiteName: QiblaWidgetHomeWidgetFlavor.appGroupId)
    let data = QiblaWidgetData.fromUserDefaults(prefs)

    completion(Timeline(entries: [QiblaWidgetHomeWidgetEntry(date: Date(), data: data)], policy: .atEnd))

  }
}

struct QiblaWidgetHomeWidgetEntry: TimelineEntry {
  let date: Date
  let data: QiblaWidgetData
}


struct QiblaWidgetHomeWidgetEntryView: View {
  var entry: Provider.Entry

  @Environment(\.colorScheme) var colorScheme

  var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text("مِشكاة • القبلة")
                .font(.system(size: 12.0, weight: .bold)).foregroundColor(Color(red: 0.7176470588235294, green: 0.8156862745098039, blue: 0.7803921568627451, opacity: 1.0))
            Spacer(minLength: 0)
            Text(entry.data.qiblaArrow ?? "")
                .font(.system(size: 42.0, weight: .regular)).foregroundColor(Color(red: 0.9411764705882353, green: 0.8117647058823529, blue: 0.5098039215686274, opacity: 1.0))
            .padding(EdgeInsets(top: 8.0, leading: 15.0, bottom: 8.0, trailing: 15.0))
            .background(RoundedRectangle(cornerRadius: 999.0).fill((colorScheme == .dark ? Color(red: 0.10588235294117647, green: 0.25098039215686274, blue: 0.21176470588235294, opacity: 1.0) : Color(red: 0.19215686274509805, green: 0.37254901960784315, blue: 0.32941176470588235, opacity: 1.0))))
            .overlay(RoundedRectangle(cornerRadius: 999.0).strokeBorder(Color(red: 0.9411764705882353, green: 0.8117647058823529, blue: 0.5098039215686274, opacity: 1.0), lineWidth: 1.0))
            Spacer(minLength: 0)
            VStack(alignment: .center, spacing: 0) {
                Text(entry.data.qiblaBearing ?? "")
                    .font(.system(size: 13.0, weight: .bold)).foregroundColor(Color(red: 0.9568627450980393, green: 0.9803921568627451, blue: 0.9686274509803922, opacity: 1.0))
                Text(entry.data.qiblaDistance ?? "")
                    .font(.system(size: 10.0)).foregroundColor(Color(red: 0.7176470588235294, green: 0.8156862745098039, blue: 0.7803921568627451, opacity: 1.0))
                .padding(.top, 1.0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .applyContainerBackground((colorScheme == .dark ? Color(red: 0.054901960784313725, green: 0.1568627450980392, blue: 0.12941176470588237, opacity: 1.0) : Color(red: 0.12941176470588237, green: 0.30980392156862746, blue: 0.26666666666666666, opacity: 1.0)))
    .widgetURL(URL(string: "mishkat://qibla?homeWidget"))
  }
}

struct QiblaWidgetHomeWidget: Widget {
  let kind: String = "QiblaWidgetHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      QiblaWidgetHomeWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("بوصلة القبلة")
    .description("اتجاه القبلة من موقعك مع انتقال للبوصلة الحية")
    .supportedFamilies([.systemSmall])
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

struct QiblaWidgetData {
  let qiblaArrow: String?
  let qiblaBearing: String?
  let qiblaDistance: String?

  static let paramPrefix = "home_widget.QiblaWidget"

  static func fromUserDefaults(_ defaults: UserDefaults?) -> QiblaWidgetData {
    return QiblaWidgetData(
      qiblaArrow: (defaults?.string(forKey: "\(paramPrefix).qiblaArrow") ?? "↑"),
      qiblaBearing: (defaults?.string(forKey: "\(paramPrefix).qiblaBearing") ?? "حدّد موقعك"),
      qiblaDistance: (defaults?.string(forKey: "\(paramPrefix).qiblaDistance") ?? "افتح مشكاة للبوصلة الحية"),
    )
  }

  static func previewFromUserDefaults(_ defaults: UserDefaults?) -> QiblaWidgetData {
    return QiblaWidgetData(
      qiblaArrow: (defaults?.string(forKey: "\(paramPrefix).qiblaArrow") ?? "↗"),
      qiblaBearing: (defaults?.string(forKey: "\(paramPrefix).qiblaBearing") ?? "٢٧٧° شمال غربي"),
      qiblaDistance: (defaults?.string(forKey: "\(paramPrefix).qiblaDistance") ?? "٨٢٣ كم إلى الكعبة"),
    )
  }
}

