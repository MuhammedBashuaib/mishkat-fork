// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Placeholder SwiftUI widget.
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

  @Environment(\.colorScheme) var colorScheme

  var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text("مِشكاة • المسبحة")
                .font(.system(size: 11.0, weight: .bold)).foregroundColor((colorScheme == .dark ? Color(red: 0.8431372549019608, green: 0.7215686274509804, blue: 0.9333333333333333, opacity: 1.0) : Color(red: 0.4470588235294118, green: 0.3254901960784314, blue: 0.5294117647058824, opacity: 1.0)))
            Spacer(minLength: 0)
            VStack(alignment: .center, spacing: 0) {
                Text(entry.data.tasbihDhikr ?? "")
                    .font(.system(size: 13.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.8431372549019608, green: 0.7215686274509804, blue: 0.9333333333333333, opacity: 1.0) : Color(red: 0.4470588235294118, green: 0.3254901960784314, blue: 0.5294117647058824, opacity: 1.0)))
                    .multilineTextAlignment(.center)
                Text(entry.data.tasbihCount ?? "")
                    .font(.system(size: 36.0, weight: .heavy)).foregroundColor((colorScheme == .dark ? Color(red: 0.9647058823529412, green: 0.9568627450980393, blue: 0.9450980392156862, opacity: 1.0) : Color(red: 0.14901960784313725, green: 0.23137254901960785, blue: 0.20784313725490197, opacity: 1.0)))
                    .multilineTextAlignment(.center)
                Text(entry.data.tasbihTarget ?? "")
                    .font(.system(size: 11.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.8431372549019608, green: 0.7215686274509804, blue: 0.9333333333333333, opacity: 1.0) : Color(red: 0.4470588235294118, green: 0.3254901960784314, blue: 0.5294117647058824, opacity: 1.0)))
                    .multilineTextAlignment(.center)
                Text(entry.data.tasbihToday ?? "")
                    .font(.system(size: 11.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.8431372549019608, green: 0.7215686274509804, blue: 0.9333333333333333, opacity: 1.0) : Color(red: 0.4470588235294118, green: 0.3254901960784314, blue: 0.5294117647058824, opacity: 1.0)))
                    .multilineTextAlignment(.center)
            }
            .padding(EdgeInsets(top: 8.0, leading: 12.0, bottom: 8.0, trailing: 12.0))
            .background(RoundedRectangle(cornerRadius: 18.0).fill((colorScheme == .dark ? Color(red: 0.22745098039215686, green: 0.1607843137254902, blue: 0.27058823529411763, opacity: 1.0) : Color(red: 0.9372549019607843, green: 0.8901960784313725, blue: 0.9686274509803922, opacity: 1.0))))
            Spacer(minLength: 0)
            Text(entry.data.tasbihAction ?? "")
                .font(.system(size: 10.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.8431372549019608, green: 0.7215686274509804, blue: 0.9333333333333333, opacity: 1.0) : Color(red: 0.4470588235294118, green: 0.3254901960784314, blue: 0.5294117647058824, opacity: 1.0)))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .applyContainerBackground((colorScheme == .dark ? Color(red: 0.15294117647058825, green: 0.11764705882352941, blue: 0.18823529411764706, opacity: 1.0) : Color(red: 0.9725490196078431, green: 0.9529411764705882, blue: 0.9882352941176471, opacity: 1.0)))
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

