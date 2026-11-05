// CUSTOMIZED NATIVE WIDGET — preserve when regenerating Dart declarations.
// See docs/HOME_WIDGETS.md for native rendering and the shared data contract.
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
  @Environment(\.colorScheme) private var systemColorScheme
  @Environment(\.widgetFamily) private var family
  private var colorScheme: ColorScheme { widgetColorScheme(systemColorScheme) }
  private var accent: Color { colorScheme == .dark ? Color(hex: 0x91DDC0) : Color(hex: 0x276C5D) }
  private var secondary: Color { colorScheme == .dark ? Color(hex: 0xADBBB5) : Color(hex: 0x60716B) }
  private var surface: Color { colorScheme == .dark ? Color(hex: 0x1D3930) : Color(hex: 0xDDEDE7) }

  var body: some View {
    Group {
      if #available(iOSApplicationExtension 16.0, *) {
        switch family {
        case .accessoryRectangular, .accessoryCircular, .accessoryInline:
          PrayerLockScreenView(entry: entry, family: family)
        default:
          homeScreenContent
        }
      } else {
        homeScreenContent
      }
    }
    .widgetURL(URL(string: "mishkat://prayer?homeWidget"))
  }

  private var homeScreenContent: some View {
    VStack(alignment: .trailing, spacing: 8) {
      HStack {
        Text(entry.data.prayerCity ?? "").font(.system(size: 11)).foregroundColor(secondary).lineLimit(1)
        Spacer(minLength: 8)
        Text("مِشكاة • الصلاة").font(.system(size: 11, weight: .bold)).foregroundColor(accent)
          .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(surface))
      }
      Spacer(minLength: 0)
      HStack(alignment: .center, spacing: 12) {
        VStack(spacing: 4) {
          Text("متبقي").font(.system(size: 10, weight: .medium)).foregroundColor(secondary)
          if let target = entry.data.prayerNextAt, target > entry.date {
            // WidgetKit owns this clock, so seconds advance with the app closed.
            // A bounded timer stops at zero instead of counting upward after expiry.
            if #available(iOSApplicationExtension 16.0, *) {
              Text(timerInterval: entry.date...target, countsDown: true, showsHours: true)
                .font(.system(size: 25, weight: .bold, design: .monospaced)).monospacedDigit()
                .foregroundColor(accent).multilineTextAlignment(.center)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.layoutDirection, .leftToRight)
            } else {
              Text(target, style: .timer)
                .font(.system(size: 25, weight: .bold, design: .monospaced)).monospacedDigit()
                .foregroundColor(accent).multilineTextAlignment(.center)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.layoutDirection, .leftToRight)
            }
          } else {
            Text(entry.data.prayerRemaining ?? "افتح مشكاة لتحديث المواقيت")
              .font(.system(size: 11)).foregroundColor(secondary).multilineTextAlignment(.center)
          }
        }
        .frame(width: 128).padding(.vertical, 9).background(RoundedRectangle(cornerRadius: 14).fill(surface))
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 2) {
          Text("الصلاة القادمة").font(.system(size: 10)).foregroundColor(secondary)
          Text(entry.data.prayerNextName ?? "—").font(.system(size: 23, weight: .heavy)).foregroundColor(colorScheme == .dark ? Color(hex: 0xF3F8F5) : Color(hex: 0x17362F)).lineLimit(1)
          Text(entry.data.prayerNextTime ?? "—").font(.system(size: 12, weight: .bold)).foregroundColor(accent)
        }
      }
      Spacer(minLength: 0)
      Text(entry.data.prayerUpcoming ?? "")
        .font(.system(size: 10, weight: .medium)).foregroundColor(secondary).lineLimit(1).minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(surface))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .applyContainerBackground(colorScheme == .dark ? Color(hex: 0x10211B) : Color(hex: 0xF3F8F5))
  }
}

// Lock Screen accessories inherit the system's monochrome/tint rendering.
// They deliberately do not read the Home Screen widgetTheme preference.
@available(iOSApplicationExtension 16.0, *)
private struct PrayerLockScreenView: View {
  let entry: PrayerTimesWidgetHomeWidgetEntry
  let family: WidgetFamily
  @Environment(\.isLuminanceReduced) private var isLuminanceReduced

