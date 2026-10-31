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
    /// Rain or snow expected in the 12 hours from `date`.
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

    /// The entries from `snapshot` still in effect at `now`. They're built as of when it was fetched, so an older one
    /// shows its forecast for the hour rather than conditions from back then as if they were current.
    static func entries(from snapshot: WeatherSnapshot, now: Date = .now) -> [WeatherEntry] {
        let entries = entries(
            current: snapshot.current, hourly: snapshot.hourly, daily: snapshot.daily, now: snapshot.date
        )
        // Keep the entry in effect at `now` as well as the ones after it.
        let start = entries.lastIndex { $0.date <= now } ?? entries.startIndex
        return Array(entries[start...])
    }

    /// Current conditions, then one entry per forecast hour up to `horizon`, each with its day's high and low, the
    /// next high or low, and the rain or snow in the 12 hours after it.
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
}

/// One WeatherKit fetch, shared by both weather complications and the Weather screen so the watch fetches once for
/// all of them rather than once each. Saved in the app group, and used as the fallback when a fetch fails.
struct WeatherSnapshot: Codable, Sendable {
    /// When it was fetched.
    var date: Date
    var location: PhoneLocation
    var current: CurrentWeather
    /// Only where WeatherKit has a minute forecast (the US, the UK, and a few other countries).
    var minute: Forecast<MinuteWeather>?
    var hourly: Forecast<HourWeather>
    var daily: Forecast<DayWeather>

    /// A saved snapshot this recent is used rather than fetching again. Up Next reloads every 30 minutes and the
    /// weather complication every hour, so this makes about one fetch an hour between them.
    static let maxAge: TimeInterval = 50 * 60

    /// Whether this can stand in for a new fetch at `now` and `location`: recent, and from about the same place.
    func isFresh(at now: Date, for location: PhoneLocation) -> Bool {
        now.timeIntervalSince(date) < Self.maxAge && !location.isFar(from: self.location)
    }

    /// The saved snapshot when it's fresh, else a new one, saved for the others. Throws when the fetch fails.
    static func latest(for location: PhoneLocation, now: Date = .now) async throws -> WeatherSnapshot {
        if let saved = cached(), saved.isFresh(at: now, for: location) {
            return saved
        }
        let snapshot = try await SharedFetch.shared.snapshot(for: location)
        snapshot.save()
        return snapshot
    }

    fileprivate static func fetch(for location: PhoneLocation) async throws -> WeatherSnapshot {
        let (current, minute, hourly, daily) = try await WeatherService.shared.weather(
            for: location.location,
            including: .current, .minute, .hourly, .daily
        )
        return WeatherSnapshot(
            date: .now, location: location, current: current, minute: minute, hourly: hourly, daily: daily
        )
    }

    static func cached(in defaults: UserDefaults = AppGroup.defaults) -> WeatherSnapshot? {
        defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) }
    }

    func save(in defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.cacheKey)
    }

    private static let cacheKey = "weatherSnapshot"
}

/// Both complications often reload at once (when the face changes, say); this has the second wait for the first's
/// fetch instead of making its own. They run in the same extension process.
private actor SharedFetch {
    static let shared = SharedFetch()

    private var running: Task<WeatherSnapshot, Error>?

    func snapshot(for location: PhoneLocation) async throws -> WeatherSnapshot {
        if let running {
            return try await running.value
        }
        let task = Task { try await WeatherSnapshot.fetch(for: location) }
        running = task
        defer { running = nil }
        return try await task.value
    }
}

/// The minute, hourly and daily forecasts and the air quality behind the calendar's weather line (`WeatherLine`).
struct PrecipitationForecast: Sendable {
    var minutes: [ForecastMinute]
    var hours: [ForecastHour]
    /// For the next day with rain or snow when there's none in the next 24 hours, and the sunrises and sunsets.
    var days: [ForecastDay]
    /// For the air quality shown when it's dry.
    var airQuality: [AirQualityReading] = []
}

extension PrecipitationForecast {
    init(_ snapshot: WeatherSnapshot) {
        self.init(
            minutes: snapshot.minute.map { $0.map(ForecastMinute.init) } ?? [],
            hours: snapshot.hourly.map(ForecastHour.init),
            days: snapshot.daily.map(ForecastDay.init)
        )
    }
}

extension PrecipitationSpan.Kind {
    /// What counts as rain or snow, given what falls and how likely it is.
    init?(_ precipitation: Precipitation, chance: Double) {
        guard chance >= WeatherForecast.precipitationThreshold else { return nil }
        switch precipitation {
        case .none: return nil
        case .snow, .sleet, .mixed: self = .snow
        default: self = .rain
        }
    }
}

extension ForecastHour {
    init(_ hour: HourWeather) {
        self.init(
            date: hour.date,
            temperature: hour.temperature.converted(to: .celsius).value,
            precipitation: PrecipitationSpan.Kind(hour.precipitation, chance: hour.precipitationChance),
            precipitationAmount: hour.precipitationAmount.converted(to: .millimeters).value,
            snowfallAmount: hour.snowfallAmount.converted(to: .millimeters).value
        )
    }
}

extension ForecastMinute {
    init(_ minute: MinuteWeather) {
        self.init(
            date: minute.date,
            precipitation: PrecipitationSpan.Kind(minute.precipitation, chance: minute.precipitationChance)
        )
    }
}

extension ForecastDay {
    init(_ day: DayWeather) {
        self.init(
            date: day.date,
            low: day.lowTemperature.converted(to: .celsius).value,
            high: day.highTemperature.converted(to: .celsius).value,
            precipitation: PrecipitationSpan.Kind(day.precipitation, chance: day.precipitationChance),
            sunrise: day.sun.sunrise,
            sunset: day.sun.sunset
        )
    }
}

/// Where the phone last was, which `PhoneLink` saves as it arrives. The watch never takes a fix of its own: its GPS
/// costs more battery than a weather forecast is worth. `saved()` is `nil` until the phone has sent a location.
extension PhoneLocation {
    private static let key = "phoneLocation"

    static func saved(in defaults: UserDefaults = AppGroup.defaults) -> PhoneLocation? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    /// Saves this location unless a newer one is already saved; returns whether it did.
    @discardableResult func save(in defaults: UserDefaults = AppGroup.defaults) -> Bool {
        if let saved = Self.saved(in: defaults), saved.date >= date {
            return false
        }
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
        return true
    }
}
