import CoreLocation
import Foundation
import WeatherKit
import WidgetKit

/// Conditions for one point in time, as the weather complication shows them.
struct WeatherEntry: TimelineEntry, Codable, Sendable {
    var date: Date
    /// Temperatures are in Celsius; `Temperature.text` formats them for the user's locale.
    var temperature: Double
    var low: Double
    var high: Double
    var symbolName: String
    var condition: String
    /// The next turning point of the temperature: the high still to come, or the low after it. `nil` when unknown.
    var next: TemperatureExtreme?
    /// Rain or snow expected in the 12 hours from `date`, drawn on the complication's clock ring.
    var precipitation: [PrecipitationSpan]?
}

struct TemperatureExtreme: Codable, Sendable {
    var temperature: Double
    var isHigh: Bool
}

struct PrecipitationSpan: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case rain
        /// Snow, sleet, or a mix: anything frozen.
        case snow
    }

    var kind: Kind
    var start: Date
    var end: Date
}

enum Temperature {
    /// "72°" in the user's preferred unit.
    static func text(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(
                width: .narrow,
                usage: .weather,
                numberFormatStyle: .number.precision(.fractionLength(0))
            ))
    }

    /// "72" in the user's preferred unit, with no degree sign.
    static func number(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .converted(to: UnitTemperature(forLocale: .current, usage: .weather))
            .value
            .formatted(.number.precision(.fractionLength(0)))
    }
}

enum WeatherForecast {
    /// How far ahead hourly entries go. A reload normally comes well before the last one.
    static let horizon: TimeInterval = 6 * 60 * 60

    /// Current conditions, then one entry per forecast hour up to `horizon`, each with its day's high and low, the
    /// next high or low, and the rain or snow in the 12 hours after it.
    static func entries(for location: CLLocation, now: Date = .now) async throws -> [WeatherEntry] {
        let (current, hourly, daily) = try await WeatherService.shared.weather(
            for: location,
            including: .current, .hourly, .daily
        )
        return entries(current: current, hourly: hourly, daily: daily, now: now)
    }

    /// The entries for a forecast already fetched, as `WeatherScreen` has.
    static func entries(
        current: CurrentWeather,
        hourly: Forecast<HourWeather>,
        daily: Forecast<DayWeather>,
        now: Date = .now
    ) -> [WeatherEntry] {
        let hours = hourly.map(ForecastHour.init)
        let days = daily.map(ForecastDay.init)
        func entry(
            date: Date,
            temperature: Measurement<UnitTemperature>,
            symbol: String,
            condition: String
        ) -> WeatherEntry {
            let value = temperature.converted(to: .celsius).value
            let day = days.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
            return WeatherEntry(
                date: date,
                temperature: value,
                low: min(day?.low ?? value, value),
                high: max(day?.high ?? value, value),
                symbolName: symbol,
                condition: condition,
                next: nextExtreme(after: date, temperature: value, hours: hours, days: days),
                precipitation: precipitation(after: date, hours: hours)
            )
        }

        let first = entry(
            date: now,
            temperature: current.temperature,
            symbol: current.symbolName,
            condition: current.condition.description
        )
        let later = hourly.filter { $0.date > now && $0.date <= now.addingTimeInterval(horizon) }.map {
            entry(
                date: $0.date,
                temperature: $0.temperature,
                symbol: $0.symbolName,
                condition: $0.condition.description
            )
        }
        return [first] + later
    }

    /// Entries saved by the last successful fetch, for when the next one fails.
    static func cached(after date: Date, in defaults: UserDefaults = AppGroup.defaults) -> [WeatherEntry] {
        let entries = defaults.data(forKey: cacheKey)
            .flatMap { try? JSONDecoder().decode([WeatherEntry].self, from: $0) } ?? []
        // Keep the entry in effect at `date` as well as the ones after it.
        let start = entries.lastIndex { $0.date <= date } ?? entries.startIndex
        return Array(entries[start...])
    }

    static func save(_ entries: [WeatherEntry], in defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(try? JSONEncoder().encode(entries), forKey: cacheKey)
    }

    private static let cacheKey = "weatherEntries"
}

extension ForecastHour {
    init(_ hour: HourWeather) {
        let kind: PrecipitationSpan.Kind? = switch hour.precipitation {
        case .none: nil
        case .snow, .sleet, .mixed: .snow
        default: .rain
        }
        self.init(
            date: hour.date,
            temperature: hour.temperature.converted(to: .celsius).value,
            precipitation: hour.precipitationChance >= WeatherForecast.precipitationThreshold ? kind : nil
        )
    }
}

extension ForecastDay {
    init(_ day: DayWeather) {
        self.init(
            date: day.date,
            low: day.lowTemperature.converted(to: .celsius).value,
            high: day.highTemperature.converted(to: .celsius).value
        )
    }
}

enum Location {
    static var isAuthorized: Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    /// A fresh fix if one arrives within `timeout`, else the last known location (the system's, then ours).
    static func current(timeout: Duration = .seconds(10)) async -> CLLocation? {
        let fresh = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location {
                            return location
                        }
                        if update.authorizationDenied || update.authorizationRestricted {
                            return nil
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        let defaults = AppGroup.defaults
        if let location = fresh ?? CLLocationManager().location {
            defaults.set([location.coordinate.latitude, location.coordinate.longitude], forKey: lastKey)
            return location
        }
        guard let saved = defaults.array(forKey: lastKey) as? [Double], saved.count == 2 else { return nil }
        return CLLocation(latitude: saved[0], longitude: saved[1])
    }

    private static let lastKey = "lastLocation"
}
