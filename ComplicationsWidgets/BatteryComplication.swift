import SwiftUI
import WidgetKit

/// Watch and iPhone battery as the two halves of one battery outline, with both percents inside.
struct BatteryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.battery.widgetKind, provider: BatteryProvider()) { entry in
            BatteryComplicationView(entry: entry)
                .environment(\.complicationAccent, AccentColor.current.color)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Route.battery.url)
        }
        .configurationDisplayName("Battery Outline")
        .description("Your watch's battery on the top half of the outline, your iPhone's on the bottom.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// Re-reads the battery every 30 minutes (the system may stretch that) and fills the gap with a forecast, one entry
/// per percent. Asking more often would only run through the day's reload budget sooner, leaving the system to space
/// them out anyway. The phone's reading comes from whatever the watch app last received; receiving a newer one, and
/// the Battery screen, reload this too.
struct BatteryProvider: TimelineProvider {
    func placeholder(in _: Context) -> BatteryEntry {
        BatteryEntry(date: .now, level: 0.82, phone: PhoneBatteryReading(date: .now, level: 0.64, isPluggedIn: false))
    }

    func getSnapshot(in _: Context, completion: @escaping @Sendable (BatteryEntry) -> Void) {
        Task { @MainActor in
            completion(BatteryEntry(date: .now, level: BatteryReading.current()?.level, phone: .saved()))
        }
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<BatteryEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            let entries = if let reading = BatteryReading.current() {
                BatteryForecast.entries(
                    for: BatteryForecast.record(reading),
                    until: now.addingTimeInterval(BatteryForecast.window)
                )
            } else {
                [BatteryEntry(date: now, level: nil)]
            }
            let phone = PhoneBatteryReading.saved()
            // So the watch app can tell whether a newer reading changes anything here.
            PhoneBatteryReading.setInTimeline(phone)
            completion(Timeline(
                entries: BatteryForecast.adding(phone, to: entries),
                policy: .after(now.addingTimeInterval(30 * 60))
            ))
        }
    }
}

#Preview(as: .accessoryCircular) {
    BatteryComplication()
} timeline: {
    BatteryEntry(date: .now, level: 0.39, phone: PhoneBatteryReading(date: .now, level: 0.3, isPluggedIn: false))
    BatteryEntry(date: .now, level: 0.82, phone: PhoneBatteryReading(date: .now, level: 0.64, isPluggedIn: false))
    BatteryEntry(date: .now, level: 1, phone: PhoneBatteryReading(date: .now, level: 0.99, isPluggedIn: true))
    BatteryEntry(date: .now, level: 0.5, phone: PhoneBatteryReading(date: .distantPast, level: 0.4, isPluggedIn: false))
    BatteryEntry(date: .now, level: 0.99, phone: PhoneBatteryReading(date: .now, level: 0.08, isPluggedIn: false))
    BatteryEntry(date: .now, level: 0.08)
}
