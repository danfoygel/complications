import Foundation

/// A forecast hour reduced to what the complication needs, so the logic below can be tested without WeatherKit.
struct ForecastHour: Sendable {
    /// The start of the hour.
    var date: Date
    /// Celsius.
    var temperature: Double
    /// What falls this hour, when it's likely enough to show; `nil` otherwise.
    var precipitation: PrecipitationSpan.Kind?
}

/// A forecast day's low and high, in Celsius.
struct ForecastDay: Sendable {
    var date: Date
    var low: Double
    var high: Double
}

extension WeatherForecast {
    /// How likely rain or snow must be for an hour to count.
    static let precipitationThreshold = 0.3
    /// How far ahead the clock ring shows rain or snow.
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

    /// The rain and snow in the `precipitationWindow` after `date`: runs of consecutive hours of the same kind,
    /// clipped to the window. The hour that `date` falls in counts from `date`. `hours` must be in order.
    static func precipitation(after date: Date, hours: [ForecastHour]) -> [PrecipitationSpan] {
        let windowEnd = date.addingTimeInterval(precipitationWindow)
        var spans: [PrecipitationSpan] = []
        for hour in hours {
            let hourEnd = hour.date.addingTimeInterval(60 * 60)
            guard let kind = hour.precipitation, hourEnd > date, hour.date < windowEnd else { continue }
            let start = max(hour.date, date)
            let end = min(hourEnd, windowEnd)
            if let last = spans.last, last.kind == kind, last.end == start {
                spans[spans.count - 1].end = end
            } else {
                spans.append(PrecipitationSpan(kind: kind, start: start, end: end))
            }
        }
        return spans
    }
}
