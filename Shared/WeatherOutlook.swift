import Foundation

/// A forecast hour reduced to what the complication needs, so the logic below can be tested without WeatherKit.
struct ForecastHour: Codable, Sendable {
    /// The start of the hour.
    var date: Date
    /// Celsius.
    var temperature: Double
    /// What falls this hour, when it's likely enough to show; `nil` otherwise.
    var precipitation: PrecipitationSpan.Kind?
    /// Millimetres of water expected this hour, snow melted, however unlikely.
    var precipitationAmount: Double = 0
    /// Millimetres of snow expected this hour, as it lies.
    var snowfallAmount: Double = 0
}

/// A minute of the minute forecast (the next hour, where WeatherKit has one), reduced like `ForecastHour`.
struct ForecastMinute: Codable, Sendable {
    var date: Date
    var precipitation: PrecipitationSpan.Kind?
}

/// The nearest rain or snow, in words: "in 30m", "in 18h", "for 4h", "for 12h+", "on Tu".
struct PrecipitationOutlook: Equatable, Sendable {
    enum Timing: Equatable, Sendable {
        /// Dry now; it starts after this long.
        case startsIn(TimeInterval)
        /// Falling now; it stops after this long.
        case stopsIn(TimeInterval)
        /// Falling now and still at the end of the `precipitationWindow`.
        case lastsPastWindow
        /// Nothing in the `totalWindow`; the first later day with some.
        case onDay(Date)
    }

    var kind: PrecipitationSpan.Kind
    var timing: Timing

    var text: String {
        switch timing {
        case let .startsIn(interval): "in " + Self.duration(interval)
        case let .stopsIn(interval): "for " + Self.duration(interval)
        case .lastsPastWindow: "for \(Int(WeatherForecast.precipitationWindow / 3600))h+"
        case let .onDay(day): "on " + day.formatted(.dateTime.weekday(.short))
        }
    }

    /// Under an hour, minutes to the nearest 5 (at least 5); otherwise hours to the nearest one.
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(5, Int((interval / 60 / 5).rounded()) * 5)
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(max(1, Int((interval / 3600).rounded())))h"
    }
}

/// How much rain or snow the `totalWindow` ahead holds: "0.4″", "12 mm", "3″" of snow.
struct PrecipitationTotal: Equatable, Sendable {
    var kind: PrecipitationSpan.Kind
    /// Millimetres: of water for rain, of snow as it lies for snow.
    var amount: Double

    /// In the locale's unit for rain or snow (inches, millimetres, centimetres), to one decimal under 10 and whole
    /// above; "<0.1″" when there's some but it rounds to nothing.
    var text: String {
        text(locale: .current)
    }

    func text(locale: Locale) -> String {
        let usage: MeasurementFormatUnitUsage<UnitLength> = kind == .rain ? .rainfall : .snowfall
        let value = Measurement(value: amount, unit: UnitLength.millimeters)
            .converted(to: UnitLength(forLocale: locale, usage: usage))
        let digits = value.value < 9.95 ? 1 : 0
        let shown = (value.value * pow(10, Double(digits))).rounded() / pow(10, Double(digits))
        func format(_ number: Double) -> String {
            Measurement(value: number, unit: value.unit).formatted(.measurement(
                width: .narrow, usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(digits)).locale(locale)
            ).locale(locale))
        }
        return shown > 0 || amount == 0 ? format(shown) : "<" + format(0.1)
    }
}

/// A forecast day's low and high, in Celsius, and what falls that day.
struct ForecastDay: Codable, Sendable {
    var date: Date
    var low: Double
    var high: Double
    /// When it's likely enough to show; `nil` otherwise.
    var precipitation: PrecipitationSpan.Kind?
    /// `nil` on days the sun doesn't rise or set.
    var sunrise: Date?
    var sunset: Date?
}

/// The next sunrise or sunset.
struct SunEvent: Equatable, Sendable {
    var isSunrise: Bool
    var date: Date

    /// The first sunrise or sunset after `date` in `days`; `nil` when none is known.
    static func next(after date: Date, in days: [ForecastDay]) -> SunEvent? {
        days
            .flatMap { day in
                [
                    day.sunrise.map { SunEvent(isSunrise: true, date: $0) },
                    day.sunset.map { SunEvent(isSunrise: false, date: $0) },
                ].compactMap(\.self)
            }
            .filter { $0.date > date }
            .min { $0.date < $1.date }
    }
}

extension WeatherForecast {
    /// How likely rain or snow must be for an hour to count.
    static let precipitationThreshold = 0.3
    /// How long rain or snow falling now is counted out to before it reads "for 12h+".
    static let precipitationWindow: TimeInterval = 12 * 60 * 60
    /// A change smaller than this (Celsius, about 1 °F) doesn't count as the temperature turning around.
    static let turnTolerance = 0.5
    /// How close the day's forecast high or low must be to the hourly peak or trough to stand in for it.
    static let dayMatchTolerance = 2.0

