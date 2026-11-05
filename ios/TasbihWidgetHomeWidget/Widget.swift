// CUSTOMIZED native widget. Maintain by hand; see docs/HOME_WIDGETS.md.
//
// App Group ID used here: TasbihWidgetHomeWidgetFlavor.appGroupId

import SwiftUI
import WidgetKit

enum TasbihWidgetHomeWidgetFlavor {
  static let appGroupId = "group.com.dakomn.mishkatapp.widgets"
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> TasbihWidgetHomeWidgetEntry {
    TasbihWidgetHomeWidgetEntry(date: Date(), data: TasbihWidgetData.previewFromUserDefaults(nil))
  }

  func getSnapshot(in context: Context, completion: @escaping (TasbihWidgetHomeWidgetEntry) -> Void) {
    if context.isPreview {
      let prefs: UserDefaults? = UserDefaults(suiteName: TasbihWidgetHomeWidgetFlavor.appGroupId)
      let data = TasbihWidgetData.previewFromUserDefaults(prefs)
      completion(TasbihWidgetHomeWidgetEntry(date: Date(), data: data))
      return
    }

    let prefs = UserDefaults(suiteName: TasbihWidgetHomeWidgetFlavor.appGroupId)
    let data = TasbihWidgetData.fromUserDefaults(prefs)

    completion(TasbihWidgetHomeWidgetEntry(date: Date(), data: data))

  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let prefs = UserDefaults(suiteName: TasbihWidgetHomeWidgetFlavor.appGroupId)
    let timedEntries = TasbihWidgetData.loadTimedEntries(prefs)
    let now = Date()
    var entries: [TasbihWidgetHomeWidgetEntry] = [
      TasbihWidgetHomeWidgetEntry(
        date: now,
        data: TasbihWidgetData.fromUserDefaults(prefs, at: now, timedEntries: timedEntries)
      )
    ]
    for timedEntry in timedEntries where timedEntry.date > now {
      entries.append(
        TasbihWidgetHomeWidgetEntry(
          date: timedEntry.date,
          data: TasbihWidgetData.fromUserDefaults(prefs, at: timedEntry.date, timedEntries: timedEntries)
        )
      )
    }
    completion(Timeline(entries: entries, policy: .atEnd))

  }
}

struct TasbihWidgetHomeWidgetEntry: TimelineEntry {
  let date: Date
  let data: TasbihWidgetData
}


struct TasbihWidgetHomeWidgetEntryView: View {
  var entry: Provider.Entry
  @Environment(\.colorScheme) private var systemColorScheme

  private var colorScheme: ColorScheme {
    let preference = UserDefaults(suiteName: TasbihWidgetHomeWidgetFlavor.appGroupId)?
      .string(forKey: "widgetTheme")
    switch preference {
    case "light": return .light
    case "dark": return .dark
    default: return systemColorScheme
    }
  }
  private var accent: Color { colorScheme == .dark ? Color(hex: 0xD7B8EE) : Color(hex: 0x795597) }
  private var secondary: Color { colorScheme == .dark ? Color(hex: 0xBBA8C9) : Color(hex: 0x887095) }
  private var primary: Color { colorScheme == .dark ? Color(hex: 0xFBF5FF) : Color(hex: 0x3B2949) }

  var body: some View {
    GeometryReader { geometry in
      let ringSize = min(72, max(48, geometry.size.height - 70))
      VStack(spacing: 3) {
      HStack(spacing: 5) {
        Spacer(minLength: 0)
        Text("مِشكاة · المسبحة").font(.system(size: 10, weight: .semibold))
        Image(systemName: "circle.dotted").font(.system(size: 11, weight: .medium))
          .accessibilityHidden(true)
      }
      .foregroundColor(secondary)
      Text(entry.data.tasbihDhikr ?? "سبحان الله")
        .font(.system(size: 12, weight: .semibold)).foregroundColor(primary)
        .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center)
      Spacer(minLength: 0)
      ZStack {
        Circle().stroke(accent.opacity(0.22), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6]))
        Circle().trim(from: 0, to: entry.data.tasbihProgressValue)
          .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
          .rotationEffect(.degrees(-90))
        VStack(spacing: 0) {
          Text(entry.data.tasbihCount ?? "٠")
            .font(.system(size: ringSize < 60 ? 23 : 29, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundColor(primary).lineLimit(1).minimumScaleFactor(0.6)
          Text(entry.data.tasbihTarget ?? "الهدف ٣٣")
            .font(.system(size: 8, weight: .medium)).foregroundColor(secondary)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 7)
      }
      .frame(width: ringSize, height: ringSize)
      .accessibilityElement(children: .combine)
      if geometry.size.height >= 128 {
        Spacer(minLength: 0)
        Text(entry.data.tasbihToday ?? "اليوم ٠ تسبيحة")
          .font(.system(size: 9, weight: .medium)).foregroundColor(secondary)
          .lineLimit(1).minimumScaleFactor(0.75)
      }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .applyContainerBackground(colorScheme == .dark ? Color(hex: 0x271E30) : Color(hex: 0xF8F3FC))
    .widgetURL(URL(string: "mishkat://tasbih?homeWidget"))
  }
}

struct TasbihWidgetHomeWidget: Widget {
  let kind: String = "TasbihWidgetHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      TasbihWidgetHomeWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("المسبحة")
    .description("ذكرك الحالي وعدّادك وهدفك في لمحة")
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

struct TasbihWidgetData {
  let tasbihProgressValue: Double
  let tasbihDhikr: String?
  let tasbihCount: String?
  let tasbihTarget: String?
  let tasbihAction: String?
  let tasbihToday: String?

