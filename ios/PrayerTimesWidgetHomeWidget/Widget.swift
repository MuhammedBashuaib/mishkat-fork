// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Placeholder SwiftUI widget.
//
// App Group ID used here: PrayerTimesWidgetHomeWidgetFlavor.appGroupId

import SwiftUI
import WidgetKit

enum PrayerTimesWidgetHomeWidgetFlavor {
  static let appGroupId = "group.com.dakomn.mishkatapp.widgets"
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> PrayerTimesWidgetHomeWidgetEntry {
    PrayerTimesWidgetHomeWidgetEntry(date: Date(), data: PrayerTimesWidgetData.previewFromUserDefaults(nil))
  }

  func getSnapshot(in context: Context, completion: @escaping (PrayerTimesWidgetHomeWidgetEntry) -> Void) {
    if context.isPreview {
      let prefs: UserDefaults? = UserDefaults(suiteName: PrayerTimesWidgetHomeWidgetFlavor.appGroupId)
      let data = PrayerTimesWidgetData.previewFromUserDefaults(prefs)
      completion(PrayerTimesWidgetHomeWidgetEntry(date: Date(), data: data))
      return
    }

    let prefs = UserDefaults(suiteName: PrayerTimesWidgetHomeWidgetFlavor.appGroupId)
    let data = PrayerTimesWidgetData.fromUserDefaults(prefs)

    completion(PrayerTimesWidgetHomeWidgetEntry(date: Date(), data: data))

  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let prefs = UserDefaults(suiteName: PrayerTimesWidgetHomeWidgetFlavor.appGroupId)
    let timedEntries = PrayerTimesWidgetData.loadTimedEntries(prefs)
    let now = Date()
    var entries: [PrayerTimesWidgetHomeWidgetEntry] = [
      PrayerTimesWidgetHomeWidgetEntry(
        date: now,
        data: PrayerTimesWidgetData.fromUserDefaults(prefs, at: now, timedEntries: timedEntries)
      )
    ]
    for timedEntry in timedEntries where timedEntry.date > now {
      entries.append(
        PrayerTimesWidgetHomeWidgetEntry(
          date: timedEntry.date,
          data: PrayerTimesWidgetData.fromUserDefaults(prefs, at: timedEntry.date, timedEntries: timedEntries)
        )
      )
    }
    completion(Timeline(entries: entries, policy: .atEnd))

  }
}

struct PrayerTimesWidgetHomeWidgetEntry: TimelineEntry {
  let date: Date
  let data: PrayerTimesWidgetData
}


struct PrayerTimesWidgetHomeWidgetEntryView: View {
  var entry: Provider.Entry

  @Environment(\.colorScheme) var colorScheme

