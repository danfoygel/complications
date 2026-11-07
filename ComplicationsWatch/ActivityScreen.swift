import SwiftUI
import WidgetKit

/// Today's rings with each one's value and goal, kept current while it's open.
struct ActivityScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var rings = ActivitySummaries.current(ActivitySummaries.saved(), now: .now)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ActivityRingsView(rings: rings)
                    .environment(\.complicationAccent, AccentColor.current.color)
                    .frame(width: 110, height: 110)
                if let rings {
                    if rings.isPaused {
                        Label("Rings paused today", systemImage: "pause.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        RingRow(name: "Move", ring: rings.move, unit: rings.moveUnit == .minutes ? "MIN" : "CAL")
                        RingRow(name: "Exercise", ring: rings.exercise, unit: "MIN")
                        RingRow(name: "Stand", ring: rings.stand, unit: "HR")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(
                        """
                        No activity yet. If the rings stay empty, allow Complications to read Activity in the Health \
                        app's settings on your iPhone.
                        """
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Activity")
        // Only while the app is active: each read reloads the complication, which costs nothing from the front.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await ActivitySummaries.requestAccess()
            while !Task.isCancelled {
                rings = await ActivitySummaries.latest()
                Route.activity.widgetKinds.forEach(WidgetCenter.shared.reloadTimelines(ofKind:))
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

private struct RingRow: View {
    let name: String
    let ring: ActivityRings.Ring
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.footnote).foregroundStyle(.secondary)
            Text("\(Int(ring.value.rounded()))/\(Int(ring.goal.rounded())) \(unit)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AccentColor.current.color)
        }
    }
}

#Preview {
    NavigationStack { ActivityScreen() }
}
