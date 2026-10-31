import SwiftUI
import WidgetKit

/// The weather complication's face: the current temperature over the next high (▲) or low (▼), on the standard
/// circular background.
/// In `Shared/` so the app's debug gallery can show it too.
struct TemperatureView: View {
    let weather: WeatherEntry

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                AccessoryWidgetBackground()
                // Text sizes are in points, for the 41mm watch, where the complication is 45 pt across.
                // The negative spacing tucks the second line under the temperature's empty descender space.
                VStack(spacing: -side * 0.04) {
                    Text(Temperature.text(weather.temperature))
                        .font(.system(size: 20, weight: .bold))
                        .tracking(-0.6)
                    if let next = weather.next {
                        HStack(spacing: side * 0.02) {
                            Image(systemName: next.isHigh ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 7, weight: .heavy))
                            Text(Temperature.number(next.temperature))
                                .font(.system(size: 12, weight: .heavy))
                        }
                        .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, side * 0.06)
                .padding(.top, side * 0.02)
            }
            .frame(width: side, height: side)
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
