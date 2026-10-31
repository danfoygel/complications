import SwiftUI
import WidgetKit

/// The battery level with an estimate of time to empty, or to full while charging, and the phone's battery.
struct BatteryScreen: View {
    @State private var history: [BatteryReading] = []
    @State private var phone = PhoneBatteryReading.saved()

    var body: some View {
        let current = history.last
        ScrollView {
            VStack(spacing: 12) {
                Gauge(value: current?.level ?? 0) {
                    Image(systemName: current?.isPluggedIn == true ? "bolt.fill" : "battery.100")
                } currentValueLabel: {
                    Text(current.map { "\(Int(($0.level * 100).rounded()))%" } ?? "--")
                }
                .gaugeStyle(.accessoryCircular)
                .tint((current?.level ?? 0) <= 0.1 ? .red : .green)
                .scaleEffect(1.6)
                .frame(height: 90)

                Text(current.map { $0.isPluggedIn ? "Charging" : "On battery" } ?? "Battery level unavailable")
                    .font(.headline)
                Text(estimate)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Divider()
                PhoneBatteryRow(reading: phone)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Battery")
        .task { await refresh() }
    }

    private var estimate: String {
        guard let current = history.last else { return "" }
        guard let remaining = BatteryForecast.timeRemaining(history) else {
            return "An estimate appears after about \(Int(BatteryForecast.minimumSpan / 60)) minutes of readings."
        }
        let duration = Duration.seconds(remaining).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return current.isPluggedIn ? "Full in about \(duration)" : "About \(duration) left"
    }

    /// Takes a reading now and every minute while the screen is open, adding each to the shared history, and
    /// asks the phone for its battery whenever the saved one is over 5 minutes old.
    private func refresh() async {
        while !Task.isCancelled {
            if let reading = BatteryReading.current() {
                history = BatteryForecast.record(reading)
                Route.battery.widgetKinds.forEach(WidgetCenter.shared.reloadTimelines(ofKind:))
            }
            phone = await PhoneLink.shared.refresh()
            try? await Task.sleep(for: .seconds(60))
        }
    }
}

private struct PhoneBatteryRow: View {
    let reading: PhoneBatteryReading?

    var body: some View {
        VStack(spacing: 2) {
            if let reading {
                Label {
                    Text("\(reading.percent)%" + (reading.isPluggedIn ? " · Charging" : ""))
                } icon: {
                    Image(systemName: "iphone")
                }
                .font(.headline)
                .foregroundStyle(reading.level <= 0.1 ? .red : .primary)
                TimelineView(.everyMinute) { context in
                    Text(updated(reading, now: context.date))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("iPhone", systemImage: "iphone").font(.headline)
                Text("Open Complications on your iPhone to start sending its battery.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func updated(_ reading: PhoneBatteryReading, now: Date) -> String {
        now.timeIntervalSince(reading.date) < 60
            ? "Just now"
            : "Updated " + reading.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

#Preview {
    NavigationStack { BatteryScreen() }
}
