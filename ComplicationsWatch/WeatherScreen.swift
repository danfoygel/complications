import SwiftUI
import WeatherKit
import WidgetKit

/// Current conditions, the next 12 hours, and the next week.
struct WeatherScreen: View {
    private enum Phase {
        case loading
        case failed(String)
        case loaded(CurrentWeather, Forecast<HourWeather>, Forecast<DayWeather>, WeatherAttribution?)
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = Phase.loading
    /// When the phone took the location the forecast is for.
    @State private var locationDate: Date?

    var body: some View {
        List {
            switch phase {
            case .loading:
                ProgressView()
            case let .failed(message):
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case let .loaded(current, hourly, daily, attribution):
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: current.symbolName)
                            Text(Temperature.text(current.temperature.converted(to: .celsius).value))
                        }
                        .font(.largeTitle)
                        Text(current.condition.description)
                        Text(
                            "Feels like \(Temperature.text(current.apparentTemperature.converted(to: .celsius).value))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // The forecast is for wherever the phone last was; say so when that was a while ago.
                        if let locationDate, Date.now.timeIntervalSince(locationDate) > 60 * 60 {
                            Text("Location from \(locationDate, format: .relative(presentation: .named))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Hourly") {
                    ForEach(hourly.filter { $0.date >= .now.addingTimeInterval(-3600) }.prefix(12), id: \.date) {
                        ForecastRow(
                            label: $0.date.formatted(.dateTime.hour()),
                            symbol: $0.symbolName,
                            value: Temperature.text($0.temperature.converted(to: .celsius).value)
                        )
                    }
                }
                Section("Daily") {
                    ForEach(daily.prefix(7), id: \.date) {
                        ForecastRow(
                            label: $0.date.formatted(.dateTime.weekday(.abbreviated)),
                            symbol: $0.symbolName,
                            value: "\(Temperature.text($0.lowTemperature.converted(to: .celsius).value)) – "
                                + Temperature.text($0.highTemperature.converted(to: .celsius).value)
                        )
                    }
                }
                if let attribution {
                    Section {
                        Text("\u{F8FF} Weather").font(.caption)
                        Text(attribution.legalPageURL.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Weather")
        // Again each time the app comes back; the saved forecast is reused while it's fresh, so that's cheap.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await load()
        }
    }

    private func load() async {
        // Until the phone has sent a location, ask it for one now.
        if PhoneLocation.saved() == nil {
            _ = await PhoneLink.shared.refresh(maxAge: 0)
        }
        guard let location = PhoneLocation.saved() else {
            phase = .failed("Open Complications on the iPhone and allow location access to see the weather here.")
            return
        }
        locationDate = location.date
        let previous = WeatherSnapshot.cachedSummary()?.date
        do {
            // Someone's looking, so a fetch that's been failing is tried again now rather than after its backoff.
            let snapshot = try await WeatherSnapshot.latest(for: location, retryingNow: true)
            // A new fetch: hand it to the complications, which may have failed their own and be waiting to retry.
            // Reloads asked for while the app is in front don't count against their budget.
            if snapshot.date != previous {
                Route.weather.widgetKinds.forEach(WidgetCenter.shared.reloadTimelines(ofKind:))
            }
            phase = await .loaded(
                snapshot.current, snapshot.hourly, snapshot.daily, try? WeatherService.shared.attribution
            )
        } catch {
            // The domain and code, which `localizedDescription` buries, say which WeatherKit check failed.
            let nsError = error as NSError
            phase = .failed("Couldn't load the weather (\(nsError.domain) \(nsError.code)): \(error)")
        }
    }
}

private struct ForecastRow: View {
    let label: String
    let symbol: String
    let value: String

    var body: some View {
        HStack {
            Text(label).frame(width: 44, alignment: .leading)
            Image(systemName: symbol).frame(width: 28)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}

#Preview {
    NavigationStack { WeatherScreen() }
}