    /// The next turning point after `date`, when it's `temperature`: the high it is still rising to, or the low it is
    /// falling to, within the next day. `nil` when the temperature holds steady that long.
    ///
    /// The value is the hourly forecast's peak or trough, unless that day's forecast high or low is close to it: then
    /// it's the day's value, which is what the Weather app shows (hourly temperatures tend to fall a degree short).
    /// A peak or trough far from the day's value isn't the day's extreme, like a low at 11 PM before a warmer night.
    static func nextExtreme(
        after date: Date,
        temperature: Double,
        hours: [ForecastHour],
        days: [ForecastDay]
    ) -> TemperatureExtreme? {
        let ahead = hours.filter { $0.date > date && $0.date <= date.addingTimeInterval(24 * 60 * 60) }
        guard let first = ahead.first(where: { abs($0.temperature - temperature) > turnTolerance }) else {
            return nil
        }
        let rising = first.temperature > temperature
        var extreme = ForecastHour(date: date, temperature: temperature)
        for hour in ahead {
            if rising ? hour.temperature > extreme.temperature : hour.temperature < extreme.temperature {
                extreme = hour
            } else if abs(hour.temperature - extreme.temperature) > turnTolerance {
                break
            }
        }
        let day = days.first { Calendar.current.isDate($0.date, inSameDayAs: extreme.date) }
        let dayValue = rising ? day?.high : day?.low
        let value = dayValue.flatMap { abs($0 - extreme.temperature) <= dayMatchTolerance ? $0 : nil }
            ?? extreme.temperature
        return TemperatureExtreme(temperature: value, isHigh: rising)
    }

    /// The rain and snow in the `window` after `date`: runs of consecutive minutes or hours of the same kind, clipped
    /// to the window. The minute forecast, where there is one, takes over from the hourly one for the
    /// time it covers. The minute or hour that `date` falls in counts from `date`. Both lists must be in order.
    static func precipitation(
        after date: Date,
        minutes: [ForecastMinute] = [],
        hours: [ForecastHour],
        window: TimeInterval = precipitationWindow
    ) -> [PrecipitationSpan] {
        let windowEnd = date.addingTimeInterval(window)
        let minutesEnd = minutes.last.map { $0.date.addingTimeInterval(60) } ?? date
        let minuteSlots = minutes.map {
            (start: $0.date, end: $0.date.addingTimeInterval(60), kind: $0.precipitation)
        }
        let hourSlots = hours.map {
            (start: max($0.date, minutesEnd), end: $0.date.addingTimeInterval(60 * 60), kind: $0.precipitation)
        }
        var spans: [PrecipitationSpan] = []
        for slot in minuteSlots + hourSlots {
            let start = max(slot.start, date)
            let end = min(slot.end, windowEnd)
            guard let kind = slot.kind, end > start else { continue }
            if let last = spans.last, last.kind == kind, last.end == start {
                spans[spans.count - 1].end = end
            } else {
                spans.append(PrecipitationSpan(kind: kind, start: start, end: end))
            }
        }
        return spans
    }

    /// How far ahead `outlook` looks for a day with rain or snow: less than a week, so the weekday is unambiguous.
    static let outlookDays = 6

    /// What to say at `date` about `spans` (from `precipitation(after: date, …)`): the rain or snow falling now and
    /// how long it lasts (up to the `precipitationWindow`), else the next one and how soon it starts. With none in
    /// `spans`, the first day after today in `days` with some. `nil` when there is none of either.
    static func outlook(at date: Date, spans: [PrecipitationSpan], days: [ForecastDay] = []) -> PrecipitationOutlook? {
        guard let span = spans.first(where: { $0.end > date }) else {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: date)
            let later = days.first { day in
                let offset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day.date)).day
                return day.precipitation != nil && (1 ... outlookDays).contains(offset ?? 0)
            }
            guard let later, let kind = later.precipitation else { return nil }
            return PrecipitationOutlook(kind: kind, timing: .onDay(later.date))
        }
        if span.start <= date {
            let lastsPastWindow = span.end >= date.addingTimeInterval(precipitationWindow)
            return PrecipitationOutlook(
                kind: span.kind,
                timing: lastsPastWindow ? .lastsPastWindow : .stopsIn(span.end.timeIntervalSince(date))
            )
        }
        return PrecipitationOutlook(kind: span.kind, timing: .startsIn(span.start.timeIntervalSince(date)))
    }
}

extension WeatherForecast {
    /// How far ahead the weather line looks for rain or snow, and `total` adds it up.
    static let totalWindow: TimeInterval = 24 * 60 * 60

    /// The `kind` expected in the `totalWindow` after `date`: water for rain, snow as it lies for snow. The hour
    /// that `date` falls in counts only for what's left of it. `nil` unless `hours` (in order) cover the whole window.
    static func total(of kind: PrecipitationSpan.Kind, after date: Date, hours: [ForecastHour]) -> PrecipitationTotal? {
        let windowEnd = date.addingTimeInterval(totalWindow)
        guard let last = hours.last, last.date.addingTimeInterval(60 * 60) >= windowEnd else { return nil }
        let amount = hours.reduce(0.0) { sum, hour in
            let start = max(hour.date, date)
            let end = min(hour.date.addingTimeInterval(60 * 60), windowEnd)
            guard end > start else { return sum }
            let perHour = kind == .rain ? hour.precipitationAmount : hour.snowfallAmount
            return sum + perHour * end.timeIntervalSince(start) / (60 * 60)
        }
        return PrecipitationTotal(kind: kind, amount: amount)
    }
}
