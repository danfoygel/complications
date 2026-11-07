import SwiftUI
import Synchronization
import WidgetKit

/// The bottom line of Up Next. With rain or snow in the next 24 hours: the total for them at the left and when it
/// starts or stops at the right. With some only later in the week: the next sunrise or sunset at the left and the day
/// at the right ("on Tu"). Otherwise: the next sunrise or sunset at the left and the air quality at the right.
struct WeatherLine: Equatable, Sendable {
    /// Left, unless there's rain or snow in the next 24 hours.
    var sun: SunEvent?
    /// Left, with rain or snow in the next 24 hours.
    var total: PrecipitationTotal?
    /// Right, with rain or snow in the next week.
    var outlook: PrecipitationOutlook?
    /// Right, when it's dry: the US AQI for the hour.
    var airQuality: Int?

    init(
        sun: SunEvent? = nil, total: PrecipitationTotal? = nil, outlook: PrecipitationOutlook? = nil,
        airQuality: Int? = nil
    ) {
        self.sun = sun
        self.total = total
        self.outlook = outlook
        self.airQuality = airQuality
    }

    /// What to show at `date` from `forecast`. Rain or snow is looked for only while the hourly forecast covers the
    /// 24 hours ahead, rather than calling it dry. `nil` when there's nothing to show.
    init?(at date: Date, forecast: PrecipitationForecast) {
        let hoursEnd = forecast.hours.last.map { $0.date.addingTimeInterval(60 * 60) } ?? date
        if hoursEnd >= date.addingTimeInterval(WeatherForecast.totalWindow) {
            let spans = WeatherForecast.precipitation(
                after: date, minutes: forecast.minutes, hours: forecast.hours, window: WeatherForecast.totalWindow
            )
            outlook = WeatherForecast.outlook(at: date, spans: spans, days: forecast.days)
        }
        switch outlook?.timing {
        case nil:
            airQuality = AirQuality.reading(at: date, in: forecast.airQuality)?.aqi
        case .onDay:
            break
        default:
            total = outlook.flatMap { WeatherForecast.total(of: $0.kind, after: date, hours: forecast.hours) }
        }
        if total == nil {
            sun = SunEvent.next(after: date, in: forecast.days)
        }
        if sun == nil, total == nil, outlook == nil, airQuality == nil {
            return nil
        }
    }

    /// The times after `now` when the line from `forecast` changes: each sunrise and sunset, each hour of air
    /// quality, and each 5-minute mark within the `totalWindow` where the rain or snow reads differently
    /// from the mark before. Every other mark would be an entry that looks just like the last, which the watch still
    /// has to render.
    static func changes(after now: Date, forecast: PrecipitationForecast) -> [Date] {
        let step: TimeInterval = 5 * 60
        let firstMark = (now.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        // What the line reads; the outlook itself holds exact intervals, which differ at every mark.
        func reading(at date: Date) -> String? {
            WeatherLine(at: date, forecast: forecast).map { line in
                [
                    line.total.map { "\($0.kind.rawValue) \($0.text)" },
                    line.outlook.map { "\($0.kind.rawValue) \($0.text)" },
                    line.airQuality.map { "AQI \($0)" },
                ].map { $0 ?? "-" }.joined(separator: " ")
            }
        }
        var shown = reading(at: now)
        var marks: [Date] = []
        for index in 0 ..< Int(WeatherForecast.totalWindow / step) {
            let mark = Date(timeIntervalSinceReferenceDate: firstMark + Double(index) * step)
            let current = reading(at: mark)
            if current != shown {
                marks.append(mark)
                shown = current
            }
        }
        return marks + forecast.days.flatMap { [$0.sunrise, $0.sunset].compactMap(\.self) }
            + forecast.airQuality.map(\.date)
    }
}

/// Times as Up Next shows them: the locale's format without AM/PM, which takes too much width.
enum ClockTime {
    /// "9:05", or "09:05" in 24-hour locales. (`.hour(.defaultDigits(amPM: .omitted))` gives "09:05" in en_US.)
    /// Read each time, so switching between 12- and 24-hour time shows at the next render, not the extension's next
    /// launch.
    static var format: String {
        (DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .autoupdatingCurrent) ?? "j:mm")
            .replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func string(_ date: Date) -> String {
        string(date, format: format)
    }

