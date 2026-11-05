// CUSTOMIZED NATIVE WIDGET — preserve when regenerating Dart declarations.
// See docs/HOME_WIDGETS.md for native rendering and the shared data contract.
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
  @Environment(\.colorScheme) private var systemColorScheme
  private var colorScheme: ColorScheme { widgetColorScheme(systemColorScheme) }
  private var accent: Color { colorScheme == .dark ? Color(hex: 0x72D4A3) : Color(hex: 0x238661) }
  private var secondary: Color { colorScheme == .dark ? Color(hex: 0xA9C5B9) : Color(hex: 0x61776B) }
  private var primary: Color { colorScheme == .dark ? Color(hex: 0xF2F8F4) : Color(hex: 0x233D30) }
  private var hasPlan: Bool { !(entry.data.wirdPages ?? "ابدأ").hasPrefix("ابدأ") }
  private var percentage: String {
    let digits = Array("٠١٢٣٤٥٦٧٨٩")
    let number = String(Int((entry.data.wirdProgressValue * 100).rounded()))
    return String(number.map { digits[$0.wholeNumberValue ?? 0] }) + "٪"
  }

  var body: some View {
    VStack(alignment: .trailing, spacing: 7) {
      HStack(spacing: 6) {
        Text(entry.data.wirdName ?? "رحلتك مع القرآن")
          .font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
        Spacer(minLength: 10)
        Text("مِشكاة · الورد اليومي").font(.system(size: 10, weight: .semibold))
        Image(systemName: "book.closed.fill").font(.system(size: 10, weight: .medium))
          .accessibilityHidden(true)
      }
      .foregroundColor(secondary)
      HStack(alignment: .center, spacing: 16) {
        if hasPlan {
          VStack(spacing: 0) {
            Text(percentage).font(.system(size: 38, weight: .bold, design: .rounded))
              .monospacedDigit().foregroundColor(accent).lineLimit(1).minimumScaleFactor(0.7)
            Text("من الختمة").font(.system(size: 10)).foregroundColor(secondary)
          }
          .frame(minWidth: 76)
        } else {
          Image(systemName: "book.closed")
            .font(.system(size: 32, weight: .light)).foregroundColor(accent.opacity(0.75))
            .accessibilityHidden(true)
            .frame(width: 60)
        }
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 4) {
          Text(entry.data.wirdPages ?? "ابدأ ختمتك الأولى")
            .font(.system(size: 22, weight: .bold)).foregroundColor(primary)
          Text(entry.data.wirdDetail ?? "حدّد خطتك ليظهر وردك هنا")
            .font(.system(size: 10)).foregroundColor(secondary)
        }
        .lineLimit(1).minimumScaleFactor(0.75)
      }
      .frame(maxHeight: .infinity)
      progressLine
      HStack {
        Text(hasPlan ? entry.data.wirdRemainingPages : "خطوة صغيرة كل يوم")
          .foregroundColor(secondary)
        Spacer(minLength: 6)
        Text(hasPlan ? entry.data.wirdCompletedPages : "رحلتك تبدأ بصفحة")
          .foregroundColor(accent)
      }
      .font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .applyContainerBackground(colorScheme == .dark ? Color(hex: 0x152923) : Color(hex: 0xF2F7F3))
    .widgetURL(URL(string: "mishkat://wird?homeWidget"))
  }

  private var progressLine: some View {
    GeometryReader { geometry in
      ZStack(alignment: .trailing) {
        Capsule().fill(colorScheme == .dark ? Color(hex: 0x355449) : Color(hex: 0xD5E5DC))
        Capsule().fill(accent).frame(width: geometry.size.width * entry.data.wirdProgressValue)
      }
    }
    .frame(height: 5)
    .accessibilityLabel("تقدم الختمة")
    .accessibilityValue(entry.data.wirdProgress ?? "")
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
  let wirdProgressValue: Double
  let wirdCompletedPages: String
  let wirdRemainingPages: String
  let wirdName: String?
  let wirdPages: String?
  let wirdDetail: String?
  let wirdProgress: String?
  let wirdAction: String?

  static let paramPrefix = "home_widget.WirdWidget"

  static func fromUserDefaults(_ defaults: UserDefaults?) -> WirdWidgetData {
    return WirdWidgetData(
      wirdProgressValue: min(1, max(0, defaults?.double(forKey: "\(paramPrefix).wirdProgressValue") ?? 0)),
      wirdCompletedPages: defaults?.string(forKey: "\(paramPrefix).wirdCompletedPages") ?? "",
      wirdRemainingPages: defaults?.string(forKey: "\(paramPrefix).wirdRemainingPages") ?? "",
      wirdName: (defaults?.string(forKey: "\(paramPrefix).wirdName") ?? "رحلتك مع القرآن"),
      wirdPages: (defaults?.string(forKey: "\(paramPrefix).wirdPages") ?? "ابدأ ختمتك الأولى"),
      wirdDetail: (defaults?.string(forKey: "\(paramPrefix).wirdDetail") ?? "حدّد خطتك ليظهر وردك هنا"),
      wirdProgress: (defaults?.string(forKey: "\(paramPrefix).wirdProgress") ?? "خطوة صغيرة كل يوم"),
      wirdAction: (defaults?.string(forKey: "\(paramPrefix).wirdAction") ?? "اضغط لإنشاء خطة"),
    )
  }

  static func previewFromUserDefaults(_ defaults: UserDefaults?) -> WirdWidgetData {
    return WirdWidgetData(
      wirdProgressValue: min(1, max(0, (defaults?.object(forKey: "\(paramPrefix).wirdProgressValue") as? NSNumber)?.doubleValue ?? (41.0 / 604.0))),
      wirdCompletedPages: defaults?.string(forKey: "\(paramPrefix).wirdCompletedPages") ?? "أنجزت ٤١ صفحة",
      wirdRemainingPages: defaults?.string(forKey: "\(paramPrefix).wirdRemainingPages") ?? "باقي ٥٦٣ صفحة",
      wirdName: (defaults?.string(forKey: "\(paramPrefix).wirdName") ?? "ختمتي"),
      wirdPages: (defaults?.string(forKey: "\(paramPrefix).wirdPages") ?? "صفحة ٤٢ – ٦٢"),
      wirdDetail: (defaults?.string(forKey: "\(paramPrefix).wirdDetail") ?? "٢١ صفحة في وردك الحالي"),
      wirdProgress: (defaults?.string(forKey: "\(paramPrefix).wirdProgress") ?? "٧٪ من الختمة"),
      wirdAction: (defaults?.string(forKey: "\(paramPrefix).wirdAction") ?? "اضغط لمتابعة القراءة"),
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
