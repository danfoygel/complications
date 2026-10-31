import SwiftUI
import WidgetKit

/// The weather complication's face: a 12-hour clock ring with rain (solid) or snow (dotted) arcs where it's expected,
/// a dot at the current hour, and the current temperature over the next high (▲) or low (▼).
/// In `Shared/` so the app's debug gallery can show it too.
struct PrecipitationClock: View {
    let weather: WeatherEntry

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let line = side * 0.058
            let radius = (side - line) / 2
            ZStack {
                ring(radius: radius, line: line)
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    Circle()
                        .inset(by: line / 2)
                        .trim(from: arc.start, to: arc.end)
                        .stroke(
                            .cyan,
                            style: StrokeStyle(
                                lineWidth: line,
                                lineCap: .round,
                                dash: arc.kind == .snow ? [0.001, line * 1.45] : []
                            )
                        )
                        .rotationEffect(.degrees(-90))
                        .widgetAccentable()
                }
                Circle()
                    .fill(.white)
                    .stroke(.black, lineWidth: line * 0.33)
                    .frame(width: line * 1.45, height: line * 1.45)
                    .offset(x: radius * cos(nowAngle), y: radius * sin(nowAngle))
                // The negative spacing tucks the second line under the temperature's empty descender space.
                VStack(spacing: -side * 0.04) {
                    Text(Temperature.text(weather.temperature))
                        .font(.system(size: side * 0.44, weight: .bold, design: .rounded))
                        .tracking(-side * 0.013)
                    if let next = weather.next {
                        HStack(spacing: side * 0.02) {
                            Image(systemName: next.isHigh ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: side * 0.16, weight: .heavy))
                            Text(Temperature.number(next.temperature))
                                .font(.system(size: side * 0.27, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, side * 0.02)
            }
            .frame(width: side, height: side)
        }
    }

    /// The track with a tick at each hour.
    private func ring(radius: CGFloat, line: CGFloat) -> some View {
        let hour = 2 * .pi * radius / 12
        let tick = line * 0.18
        return ZStack {
            Circle().inset(by: line / 2).stroke(.white.opacity(0.17), lineWidth: line)
            Circle().inset(by: line / 2)
                .stroke(
                    .white.opacity(0.38),
                    style: StrokeStyle(lineWidth: line, dash: [tick, hour - tick], dashPhase: tick / 2)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    /// Where `date` falls on a 12-hour dial, from 0 at 12 o'clock to 1 back at 12.
    private func dial(_ date: Date) -> CGFloat {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (CGFloat((parts.hour ?? 0) % 12) + CGFloat(parts.minute ?? 0) / 60) / 12
    }

    private var nowAngle: CGFloat {
        dial(weather.date) * 2 * .pi - .pi / 2
    }

    private struct Arc {
        var kind: PrecipitationSpan.Kind
        var start: CGFloat
        var end: CGFloat
    }

    /// Each span as trim fractions, split in two where it passes 12 o'clock.
    private var arcs: [Arc] {
        (weather.precipitation ?? []).flatMap { span -> [Arc] in
            let start = dial(span.start)
            let end = start + min(span.end.timeIntervalSince(span.start) / (12 * 3600), 1)
            return end <= 1
                ? [Arc(kind: span.kind, start: start, end: end)]
                : [Arc(kind: span.kind, start: start, end: 1), Arc(kind: span.kind, start: 0, end: end - 1)]
        }
    }
}

extension WeatherEntry {
    /// The four cases on the design canvas: rain coming, raining now, dry, snow coming.
    static let samples: [WeatherEntry] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ hour: Int) -> Date {
            calendar.date(byAdding: .hour, value: hour, to: today)!
        }
        func fahrenheit(_ value: Double) -> Double {
            (value - 32) * 5 / 9
        }
        /// Temperatures in Fahrenheit; the symbol and condition aren't on the face, so they're placeholders.
        func entry(
            now: Int, temperature: Double, range: ClosedRange<Double>, nextIsHigh: Bool,
            precipitation: [PrecipitationSpan] = []
        ) -> WeatherEntry {
            WeatherEntry(
                date: at(now),
                temperature: fahrenheit(temperature),
                low: fahrenheit(range.lowerBound),
                high: fahrenheit(range.upperBound),
                symbolName: "cloud",
                condition: "",
                next: TemperatureExtreme(
                    temperature: fahrenheit(nextIsHigh ? range.upperBound : range.lowerBound),
                    isHigh: nextIsHigh
                ),
                precipitation: precipitation
            )
        }
        return [
            entry(
                now: 11, temperature: 64, range: 52 ... 71, nextIsHigh: true,
                precipitation: [PrecipitationSpan(kind: .rain, start: at(14), end: at(17))]
            ),
            entry(
                now: 18, temperature: 55, range: 48 ... 61, nextIsHigh: false,
                precipitation: [PrecipitationSpan(kind: .rain, start: at(18), end: at(21))]
            ),
            entry(now: 10, temperature: 78, range: 61 ... 84, nextIsHigh: true),
            entry(
                now: 15, temperature: 31, range: 24 ... 36, nextIsHigh: false,
                precipitation: [PrecipitationSpan(kind: .snow, start: at(21), end: at(24))]
            ),
        ]
    }()
}
