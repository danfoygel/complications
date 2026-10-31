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

/// The top half of a sun (with both horizontal rays) over a small ▼ before a sunset; flipped, a ▲ over the bottom
/// half before a sunrise.
struct SunSymbol: View {
    let isSunrise: Bool

    var body: some View {
        Image(systemName: "sun.max.fill")
            .mask(HalfSunMask())
            .overlay(SunsetTriangle().fill())
            .scaleEffect(y: isSunrise ? -1 : 1)
    }
}

/// The top half of `sun.max.fill`'s bounds, plus a strip at the middle of each side for the horizontal rays.
private struct HalfSunMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
        // The rays end 0.18 of the width in from each side and the disc starts at 0.26.
        let strip = CGSize(width: rect.width * 0.22, height: rect.height * 0.12)
        let stripY = rect.midY - strip.height / 2
        path.addRect(CGRect(origin: CGPoint(x: rect.minX, y: stripY), size: strip))
        path.addRect(CGRect(origin: CGPoint(x: rect.maxX - strip.width, y: stripY), size: strip))
        return path
    }
}

/// A ▼ in the bottom half, a little below the cut and narrower than the disc.
private struct SunsetTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let top = rect.minY + rect.height * 0.61
        let halfWidth = rect.width * 0.17
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - halfWidth, y: top))
        path.addLine(to: CGPoint(x: rect.midX + halfWidth, y: top))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.83))
        path.closeSubpath()
        return path
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