  static let paramPrefix = "home_widget.TasbihWidget"

  static func fromUserDefaults(
    _ defaults: UserDefaults?,
    at date: Date = Date(),
    timedEntries: [(date: Date, values: [String: Any])]? = nil
  ) -> TasbihWidgetData {
    let timedValues = activeTimedValues(timedEntries ?? loadTimedEntries(defaults), at: date)
    return TasbihWidgetData(
      tasbihProgressValue: min(1, max(0, defaults?.double(forKey: "\(paramPrefix).tasbihProgressValue") ?? 0)),
      tasbihDhikr: (defaults?.string(forKey: "\(paramPrefix).tasbihDhikr") ?? "سبحان الله"),
      tasbihCount: (defaults?.string(forKey: "\(paramPrefix).tasbihCount") ?? "٠"),
      tasbihTarget: (defaults?.string(forKey: "\(paramPrefix).tasbihTarget") ?? "الهدف ٣٣"),
      tasbihAction: (defaults?.string(forKey: "\(paramPrefix).tasbihAction") ?? "اضغط لفتح المسبحة"),
      tasbihToday: (timedValues["tasbihToday"] as? String) ?? "اليوم ٠ تسبيحة",
    )
  }

  static func previewFromUserDefaults(
    _ defaults: UserDefaults?,
    at date: Date = Date(),
    timedEntries: [(date: Date, values: [String: Any])]? = nil
  ) -> TasbihWidgetData {
    let timedValues = activeTimedValues(timedEntries ?? loadTimedEntries(defaults), at: date)
    return TasbihWidgetData(
      tasbihProgressValue: min(1, max(0, (defaults?.object(forKey: "\(paramPrefix).tasbihProgressValue") as? NSNumber)?.doubleValue ?? (24.0 / 33.0))),
      tasbihDhikr: (defaults?.string(forKey: "\(paramPrefix).tasbihDhikr") ?? "سبحان الله"),
      tasbihCount: (defaults?.string(forKey: "\(paramPrefix).tasbihCount") ?? "٢٤"),
      tasbihTarget: (defaults?.string(forKey: "\(paramPrefix).tasbihTarget") ?? "الهدف ٣٣"),
      tasbihAction: (defaults?.string(forKey: "\(paramPrefix).tasbihAction") ?? "اضغط لفتح المسبحة"),
      tasbihToday: (timedValues["tasbihToday"] as? String) ?? "اليوم ٩٠ تسبيحة",
    )
  }

  fileprivate static func loadTimedEntries(_ defaults: UserDefaults?) -> [(date: Date, values: [String: Any])] {
    guard let path = defaults?.string(forKey: "\(paramPrefix).timedData") else { return [] }
    guard FileManager.default.fileExists(atPath: path) else { return [] }
    do {
      let raw = try Data(contentsOf: URL(fileURLWithPath: path))
      guard let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return [] }
      var entries: [(date: Date, values: [String: Any])] = []
      for (key, value) in json {
        guard let millis = Double(key), let values = value as? [String: Any] else { continue }
        entries.append((date: Date(timeIntervalSince1970: millis / 1000), values: values))
      }
      entries.sort { $0.date < $1.date }
      return entries
    } catch {
      return []
    }
  }

  fileprivate static func activeTimedValues(_ entries: [(date: Date, values: [String: Any])], at date: Date) -> [String: Any] {
    var values: [String: Any] = [:]
    for entry in entries {
      if entry.date > date { break }
      values = entry.values
    }
    return values
  }
}


private extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}
