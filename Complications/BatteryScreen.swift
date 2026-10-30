import SwiftUI
import WidgetKit

/// The battery level with an estimate of time to empty, or to full while charging.
struct BatteryScreen: View {
    @State private var history: [BatteryReading] = []

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

    /// Takes a reading now and every minute while the screen is open, adding each to the shared history.
    private func refresh() async {
        while !Task.isCancelled {
            if let reading = BatteryReading.current() {
                history = BatteryForecast.record(reading)
                WidgetCenter.shared.reloadTimelines(ofKind: Route.battery.widgetKind)
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }
}

#Preview {
    NavigationStack { BatteryScreen() }
}
