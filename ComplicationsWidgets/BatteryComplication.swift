import SwiftUI
import WidgetKit

/// Watch and iPhone battery as the two halves of one ring, with both percents inside.
struct BatteryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.battery.widgetKind, provider: BatteryProvider()) { entry in
            BatteryComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Route.battery.url)
        }
        .configurationDisplayName("Battery Rings")
        .description("Your watch's battery on the top half of the ring, your iPhone's on the bottom.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// Re-reads the battery every 15 minutes (the system may stretch that) and fills the gap with a forecast. The phone's
/// reading comes from whatever the watch app last received; receiving a newer one reloads this.
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
            completion(Timeline(
                entries: BatteryForecast.adding(.saved(), to: entries),
                policy: .after(now.addingTimeInterval(15 * 60))
            ))
        }
    }
}

/// The watch's percent over the phone's, inside a ring split in two: the top half is the watch's battery, the bottom
/// half the phone's. Both halves fill from 9 o'clock, the watch's clockwise over the top and the phone's
/// counter-clockwise under the bottom, so each drains back toward 9 o'clock. A stale phone reading is dimmed rather
/// than hidden; with no reading yet its half is empty.
struct BatteryComplicationView: View {
    let entry: BatteryEntry

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                halfRing(entry.level, tint: .green, isTop: true, side: side)
                halfRing(entry.phone?.level, tint: .blue, isTop: false, side: side)
                    .opacity(isPhoneStale ? 0.4 : 1)
                percent(entry.percent, color: .white, centerY: Layout.watchNumberY, side: side)
                percent(entry.phone?.percent, color: .cyan, centerY: Layout.phoneNumberY, side: side)
                    .opacity(isPhoneStale ? 0.4 : 1)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var isPhoneStale: Bool {
        entry.phone?.isStale(at: entry.date) ?? false
    }

    /// A circle's path starts at 3 o'clock and runs clockwise, so the bottom half is its first half as drawn, and
    /// turning it 180° puts that half on top.
    private func halfRing(_ level: Double?, tint: Color, isTop: Bool, side: Double) -> some View {
        let lineWidth = side * Layout.thickness
        let diameter = side * (1 - Layout.thickness)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        // Each end stops short of 3 and 9 o'clock by half the gap plus its rounded cap, as a share of the
        // circumference.
        let inset = (Layout.gap + Layout.thickness) / 2 / (.pi * (1 - Layout.thickness))
        let start = inset
        let end = 0.5 - inset
        let filled = (end - start) * min(max(level ?? 0, 0), 1)
        return ZStack {
            Circle().trim(from: start, to: end).stroke(Color(white: 0.3), style: style)
            Circle()
                // On top the fill runs on from 9 o'clock; on the bottom it runs back to it.
                .trim(from: isTop ? start : end - filled, to: isTop ? start + filled : end)
                .stroke((level ?? 0) <= 0.1 ? .red : tint, style: style)
                .widgetAccentable()
        }
        .rotationEffect(.degrees(isTop ? 180 : 0))
        .frame(width: diameter, height: diameter)
    }

    private func percent(_ value: Int?, color: Color, centerY: Double, side: Double) -> some View {
        Text(value.map(String.init) ?? "--")
            .font(.system(size: side * Layout.fontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: side * Layout.textWidth)
            .position(x: side / 2, y: side * centerY)
    }
}

/// Fractions of the complication's side, laid out in the dual battery designer on the 41mm canvas.
private enum Layout {
    /// The ring's outer edge is the complication's edge.
    static let thickness = 0.067
    /// Space between the two halves at 3 and 9 o'clock, about 1.3 pt on a 41mm watch.
    static let gap = 0.03
    static let fontSize = 0.404
    static let watchNumberY = 0.326
    static let phoneNumberY = 0.669
    /// Room for a percent before it shrinks; "100" needs less than full size.
    static let textWidth = 0.62
}

#Preview(as: .accessoryCircular) {
    BatteryComplication()
} timeline: {
    BatteryEntry(date: .now, level: 0.39, phone: PhoneBatteryReading(date: .now, level: 0.3, isPluggedIn: false))
    BatteryEntry(date: .now, level: 0.82, phone: PhoneBatteryReading(date: .now, level: 0.64, isPluggedIn: false))
    BatteryEntry(date: .now, level: 0.35, phone: PhoneBatteryReading(date: .now, level: 0.99, isPluggedIn: true))
    BatteryEntry(date: .now, level: 0.5, phone: PhoneBatteryReading(date: .distantPast, level: 0.4, isPluggedIn: false))
    BatteryEntry(date: .now, level: 0.99, phone: PhoneBatteryReading(date: .now, level: 0.08, isPluggedIn: false))
    BatteryEntry(date: .now, level: 0.08)
}