    /// `date` in `format`, with `amSymbol` and `pmSymbol` when given. Formatters are slow to make and a timeline
    /// draws many entries, so each one is made once and kept.
    static func string(_ date: Date, format: String, amSymbol: String? = nil, pmSymbol: String? = nil) -> String {
        let key = [Locale.autoupdatingCurrent.identifier, format, amSymbol ?? "", pmSymbol ?? ""].joined(separator: "|")
        return formatters.withLock { formatters in
            let formatter = formatters[key] ?? {
                let formatter = DateFormatter()
                formatter.locale = .autoupdatingCurrent
                formatter.dateFormat = format
                if let amSymbol, let pmSymbol {
                    formatter.amSymbol = amSymbol
                    formatter.pmSymbol = pmSymbol
                }
                return formatter
            }()
            formatters[key] = formatter
            return formatter.string(from: date)
        }
    }

    private static let formatters = Mutex<[String: DateFormatter]>([:])
}

/// In `Shared/` so the app's debug gallery can show it too. Every symbol is in the accent color.
struct WeatherLineView: View {
    let line: WeatherLine
    @Environment(\.complicationAccent) private var accent

    var body: some View {
        HStack(spacing: 3) {
            if let total = line.total {
                symbol(Image(systemName: total.kind == .rain ? "drop.fill" : "snowflake"))
                Text(total.text)
            } else if let sun = line.sun {
                symbol(SunSymbol(isSunrise: sun.isSunrise))
                Text(ClockTime.string(sun.date))
            }
            Spacer(minLength: 4)
            if let outlook = line.outlook {
                symbol(Image(systemName: outlook.kind == .rain ? "cloud.rain.fill" : "snowflake"))
                Text(outlook.text)
            } else if let aqi = line.airQuality {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    symbol(Text("AQI").font(.system(size: 11, weight: .semibold)))
                    Text("\(aqi)")
                }
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
    }

    private func symbol(_ view: some View) -> some View {
        view
            .foregroundStyle(accent)
            .widgetAccentable()
    }
}

/// An arrow whose head sits where `sun.max.fill`'s disc was, with that half's rays around it: pointing up before a
/// sunrise, flipped to point down before a sunset. Slightly blurred so it reads as soft as the rays at 15 pt.
struct SunSymbol: View {
    let isSunrise: Bool

    var body: some View {
        Image(systemName: "sun.max.fill")
            .mask(SunRaysMask())
            .overlay(SunArrow().fill())
            .scaleEffect(y: isSunrise ? 1 : -1)
            .blur(radius: 0.4)
    }
}

/// The rays of `sun.max.fill`'s top half, including the horizontal ones, without its disc.
private struct SunRaysMask: Shape {
    func path(in rect: CGRect) -> Path {
        var half = Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
        // The rays end 0.18 of the width in from each side and the disc starts at 0.26.
        let strip = CGSize(width: rect.width * 0.22, height: rect.height * 0.12)
        let stripY = rect.midY - strip.height / 2
        half.addRect(CGRect(origin: CGPoint(x: rect.minX, y: stripY), size: strip))
        half.addRect(CGRect(origin: CGPoint(x: rect.maxX - strip.width, y: stripY), size: strip))
        let radius = rect.width * 0.27
        let disc = Path(ellipseIn: CGRect(
            x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2
        ))
        return half.subtracting(disc)
    }
}

/// An up arrow: a ▲ in the disc's place, its base on the middle line, and a stem down into the bottom half.
private struct SunArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let halfBase = rect.width * 0.25
        path.move(to: CGPoint(x: rect.midX - halfBase, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + halfBase, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.27))
        path.closeSubpath()
        let stemWidth = rect.width * 0.13
        path.addRect(CGRect(
            x: rect.midX - stemWidth / 2, y: rect.midY,
            width: stemWidth, height: rect.minY + rect.height * 0.86 - rect.midY
        ))
        return path
    }
}

extension PrecipitationForecast {
    /// Rain from noon to 3 p.m. today, the usual sunrise and sunset, and good air, for previews and the debug gallery.
    static let sample: PrecipitationForecast = {
        let today = Calendar.current.startOfDay(for: .now)
        func at(_ hour: Double) -> Date {
            today.addingTimeInterval(hour * 3600)
        }
        return PrecipitationForecast(
            minutes: [],
            hours: (0 ..< 48).map { hour in
                ForecastHour(
                    date: at(Double(hour)), temperature: 15, precipitation: (12 ..< 15).contains(hour) ? .rain : nil,
                    precipitationAmount: (12 ..< 15).contains(hour) ? 3.5 : 0
                )
            },
            days: (0 ..< 7).map { day in
                ForecastDay(
                    date: at(Double(day * 24)), low: 8, high: 16, precipitation: day == 3 ? .rain : nil,
                    sunrise: at(Double(day * 24) + 7.35), sunset: at(Double(day * 24) + 17.7)
                )
            },
            airQuality: (0 ..< 48).map { AirQualityReading(date: at(Double($0)), aqi: 38) }
        )
    }()
}
