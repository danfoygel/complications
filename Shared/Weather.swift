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
    /// shows its forecast for the hour rather than conditions from back then as if they were current. None once
    /// `now` is past the last of them: an hours-old forecast shouldn't stand in for the current temperature.
    static func entries(from snapshot: WeatherSnapshot, now: Date = .now) -> [WeatherEntry] {
        guard now.timeIntervalSince(snapshot.date) < horizon else { return [] }
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

    /// The saved snapshot when it's fresh, else a new one, saved for the others. Throws when the fetch fails or
    /// takes longer than `fetchLimit`, and without trying while recent failures for about this place say to wait
    /// (`Backoff`), unless `retryingNow` (someone is looking at the Weather screen).
    static func latest(
        for location: PhoneLocation, now: Date = .now, retryingNow: Bool = false
    ) async throws -> WeatherSnapshot {
        if let saved = cached(), saved.isFresh(at: now, for: location) {
            return saved
        }
        if !retryingNow {
            try Backoff.check(backoffKey, at: now, for: location)
        }
        return try await SharedFetch.shared.snapshot(for: location)
    }

    fileprivate static let backoffKey = "weatherBackoff"

    /// The saved snapshot as a stand-in when a fetch fails: only one from about the same place as `location` and
    /// under `maxAge` old, so a forecast from before a trip, or from days ago, isn't shown as this one.
    static func fallback(
        for location: PhoneLocation?,
        maxAge: TimeInterval,
        now: Date = .now,
        at url: URL? = fileURL
    ) -> WeatherSnapshot? {
        guard let location, let saved = cached(at: url),
              now.timeIntervalSince(saved.date) < maxAge, !location.isFar(from: saved.location) else { return nil }
        return saved
    }

    /// How long a fetch may take before it counts as failed, well within a widget's time to return its timeline.
    static let fetchLimit: Duration = .seconds(15)

    /// How far the hourly forecast goes. Up Next looks 24 hours ahead from each of its entries, and WeatherKit's
    /// default (25 hours from the current hour) stops covering that within the hour; two days keeps rain on the line
    /// for a day of entries even when reloads are skipped.
    static let hourlyRange: TimeInterval = 48 * 60 * 60

    fileprivate static func fetch(for location: PhoneLocation) async throws -> WeatherSnapshot {
        let now = Date.now
        // From the start of the current hour, which the default query also includes.
        let hourStart = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        let (current, minute, hourly, daily) = try await WeatherService.shared.weather(
            for: location.location,
            including: .current, .minute,
            .hourly(startDate: hourStart, endDate: hourStart.addingTimeInterval(hourlyRange)), .daily
        )
        return WeatherSnapshot(
            date: now, location: location, current: current, minute: minute, hourly: hourly, daily: daily
        )
    }

    /// Where the last fetch is saved. It's tens of kilobytes of WeatherKit's encoding, too much for the app group's
    /// defaults (which every process using them keeps in memory), so it's a file in the group's container.
    static let fileURL = AppGroup.containerURL?.appendingPathComponent("weatherSnapshot.json")

    static func cached(at url: URL? = fileURL) -> WeatherSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    /// When and where the saved fetch was made, without building its forecasts.
    struct Summary: Decodable {
        var date: Date
        var location: PhoneLocation
    }

    static func cachedSummary(at url: URL? = fileURL) -> Summary? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: data)
    }

    func save(to url: URL? = Self.fileURL) {
        guard let url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
        // Where earlier builds kept it.
        AppGroup.defaults.removeObject(forKey: "weatherSnapshot")
    }
}

/// Both complications often reload at once (when the face changes, say); this has the second wait for the first's
/// fetch instead of making its own, when it's for about the same place. They run in the same extension process.
/// The fetch saves what it gets and records the outcome in the `Backoff`, once however many are waiting for it.
private actor SharedFetch {
    static let shared = SharedFetch()

    private var running: (location: PhoneLocation, task: Task<WeatherSnapshot, Error>)?

    func snapshot(for location: PhoneLocation) async throws -> WeatherSnapshot {
        if let running, !location.isFar(from: running.location) {
            return try await running.task.value
        }
        let task = Task {
            do {
                let snapshot = try await Deadline.run(within: WeatherSnapshot.fetchLimit) {
                    try await WeatherSnapshot.fetch(for: location)
                }
                snapshot.save()
                Backoff.reset(WeatherSnapshot.backoffKey)
                return snapshot
            } catch {
                Backoff.recordFailure(WeatherSnapshot.backoffKey, at: .now, for: location)
                throw error
            }
        }
        running = (location, task)
        defer {
            if running?.task == task {
                running = nil
            }
        }
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
