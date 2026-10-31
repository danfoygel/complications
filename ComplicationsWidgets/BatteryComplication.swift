import SwiftUI
import WidgetKit

/// Battery percentage inside a battery outline that fills, like a ring gauge, in proportion to the charge.
struct BatteryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.battery.widgetKind, provider: BatteryProvider()) { entry in
            BatteryComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Route.battery.url)
        }
        .configurationDisplayName("Battery Outline")
        .description("Watch battery in a battery-shaped gauge, with your iPhone's battery below.")
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

/// The watch's battery outline, with the phone's percent below it once the phone app has sent one. A stale phone
/// reading is dimmed rather than hidden.
struct BatteryComplicationView: View {
    let entry: BatteryEntry

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            VStack(spacing: side * 0.04) {
                if let phone = entry.phone {
                    // Smaller, so both fit inside the circle.
                    watch(side: side, width: 0.76, height: 0.42)
                    phoneRow(phone, side: side)
                } else {
                    watch(side: side, width: 0.84, height: 0.48)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func watch(side: Double, width: Double, height: Double) -> some View {
        let outline = BatteryOutline()
        return ZStack {
            outline.stroke(.secondary.opacity(0.35), lineWidth: side * 0.07)
            outline
                .trim(from: 0, to: entry.level ?? 0)
                .stroke(tint, style: StrokeStyle(lineWidth: side * 0.07, lineCap: .round, lineJoin: .round))
                .widgetAccentable()
            Text(entry.percent.map { "\($0)%" } ?? "--")
                .font(.system(size: side * height * 0.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(width: side * width * 0.69)
                .padding(.trailing, side * width * BatteryOutline.nubFraction)
        }
        .frame(width: side * width, height: side * height)
    }

    private func phoneRow(_ phone: PhoneBatteryReading, side: Double) -> some View {
        HStack(spacing: side * 0.02) {
            Image(systemName: "iphone")
            Text("\(phone.percent)%").monospacedDigit()
            if phone.isPluggedIn {
                Image(systemName: "bolt.fill").imageScale(.small)
            }
        }
        .font(.system(size: side * 0.17, weight: .semibold, design: .rounded))
        .foregroundStyle(phone.level <= 0.1 ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        .opacity(phone.isStale(at: entry.date) ? 0.4 : 1)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var tint: Color {
        (entry.level ?? 0) <= 0.1 ? .red : .green
    }
}

/// A horizontal battery traced as a single path from the top center, clockwise and around the terminal nub,
/// so trimming it fills the outline the way a ring gauge fills from 12 o'clock.
struct BatteryOutline: Shape {
    /// Share of the width taken by the nub on the right.
    static let nubFraction = 0.08

    func path(in rect: CGRect) -> Path {
        let nubWidth = rect.width * Self.nubFraction
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width - nubWidth, height: rect.height)
        let radius = body.height * 0.28
        let nubTop = body.midY - body.height * 0.2
        let nubBottom = body.midY + body.height * 0.2
        let nubRadius = nubWidth * 0.6

        var path = Path()
        path.move(to: CGPoint(x: body.midX, y: body.minY))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.minY),
            tangent2End: CGPoint(x: body.maxX, y: body.maxY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: body.maxX, y: nubTop))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: nubTop),
            tangent2End: CGPoint(x: rect.maxX, y: nubBottom),
            radius: nubRadius
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: nubBottom),
            tangent2End: CGPoint(x: body.maxX, y: nubBottom),
            radius: nubRadius
        )
        path.addLine(to: CGPoint(x: body.maxX, y: nubBottom))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.maxY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.minY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.minY),
            tangent2End: CGPoint(x: body.midX, y: body.minY),
            radius: radius
        )
        path.closeSubpath()
        return path
    }
}

#Preview(as: .accessoryCircular) {
    BatteryComplication()
} timeline: {
    BatteryEntry(date: .now, level: 0.82, phone: PhoneBatteryReading(date: .now, level: 0.64, isPluggedIn: false))
    BatteryEntry(date: .now, level: 0.35, phone: PhoneBatteryReading(date: .now, level: 1, isPluggedIn: true))
    BatteryEntry(date: .now, level: 0.5, phone: PhoneBatteryReading(date: .distantPast, level: 0.4, isPluggedIn: false))
    BatteryEntry(date: .now, level: 0.82)
    BatteryEntry(date: .now, level: 0.35)
    BatteryEntry(date: .now, level: 0.08)
    BatteryEntry(date: .now, level: 1)
    BatteryEntry(date: .now, level: nil)
}