  private var target: Date? {
    guard let date = entry.data.prayerNextAt, date > entry.date else { return nil }
    return date
  }
  private var name: String { entry.data.prayerNextName ?? "الصلاة القادمة" }
  private var time: String { entry.data.prayerNextTime ?? "—" }
  private var updatePrompt: String {
    (entry.data.prayerCity ?? "").hasPrefix("حدّد")
      ? "حدّد موقعك في مشكاة"
      : "افتح مشكاة للتحديث"
  }

  var body: some View {
    Group {
      switch family {
      case .accessoryInline:
        inlineContent
      case .accessoryCircular:
        circularContent
      default:
        rectangularContent
      }
    }
    .applyContainerBackground(Color.clear)
  }

  private var inlineContent: some View {
    // AccessoryInline supports one line of text and one optional image.
    Label {
      Text(target == nil ? updatePrompt : "\(name) · \(time)")
    } icon: {
      Image(systemName: "clock")
    }
  }

  private var circularContent: some View {
    ZStack {
      AccessoryWidgetBackground()
      if target != nil {
        VStack(spacing: 1) {
          Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
          Text(time).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .minimumScaleFactor(0.7).multilineTextAlignment(.center).padding(5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name)، \(time)")
      } else {
        VStack(spacing: 1) {
          Image(systemName: "clock").font(.system(size: 12))
          Text("افتح مشكاة").font(.system(size: 10, weight: .medium)).lineLimit(2)
        }
        .multilineTextAlignment(.center).padding(5)
        .accessibilityLabel(updatePrompt)
      }
    }
  }

  private var rectangularContent: some View {
    VStack(alignment: .trailing, spacing: 2) {
      if let target {
        if isLuminanceReduced {
          // Always On may lower its refresh rate; the scheduled time stays precise.
          Label(name, systemImage: "clock")
            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
          Text(time).font(.system(size: 23, weight: .semibold)).lineLimit(1)
          Text("الصلاة القادمة").font(.system(size: 10, weight: .medium))
        } else {
          HStack(spacing: 4) {
            Text(time).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Image(systemName: "clock").font(.system(size: 11)).accessibilityHidden(true)
          }
          .minimumScaleFactor(0.8)
          Text(timerInterval: entry.date...target, countsDown: true, showsHours: true)
            .font(.system(size: 23, weight: .semibold, design: .monospaced))
            .monospacedDigit().multilineTextAlignment(.trailing)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.layoutDirection, .leftToRight)
          Text("متبقي").font(.system(size: 10, weight: .medium))
        }
      } else {
        Label("مِشكاة · الصلاة", systemImage: "clock")
          .font(.system(size: 13, weight: .semibold))
        Text(updatePrompt).font(.system(size: 11)).lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
  }
}

struct PrayerTimesWidgetHomeWidget: Widget {
  let kind: String = "PrayerTimesWidgetHomeWidget"

  private var families: [WidgetFamily] {
    if #available(iOSApplicationExtension 16.0, *) {
      return [.systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline]
    }
    return [.systemMedium]
  }

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      PrayerTimesWidgetHomeWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("مواقيت الصلاة")
    .description("الصلاة القادمة والوقت المتبقي على الشاشة الرئيسية وشاشة القفل")
    .supportedFamilies(families)
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
  let prayerNextAt: Date?
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
      prayerNextAt: prayerDate(timedValues["prayerNextAt"]),
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
      prayerNextAt: prayerDate(timedValues["prayerNextAt"]) ?? date.addingTimeInterval(2910),
      prayerCity: (defaults?.string(forKey: "\(paramPrefix).prayerCity") ?? "مكة المكرمة"),
      prayerRemaining: (timedValues["prayerRemaining"] as? String) ?? "48:30",
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
    guard let target = prayerDate(values["prayerNextAt"]), target > date else {
      return ["prayerRemaining": "افتح مشكاة لتحديث المواقيت"]
    }
    return values
  }
}


private func prayerDate(_ value: Any?) -> Date? {
  guard let milliseconds = value as? NSNumber, milliseconds.doubleValue > 0 else { return nil }
  return Date(timeIntervalSince1970: milliseconds.doubleValue / 1000)
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