  var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text(entry.data.prayerCity ?? "")
                    .font(.system(size: 11.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.6784313725490196, green: 0.7333333333333333, blue: 0.7098039215686275, opacity: 1.0) : Color(red: 0.3764705882352941, green: 0.44313725490196076, blue: 0.4196078431372549, opacity: 1.0)))
                    .multilineTextAlignment(.trailing)
                Spacer(minLength: 0)
                Text("مِشكاة • الصلاة")
                    .font(.system(size: 12.0, weight: .bold)).foregroundColor((colorScheme == .dark ? Color(red: 0.5686274509803921, green: 0.8666666666666667, blue: 0.7529411764705882, opacity: 1.0) : Color(red: 0.15294117647058825, green: 0.4235294117647059, blue: 0.36470588235294116, opacity: 1.0)))
                    .multilineTextAlignment(.trailing)
                .padding(EdgeInsets(top: 3.0, leading: 8.0, bottom: 3.0, trailing: 8.0))
                .background(RoundedRectangle(cornerRadius: 999.0).fill((colorScheme == .dark ? Color(red: 0.11372549019607843, green: 0.2235294117647059, blue: 0.18823529411764706, opacity: 1.0) : Color(red: 0.8666666666666667, green: 0.9294117647058824, blue: 0.9058823529411765, opacity: 1.0))))
            }
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.data.prayerRemaining ?? "")
                        .font(.system(size: 11.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.6784313725490196, green: 0.7333333333333333, blue: 0.7098039215686275, opacity: 1.0) : Color(red: 0.3764705882352941, green: 0.44313725490196076, blue: 0.4196078431372549, opacity: 1.0)))
                        .multilineTextAlignment(.trailing)
                    .padding(EdgeInsets(top: 7.0, leading: 10.0, bottom: 7.0, trailing: 10.0))
                    .background(RoundedRectangle(cornerRadius: 12.0).fill((colorScheme == .dark ? Color(red: 0.11372549019607843, green: 0.2235294117647059, blue: 0.18823529411764706, opacity: 1.0) : Color(red: 0.8666666666666667, green: 0.9294117647058824, blue: 0.9058823529411765, opacity: 1.0))))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("الصلاة القادمة")
                        .font(.system(size: 11.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.6784313725490196, green: 0.7333333333333333, blue: 0.7098039215686275, opacity: 1.0) : Color(red: 0.3764705882352941, green: 0.44313725490196076, blue: 0.4196078431372549, opacity: 1.0)))
                        .multilineTextAlignment(.trailing)
                    Text(entry.data.prayerNextName ?? "")
                        .font(.system(size: 22.0, weight: .heavy)).foregroundColor((colorScheme == .dark ? Color(red: 0.9529411764705882, green: 0.9725490196078431, blue: 0.9607843137254902, opacity: 1.0) : Color(red: 0.09019607843137255, green: 0.21176470588235294, blue: 0.1843137254901961, opacity: 1.0)))
                        .multilineTextAlignment(.trailing)
                    Text(entry.data.prayerNextTime ?? "")
                        .font(.system(size: 12.0, weight: .bold)).foregroundColor((colorScheme == .dark ? Color(red: 0.5686274509803921, green: 0.8666666666666667, blue: 0.7529411764705882, opacity: 1.0) : Color(red: 0.15294117647058825, green: 0.4235294117647059, blue: 0.36470588235294116, opacity: 1.0)))
                        .multilineTextAlignment(.trailing)
                }
            }
            Spacer(minLength: 0)
            Text(entry.data.prayerUpcoming ?? "")
                .font(.system(size: 11.0, weight: .semibold)).foregroundColor((colorScheme == .dark ? Color(red: 0.6784313725490196, green: 0.7333333333333333, blue: 0.7098039215686275, opacity: 1.0) : Color(red: 0.3764705882352941, green: 0.44313725490196076, blue: 0.4196078431372549, opacity: 1.0)))
                .multilineTextAlignment(.trailing)
            .padding(EdgeInsets(top: 5.0, leading: 9.0, bottom: 5.0, trailing: 9.0))
            .background(RoundedRectangle(cornerRadius: 10.0).fill((colorScheme == .dark ? Color(red: 0.11372549019607843, green: 0.2235294117647059, blue: 0.18823529411764706, opacity: 1.0) : Color(red: 0.8666666666666667, green: 0.9294117647058824, blue: 0.9058823529411765, opacity: 1.0))))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    .applyContainerBackground((colorScheme == .dark ? Color(red: 0.06274509803921569, green: 0.12941176470588237, blue: 0.10588235294117647, opacity: 1.0) : Color(red: 0.9529411764705882, green: 0.9725490196078431, blue: 0.9607843137254902, opacity: 1.0)))
    .widgetURL(URL(string: "mishkat://prayer?homeWidget"))
  }
}

struct PrayerTimesWidgetHomeWidget: Widget {
  let kind: String = "PrayerTimesWidgetHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      PrayerTimesWidgetHomeWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("مواقيت الصلاة")
    .description("الصلاة القادمة ومواقيت اليوم من مشكاة")
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

struct PrayerTimesWidgetData {
  let prayerCity: String?
  let prayerRemaining: String?
  let prayerNextName: String?
  let prayerNextTime: String?
  let prayerUpcoming: String?

  static let paramPrefix = "home_widget.PrayerTimesWidget"

  static func fromUserDefaults(
    _ defaults: UserDefaults?,
    at date: Date = Date(),
    timedEntries: [(date: Date, values: [String: Any])]? = nil
  ) -> PrayerTimesWidgetData {
    let timedValues = activeTimedValues(timedEntries ?? loadTimedEntries(defaults), at: date)
    return PrayerTimesWidgetData(
      prayerCity: (defaults?.string(forKey: "\(paramPrefix).prayerCity") ?? "حدّد موقعك في مشكاة"),
      prayerRemaining: (timedValues["prayerRemaining"] as? String) ?? "افتح مشكاة لتحديث المواقيت",
      prayerNextName: (timedValues["prayerNextName"] as? String) ?? "—",
      prayerNextTime: (timedValues["prayerNextTime"] as? String) ?? "—",
      prayerUpcoming: (timedValues["prayerUpcoming"] as? String) ?? "تظهر المواقيت بعد تحديد الموقع",
    )
  }

  static func previewFromUserDefaults(
    _ defaults: UserDefaults?,
    at date: Date = Date(),
    timedEntries: [(date: Date, values: [String: Any])]? = nil
  ) -> PrayerTimesWidgetData {
    let timedValues = activeTimedValues(timedEntries ?? loadTimedEntries(defaults), at: date)
    return PrayerTimesWidgetData(
      prayerCity: (defaults?.string(forKey: "\(paramPrefix).prayerCity") ?? "مكة المكرمة"),
      prayerRemaining: (timedValues["prayerRemaining"] as? String) ?? "متبقي نحو ساعتين",
      prayerNextName: (timedValues["prayerNextName"] as? String) ?? "المغرب",
      prayerNextTime: (timedValues["prayerNextTime"] as? String) ?? "٥:٤٢ م",
      prayerUpcoming: (timedValues["prayerUpcoming"] as? String) ?? "العصر ٣:٢١  •  المغرب ٥:٤٢  •  العشاء ٧:١٢",
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

