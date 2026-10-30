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
        .description("Battery percentage with a battery-shaped gauge.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// Re-reads the battery every 15 minutes (the system may stretch that) and fills the gap with a forecast.
struct BatteryProvider: TimelineProvider {
    func placeholder(in _: Context) -> BatteryEntry {
        BatteryEntry(date: .now, level: 0.82)
    }

    func getSnapshot(in _: Context, completion: @escaping @Sendable (BatteryEntry) -> Void) {
        Task { @MainActor in
            completion(BatteryEntry(date: .now, level: BatteryReading.current()?.level))
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
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }
}

struct BatteryComplicationView: View {
    let entry: BatteryEntry

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let outline = BatteryOutline()
            ZStack {
                outline.stroke(.secondary.opacity(0.35), lineWidth: side * 0.07)
                outline
                    .trim(from: 0, to: entry.level ?? 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: side * 0.07, lineCap: .round, lineJoin: .round))
                    .widgetAccentable()
                Text(entry.percent.map { "\($0)%" } ?? "--")
                    .font(.system(size: side * 0.24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(width: side * 0.58)
                    .padding(.trailing, side * 0.84 * BatteryOutline.nubFraction)
            }
            .frame(width: side * 0.84, height: side * 0.48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
    BatteryEntry(date: .now, level: 0.82)
    BatteryEntry(date: .now, level: 0.35)
    BatteryEntry(date: .now, level: 0.08)
    BatteryEntry(date: .now, level: 1)
    BatteryEntry(date: .now, level: nil)
}
