import CoreLocation
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

    @State private var phase = Phase.loading
    /// Keeps the When In Use authorization prompt (and live updates) available while the screen is open.
    @State private var session: CLServiceSession?

    var body: some View {
        List {
            switch phase {
            case .loading:
                ProgressView()
            case let .failed(message):
                Text(message).foregroundStyle(.secondary)
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
        .task { await load() }
    }

    private func load() async {
        let wasAuthorized = Location.isAuthorized
        session = CLServiceSession(authorization: .whenInUse)
        defer { session = nil }
        guard let location = await Location.current() else {
            phase = .failed("Allow location access in Settings › Privacy & Security › Location Services.")
            return
        }
        if Location.isAuthorized != wasAuthorized {
            WidgetCenter.shared.reloadTimelines(ofKind: Route.weather.widgetKind)
        }
        do {
            let (current, hourly, daily) = try await WeatherService.shared.weather(
                for: location,
                including: .current, .hourly, .daily
            )
            phase = await .loaded(current, hourly, daily, try? WeatherService.shared.attribution)
        } catch {
            phase = .failed("Couldn't load the weather: \(error.localizedDescription)")
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
