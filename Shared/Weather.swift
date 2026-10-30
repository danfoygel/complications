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
}

enum WeatherForecast {
    /// How far ahead hourly entries go. A reload normally comes well before the last one.
    static let horizon: TimeInterval = 6 * 60 * 60

    /// Current conditions, then one entry per forecast hour up to `horizon`, each with its day's high and low.
    static func entries(for location: CLLocation, now: Date = .now) async throws -> [WeatherEntry] {
        let (current, hourly, daily) = try await WeatherService.shared.weather(
            for: location,
            including: .current, .hourly, .daily
        )
        func range(on date: Date) -> (low: Double, high: Double)? {
            daily.first { Calendar.current.isDate($0.date, inSameDayAs: date) }.map {
                ($0.lowTemperature.converted(to: .celsius).value, $0.highTemperature.converted(to: .celsius).value)
            }
        }
        func entry(
            date: Date,
            temperature: Measurement<UnitTemperature>,
            symbol: String,
            condition: String
        ) -> WeatherEntry {
            let value = temperature.converted(to: .celsius).value
            let day = range(on: date) ?? (value, value)
            return WeatherEntry(
                date: date,
                temperature: value,
                low: min(day.low, value),
                high: max(day.high, value),
                symbolName: symbol,
                condition: condition
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
