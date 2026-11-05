// CUSTOMIZED NATIVE WIDGET — preserve when regenerating Dart declarations.
// See docs/HOME_WIDGETS.md for native rendering and the shared data contract.
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
  @Environment(\.colorScheme) private var systemColorScheme
  private var colorScheme: ColorScheme { widgetColorScheme(systemColorScheme) }
  private var accent: Color { colorScheme == .dark ? Color(hex: 0xF0CF82) : Color(hex: 0x9B742C) }
  private var secondary: Color { colorScheme == .dark ? Color(hex: 0xB7D0C7) : Color(hex: 0x526F63) }
  private var hasBearing: Bool { entry.data.qiblaBearingDegrees.isFinite && entry.data.qiblaBearingDegrees >= 0 }

  var body: some View {
    VStack(spacing: 3) {
      Text("مِشكاة • القبلة").font(.system(size: 11, weight: .bold)).foregroundColor(secondary)
      Spacer(minLength: 0)
      ZStack {
        Circle().fill(colorScheme == .dark ? Color(hex: 0x1B4036) : Color(hex: 0xE0EDE6))
        Circle().strokeBorder(accent.opacity(0.7), lineWidth: 1)
        VStack { Text("N").font(.system(size: 9, weight: .semibold)).foregroundColor(secondary); Spacer() }.padding(.top, 5)
        Image(systemName: "location.north.fill")
          .font(.system(size: 33)).foregroundColor(accent)
          .rotationEffect(.degrees(hasBearing ? entry.data.qiblaBearingDegrees : 0))
      }
      .frame(width: 66, height: 66)
      .accessibilityLabel(hasBearing ? "اتجاه القبلة بالنسبة للشمال" : "الشمال — حدّد موقعك لاتجاه القبلة")
      Spacer(minLength: 0)
      Text(hasBearing ? (entry.data.qiblaBearing ?? "القبلة") : "الشمال").font(.system(size: 12, weight: .bold))
        .foregroundColor(colorScheme == .dark ? Color(hex: 0xF4FAF7) : Color(hex: 0x17362F)).lineLimit(1).minimumScaleFactor(0.8)
      Text(hasBearing ? "بالنسبة للشمال" : "حدّد موقعك للقبلة").font(.system(size: 9)).foregroundColor(secondary)
      Text("اضغط للبوصلة الحية").font(.system(size: 9, weight: .semibold)).foregroundColor(secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .applyContainerBackground(colorScheme == .dark ? Color(hex: 0x0E2821) : Color(hex: 0xF3F8F5))
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
  let qiblaBearingDegrees: Double
  let qiblaArrow: String?
  let qiblaBearing: String?
  let qiblaDistance: String?

  static let paramPrefix = "home_widget.QiblaWidget"

  static func fromUserDefaults(_ defaults: UserDefaults?) -> QiblaWidgetData {
    return QiblaWidgetData(
      qiblaBearingDegrees: (defaults?.object(forKey: "\(paramPrefix).qiblaBearingDegrees") as? NSNumber)?.doubleValue ?? -1,
      qiblaArrow: (defaults?.string(forKey: "\(paramPrefix).qiblaArrow") ?? "↑"),
      qiblaBearing: (defaults?.string(forKey: "\(paramPrefix).qiblaBearing") ?? "حدّد موقعك"),
      qiblaDistance: (defaults?.string(forKey: "\(paramPrefix).qiblaDistance") ?? "افتح مشكاة للبوصلة الحية"),
    )
  }

  static func previewFromUserDefaults(_ defaults: UserDefaults?) -> QiblaWidgetData {
    return QiblaWidgetData(
      qiblaBearingDegrees: (defaults?.object(forKey: "\(paramPrefix).qiblaBearingDegrees") as? NSNumber)?.doubleValue ?? 277,
      qiblaArrow: (defaults?.string(forKey: "\(paramPrefix).qiblaArrow") ?? "↗"),
      qiblaBearing: (defaults?.string(forKey: "\(paramPrefix).qiblaBearing") ?? "٢٧٧° شمال غربي"),
      qiblaDistance: (defaults?.string(forKey: "\(paramPrefix).qiblaDistance") ?? "٨٢٣ كم إلى الكعبة"),
    )
  }
}


// Each widget is its own extension target; keep these helpers local to its source.
private func widgetColorScheme(_ system: ColorScheme) -> ColorScheme {
  switch UserDefaults(suiteName: "group.com.dakomn.mishkatapp.widgets")?.string(forKey: "widgetTheme") {
  case "light": return .light
  case "dark": return .dark
  default: return system
  }
}

private extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}
