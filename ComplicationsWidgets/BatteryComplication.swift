import SwiftUI
import WidgetKit

/// Watch and iPhone battery as the two halves of one battery outline, with both percents inside.
struct BatteryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.battery.widgetKind, provider: BatteryProvider()) { entry in
            BatteryComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Route.battery.url)
        }
        .configurationDisplayName("Battery Outline")
        .description("Your watch's battery on the top half of the outline, your iPhone's on the bottom.")
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

/// The watch's percent over the phone's, inside a battery outline split in two: the top half is the watch's battery,
/// the bottom half the phone's. Both halves fill from the middle of the left side, the watch's clockwise over the top
/// and the phone's counter-clockwise under the bottom, so each drains back toward the left. A stale phone reading is
/// dimmed rather than hidden; with no reading yet its half is empty.
struct BatteryComplicationView: View {
    let entry: BatteryEntry

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                half(entry.level, tint: .green, isTop: true, side: side)
                half(entry.phone?.level, tint: .blue, isTop: false, side: side)
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

    private func half(_ level: Double?, tint: Color, isTop: Bool, side: Double) -> some View {
        let shape = BatteryHalf(isTop: isTop)
        let style = StrokeStyle(lineWidth: side * Layout.thickness, lineCap: .round, lineJoin: .round)
        // Each end stops short of the split by half the gap plus its rounded cap, as a share of the half's length.
        let inset = (Layout.gap + Layout.thickness) / 2 / BatteryHalf.length
        let filled = (1 - 2 * inset) * min(max(level ?? 0, 0), 1)
        // The empty part is the half's own color, faded like a system gauge's track; both parts are accented, so on a
        // tinted face it shows as the tint at the same fade.
        return ZStack {
            shape.trim(from: inset, to: 1 - inset).stroke(tint.opacity(Layout.trackOpacity), style: style)
            shape
                .trim(from: inset, to: inset + filled)
                .stroke((level ?? 0) <= 0.1 ? .red : tint, style: style)
        }
        .widgetAccentable()
        .frame(width: side, height: side)
    }

    private func percent(_ value: Int?, color: Color, centerY: Double, side: Double) -> some View {
        Text(value.map(String.init) ?? "--")
            .font(.system(size: side * Layout.fontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: side * Layout.textWidth)
            .position(x: side * Layout.bodyMidX, y: side * centerY)
    }
}

/// Half of a horizontal battery's outline, traced along the middle of its stroke from the middle of the left side,
/// over the top (or under the bottom) and around the nub to the nub's middle, so trimming it fills from the left.
/// The nub's corners are square here; the round line join rounds them.
struct BatteryHalf: Shape {
    let isTop: Bool

    private static let minX = Layout.bodyLeft + Layout.thickness / 2
    private static let maxX = Layout.bodyLeft + Layout.bodyWidth - Layout.thickness / 2
    private static let minY = 0.5 - Layout.bodyHeight / 2 + Layout.thickness / 2
    private static let radius = Layout.cornerRadius - Layout.thickness / 2
    private static let nubRight = Layout.bodyLeft + Layout.bodyWidth + Layout.nubWidth - Layout.thickness / 2
    private static let nubTop = 0.5 - Layout.nubHeight / 2 + Layout.thickness / 2

    /// The path's length as a fraction of the complication's side.
    static let length = (0.5 - minY - radius) + .pi * radius + (maxX - minX - 2 * radius) + (nubTop - minY - radius)
        + (nubRight - maxX) + (0.5 - nubTop)

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        // The bottom half is the top half mirrored across the middle.
        let point = { (across: Double, down: Double) in
            CGPoint(x: rect.minX + across * side, y: rect.minY + (isTop ? down : 1 - down) * side)
        }
        var path = Path()
        path.move(to: point(Self.minX, 0.5))
        path.addArc(
            tangent1End: point(Self.minX, Self.minY),
            tangent2End: point(Self.maxX, Self.minY),
            radius: Self.radius * side
        )
        path.addArc(
            tangent1End: point(Self.maxX, Self.minY),
            tangent2End: point(Self.maxX, 0.5),
            radius: Self.radius * side
        )
        path.addLine(to: point(Self.maxX, Self.nubTop))
        path.addLine(to: point(Self.nubRight, Self.nubTop))
        path.addLine(to: point(Self.nubRight, 0.5))
        return path
    }
}

/// Fractions of the complication's side: the largest 1.2 : 1 battery whose outline (nub included) stays inside the
/// circle, with 14 pt numbers on a 41mm watch.
private enum Layout {
    static let thickness = 0.067
    /// Space between the two halves at the middle of each side, about 1.3 pt on a 41mm watch.
    static let gap = 0.03
    /// Matches the track of the system's circular gauges on a tinted face (measured at about 35% of the tint).
    static let trackOpacity = 0.35
    /// The body's outer edge; the body and nub together are centered.
    static let bodyLeft = 0.054
    static let bodyWidth = 0.857
    static let bodyHeight = 0.714
    /// A quarter of the body's height, on the outer edge.
    static let cornerRadius = 0.1785
    static let nubWidth = 0.075
    static let nubHeight = 0.3
    static let bodyMidX = bodyLeft + bodyWidth / 2
    static let fontSize = 0.315
    /// Line-box centers that space the two numbers' digits evenly inside the body.
    static let watchNumberY = 0.362
    static let phoneNumberY = 0.625
    /// The body's inside, less 0.025 each side; "100" fits at full size.
    static let textWidth = 0.673
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
