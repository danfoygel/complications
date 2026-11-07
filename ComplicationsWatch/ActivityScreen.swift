import SwiftUI
import WidgetKit

/// Today's activity laid out like the Activity app, in the accent color: the rings with each one's value and goal,
/// then a page per ring with its hour-by-hour chart. Kept current while it's open.
struct ActivityScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var rings = ActivitySummaries.current(ActivitySummaries.saved(), now: .now)
    @State private var hours = ActivityHours.empty
    @State private var now = Date.now
    private let accent = AccentColor.current.color

    var body: some View {
        TabView {
            Overview(rings: rings)
                .navigationTitle("Activity")
            if let rings {
                RingPage(
                    ring: rings.move,
                    goalUnit: rings.moveUnit == .minutes ? "MIN" : "CAL",
                    hours: hours.move,
                    now: now
                )
                .navigationTitle("Move")
                RingPage(ring: rings.exercise, goalUnit: "MIN", hours: hours.exercise, now: now)
                    .navigationTitle("Exercise")
                RingPage(ring: rings.stand, goalUnit: "HRS", hours: hours.stand, now: now)
                    .navigationTitle("Stand")
            }
        }
        .tabViewStyle(.verticalPage)
        .environment(\.complicationAccent, accent)
        // Only while the app is active: each read reloads the complication, which costs nothing from the front.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await ActivitySummaries.requestAccess()
            while !Task.isCancelled {
                now = .now
                rings = await ActivitySummaries.latest(now: now)
                hours = await ActivitySummaries.hours(moveUnit: rings?.moveUnit ?? .calories, now: now)
                Route.activity.widgetKinds.forEach(WidgetCenter.shared.reloadTimelines(ofKind:))
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

/// The rings over each one's value against its goal, in ring order (Move, Exercise, Stand), all on one screen so the
/// pages below are a swipe away.
private struct Overview: View {
    let rings: ActivityRings?
    @Environment(\.complicationAccent) private var accent

    var body: some View {
        VStack(spacing: 6) {
            ActivityRingsView(rings: rings)
                .frame(width: 84, height: 84)
            if let rings {
                VStack(spacing: 0) {
                    line(rings.move, unit: rings.moveUnit == .minutes ? "MIN" : "CAL")
                    line(rings.exercise, unit: "MIN")
                    line(rings.stand, unit: "HRS")
                }
                if rings.isPaused {
                    Label("Paused today", systemImage: "pause.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No activity yet. If it stays empty, allow Activity for Complications in Health on iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func line(_ ring: ActivityRings.Ring, unit: String) -> some View {
        Text("\(ring.value.wholeNumber)/\(ring.goal.wholeNumber) \(unit)")
            .font(.system(size: 18, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// One ring's page: its hour-by-hour chart over the value against the goal and how far round it is, on a wash of the
/// accent color.
private struct RingPage: View {
    let ring: ActivityRings.Ring
    let goalUnit: String
    let hours: [Double]
    let now: Date
    @Environment(\.complicationAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HourlyChart(values: hours, now: now)
                .frame(maxHeight: .infinity)
            HStack(alignment: .center, spacing: 1) {
                Text("\(ring.value.wholeNumber)/")
                    .font(.system(size: 38, weight: .semibold))
                VStack(alignment: .leading, spacing: -3) {
                    Text(ring.goal.wholeNumber)
                    Text(goalUnit)
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(accent)
            Text(ring.progress, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent.opacity(0.6))
        }
        .containerBackground(accent.gradient.opacity(0.3), for: .tabView)
    }
}

/// 24 bars from midnight, scaled to the day's busiest hour, with a line and label every 6 hours. An hour with nothing
/// is a dot, faded once it's past; hours still to come are fainter dots.
private struct HourlyChart: View {
    let values: [Double]
    let now: Date
    @Environment(\.complicationAccent) private var accent

    private static let labelHeight: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let column = geometry.size.width / 24
            let bar = column * 0.6
            let plot = geometry.size.height - Self.labelHeight
            let peak = max(values.max() ?? 0, 1)
            let currentHour = Calendar.current.component(.hour, from: now)
            ZStack(alignment: .topLeading) {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Rectangle()
                        .fill(.secondary.opacity(0.5))
                        .frame(width: 0.5, height: geometry.size.height)
                        .offset(x: min(Double(hour) * column, geometry.size.width - 0.5))
                    if hour < 24 {
                        Text(label(hour))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: Double(hour) * column + 2, y: plot)
                    }
                }
                ForEach(values.indices, id: \.self) { hour in
                    let value = values[hour]
                    let height = value > 0 ? max(bar, plot * value / peak) : bar
                    Capsule()
                        .fill(accent.opacity(value > 0 ? 1 : hour <= currentHour ? 0.45 : 0.2))
                        .frame(width: bar, height: height)
                        .offset(x: (Double(hour) + 0.5) * column - bar / 2, y: plot - height - 1)
                }
            }
        }
    }

    private func label(_ hour: Int) -> String {
        let date = Calendar.current.date(byAdding: .hour, value: hour, to: Calendar.current.startOfDay(for: now))!
        // "12AM", as the Activity app has it; the formatter puts a narrow no-break space before the AM.
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
            .filter { !$0.isWhitespace }
    }
}

private extension Double {
    /// Rounded and grouped, as the Activity app shows them: "1,020".
    var wholeNumber: String {
        formatted(.number.precision(.fractionLength(0)))
    }
}

#Preview {
    NavigationStack { ActivityScreen() }
}
