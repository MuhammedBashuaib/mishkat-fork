// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Placeholder SwiftUI widget.
//
// App Group ID used here: AdhkarWidgetHomeWidgetFlavor.appGroupId

import SwiftUI
import WidgetKit

enum AdhkarWidgetHomeWidgetFlavor {
  static let appGroupId = "group.com.dakomn.mishkatapp.widgets"
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> AdhkarWidgetHomeWidgetEntry {
    AdhkarWidgetHomeWidgetEntry(date: Date(), data: AdhkarWidgetData.previewFromUserDefaults(nil))
  }

  func getSnapshot(in context: Context, completion: @escaping (AdhkarWidgetHomeWidgetEntry) -> Void) {
    if context.isPreview {
      let prefs: UserDefaults? = UserDefaults(suiteName: AdhkarWidgetHomeWidgetFlavor.appGroupId)
      let data = AdhkarWidgetData.previewFromUserDefaults(prefs)
      completion(AdhkarWidgetHomeWidgetEntry(date: Date(), data: data))
      return
    }

    let prefs = UserDefaults(suiteName: AdhkarWidgetHomeWidgetFlavor.appGroupId)
    let data = AdhkarWidgetData.fromUserDefaults(prefs)

    completion(AdhkarWidgetHomeWidgetEntry(date: Date(), data: data))

  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let prefs = UserDefaults(suiteName: AdhkarWidgetHomeWidgetFlavor.appGroupId)
    let timedEntries = AdhkarWidgetData.loadTimedEntries(prefs)
    let now = Date()
    var entries: [AdhkarWidgetHomeWidgetEntry] = [
      AdhkarWidgetHomeWidgetEntry(
        date: now,
        data: AdhkarWidgetData.fromUserDefaults(prefs, at: now, timedEntries: timedEntries)
      )
    ]
    for timedEntry in timedEntries where timedEntry.date > now {
      entries.append(
        AdhkarWidgetHomeWidgetEntry(
          date: timedEntry.date,
          data: AdhkarWidgetData.fromUserDefaults(prefs, at: timedEntry.date, timedEntries: timedEntries)
        )
      )
    }
    completion(Timeline(entries: entries, policy: .atEnd))

  }
}

struct AdhkarWidgetHomeWidgetEntry: TimelineEntry {
  let date: Date
  let data: AdhkarWidgetData
}


struct AdhkarWidgetHomeWidgetEntryView: View {
  var entry: Provider.Entry

  @Environment(\.colorScheme) var colorScheme

  var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text(entry.data.dhikrCount ?? "")
                    .font(.system(size: 10.0, weight: .bold)).foregroundColor((colorScheme == .dark ? Color(red: 0.9098039215686274, green: 0.7568627450980392, blue: 0.6235294117647059, opacity: 1.0) : Color(red: 0.5450980392156862, green: 0.36470588235294116, blue: 0.2627450980392157, opacity: 1.0)))
                .padding(EdgeInsets(top: 4.0, leading: 9.0, bottom: 4.0, trailing: 9.0))
                .background(RoundedRectangle(cornerRadius: 999.0).fill((colorScheme == .dark ? Color(red: 0.23137254901960785, green: 0.17254901960784313, blue: 0.15294117647058825, opacity: 1.0) : Color(red: 0.9529411764705882, green: 0.9019607843137255, blue: 0.8705882352941177, opacity: 1.0))))
                Spacer(minLength: 0)
                Text(entry.data.dhikrCategory ?? "")
                    .font(.system(size: 12.0, weight: .heavy)).foregroundColor((colorScheme == .dark ? Color(red: 0.9098039215686274, green: 0.7568627450980392, blue: 0.6235294117647059, opacity: 1.0) : Color(red: 0.5450980392156862, green: 0.36470588235294116, blue: 0.2627450980392157, opacity: 1.0)))
                    .multilineTextAlignment(.trailing)
            }
            Spacer(minLength: 0)
            Text(entry.data.dhikrText ?? "")
                .font(.system(size: 15.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.9686274509803922, green: 0.9333333333333333, blue: 0.9098039215686274, opacity: 1.0) : Color(red: 0.24313725490196078, green: 0.17254901960784313, blue: 0.1411764705882353, opacity: 1.0)))
                .multilineTextAlignment(.trailing)
            .padding(EdgeInsets(top: 8.0, leading: 11.0, bottom: 8.0, trailing: 11.0))
            .background(RoundedRectangle(cornerRadius: 14.0).fill((colorScheme == .dark ? Color(red: 0.23137254901960785, green: 0.17254901960784313, blue: 0.15294117647058825, opacity: 1.0) : Color(red: 0.9529411764705882, green: 0.9019607843137255, blue: 0.8705882352941177, opacity: 1.0))))
            Spacer(minLength: 0)
            Text("← اضغط للمتابعة داخل مشكاة")
                .font(.system(size: 10.0)).foregroundColor((colorScheme == .dark ? Color(red: 0.7607843137254902, green: 0.6745098039215687, blue: 0.6274509803921569, opacity: 1.0) : Color(red: 0.47843137254901963, green: 0.396078431372549, blue: 0.34901960784313724, opacity: 1.0)))
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    .applyContainerBackground((colorScheme == .dark ? Color(red: 0.12941176470588237, green: 0.10196078431372549, blue: 0.09411764705882353, opacity: 1.0) : Color(red: 1.0, green: 0.9725490196078431, blue: 0.9490196078431372, opacity: 1.0)))
    .widgetURL(URL(string: "mishkat://adhkar?homeWidget"))
  }
}

struct AdhkarWidgetHomeWidget: Widget {
  let kind: String = "AdhkarWidgetHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      AdhkarWidgetHomeWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("ذِكر اليوم")
    .description("ذكر مناسب لوقتك من أذكار مشكاة")
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

struct AdhkarWidgetData {
  let dhikrCount: String?
  let dhikrCategory: String?
  let dhikrText: String?

  static let paramPrefix = "home_widget.AdhkarWidget"

  static func fromUserDefaults(
    _ defaults: UserDefaults?,
    at date: Date = Date(),
    timedEntries: [(date: Date, values: [String: Any])]? = nil
  ) -> AdhkarWidgetData {
    let timedValues = activeTimedValues(timedEntries ?? loadTimedEntries(defaults), at: date)
    return AdhkarWidgetData(
      dhikrCount: (timedValues["dhikrCount"] as? String) ?? "مرة واحدة",
      dhikrCategory: (timedValues["dhikrCategory"] as? String) ?? "ذِكر اليوم",
      dhikrText: (timedValues["dhikrText"] as? String) ?? "سبحان الله وبحمده، سبحان الله العظيم.",
    )
  }

  static func previewFromUserDefaults(
    _ defaults: UserDefaults?,
    at date: Date = Date(),
    timedEntries: [(date: Date, values: [String: Any])]? = nil
  ) -> AdhkarWidgetData {
    let timedValues = activeTimedValues(timedEntries ?? loadTimedEntries(defaults), at: date)
    return AdhkarWidgetData(
      dhikrCount: (timedValues["dhikrCount"] as? String) ?? "٣ مرات",
      dhikrCategory: (timedValues["dhikrCategory"] as? String) ?? "أذكار المساء",
      dhikrText: (timedValues["dhikrText"] as? String) ?? "رَضِيتُ بِاللَّهِ رَبًّا، وَبِالإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ ﷺ نَبِيًّا.",
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

