import SwiftUI
import WidgetKit

/// The bottom line of Up Next: the next sunrise or sunset at the left, the nearest rain or snow at the right.
struct WeatherLine: Equatable, Sendable {
    var sun: SunEvent?
    var outlook: PrecipitationOutlook?

    init(sun: SunEvent?, outlook: PrecipitationOutlook?) {
        self.sun = sun
        self.outlook = outlook
    }

    /// What to show at `date` from `forecast`. The rain or snow is left out once the hourly forecast no longer covers
    /// the 12 hours ahead, rather than calling it dry. `nil` when there's nothing to show.
    init?(at date: Date, forecast: PrecipitationForecast) {
        sun = SunEvent.next(after: date, in: forecast.days)
        let hoursEnd = forecast.hours.last.map { $0.date.addingTimeInterval(60 * 60) } ?? date
        if hoursEnd >= date.addingTimeInterval(WeatherForecast.precipitationWindow) {
            let spans = WeatherForecast.precipitation(after: date, minutes: forecast.minutes, hours: forecast.hours)
            outlook = WeatherForecast.outlook(at: date, spans: spans, days: forecast.days)
        }
        if sun == nil, outlook == nil {
            return nil
        }
    }

    /// The times after `now` when the line from `forecast` changes: each sunrise and sunset, and each 5-minute mark
    /// within the `precipitationWindow` where the rain or snow reads differently from the mark before. Every other
    /// mark would be an entry that looks just like the last, which the watch still has to render.
    static func changes(after now: Date, forecast: PrecipitationForecast) -> [Date] {
        let step: TimeInterval = 5 * 60
        let firstMark = (now.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        // What the right side reads; the outlook itself holds exact intervals, which differ at every mark.
        func reading(at date: Date) -> String? {
            WeatherLine(at: date, forecast: forecast)?.outlook.map { "\($0.kind.rawValue) \($0.text)" }
        }
        var shown = reading(at: now)
        var marks: [Date] = []
        for index in 0 ..< Int(WeatherForecast.precipitationWindow / step) {
            let mark = Date(timeIntervalSinceReferenceDate: firstMark + Double(index) * step)
            let current = reading(at: mark)
            if current != shown {
                marks.append(mark)
                shown = current
            }
        }
        return marks + forecast.days.flatMap { [$0.sunrise, $0.sunset].compactMap(\.self) }
    }
}

/// Times as Up Next shows them: the locale's format without AM/PM, which takes too much width.
enum ClockTime {
    /// "9:05", or "09:05" in 24-hour locales. (`.hour(.defaultDigits(amPM: .omitted))` gives "09:05" in en_US.)
    static let format =
        (DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "j:mm")
            .replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces)

    static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

/// In `Shared/` so the app's debug gallery can show it too.
struct WeatherLineView: View {
    let line: WeatherLine

    var body: some View {
        HStack(spacing: 3) {
            if let sun = line.sun {
                SunSymbol(isSunrise: sun.isSunrise)
                    .foregroundStyle(.orange)
                    .widgetAccentable()
                Text(ClockTime.string(sun.date))
            }
            Spacer(minLength: 4)
            if let outlook = line.outlook {
                Image(systemName: outlook.kind == .rain ? "cloud.rain.fill" : "snowflake")
                    .foregroundStyle(.cyan)
                    .widgetAccentable()
                Text(outlook.text)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// A sun with a small triangle cut out of its disc: up before a sunrise, down before a sunset.
struct SunSymbol: View {
    let isSunrise: Bool

    var body: some View {
        ZStack {
            Image(systemName: "sun.max.fill")
            Image(systemName: isSunrise ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 5, weight: .black))
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}

extension PrecipitationForecast {
    /// Rain from noon to 3 p.m. today and the usual sunrise and sunset, for previews and the debug gallery.
    static let sample: PrecipitationForecast = {
        let today = Calendar.current.startOfDay(for: .now)
        func at(_ hour: Double) -> Date {
            today.addingTimeInterval(hour * 3600)
        }
        return PrecipitationForecast(
            minutes: [],
            hours: (0 ..< 48).map { hour in
                ForecastHour(
                    date: at(Double(hour)), temperature: 15, precipitation: (12 ..< 15).contains(hour) ? .rain : nil
                )
            },
            days: (0 ..< 7).map { day in
                ForecastDay(
                    date: at(Double(day * 24)), low: 8, high: 16, precipitation: day == 3 ? .rain : nil,
                    sunrise: at(Double(day * 24) + 7.35), sunset: at(Double(day * 24) + 17.7)
                )
            }
        )
    }()
}
