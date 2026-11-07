#if DEBUG
    import SwiftUI

    /// The battery and weather complications' faces at their size on a 41mm watch (45 pt), for sample entries.
    /// Real data rarely reaches the simulator (no battery, and WeatherKit usually fails there), so this is the way to
    /// see the faces there: `xcrun simctl launch <sim> com.danfoygel.complications.watchkitapp -complicationGallery`.
    /// The top row has a hairline at the complication's bounds.
    struct ComplicationGallery: View {
        private let side: CGFloat = 45

        var body: some View {
            VStack(spacing: 0) {
                Grid(horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        battery(0.65, phone: 0.95).overlay(bounds)
                        weather(3).overlay(bounds)
                        weather(0).overlay(bounds)
                    }
                    GridRow {
                        weather(1)
                        weather(2)
                        battery(0.5, phone: 0.4, phoneDate: .distantPast)
                    }
                    GridRow {
                        battery(0.08, phone: 0.3)
                        battery(1, phone: 0.08)
                        battery(0.82, phone: nil)
                    }
                }
                VStack(spacing: 2) {
                    ForEach(Array(Self.weatherLines.enumerated()), id: \.offset) { _, line in
                        WeatherLineView(line: line).frame(width: 162)
                    }
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        }

        /// Up Next's weather line at the 41mm rectangular width: rain ahead, snow falling, rain only later in the week,
        /// dry with unhealthy air.
        private static let weatherLines: [WeatherLine] = [
            WeatherLine(
                total: .init(kind: .rain, amount: 10), outlook: .init(kind: .rain, timing: .startsIn(3 * 3600))
            ),
            WeatherLine(total: .init(kind: .snow, amount: 76), outlook: .init(kind: .snow, timing: .lastsPastWindow)),
            WeatherLine(
                sun: .init(isSunrise: false, date: .now),
                outlook: .init(kind: .rain, timing: .onDay(.now.addingTimeInterval(3 * 24 * 3600)))
            ),
            WeatherLine(sun: .init(isSunrise: true, date: .now), airQuality: 164),
        ]

        private var bounds: some View {
            Circle().stroke(.red, lineWidth: 0.5)
        }

        private func weather(_ index: Int) -> some View {
            TemperatureView(weather: WeatherEntry.samples[index])
                .frame(width: side, height: side)
        }

        private func battery(_ level: Double, phone: Double?, phoneDate: Date = .now) -> some View {
            BatteryComplicationView(entry: BatteryEntry(
                date: .now,
                level: level,
                phone: phone.map { PhoneBatteryReading(date: phoneDate, level: $0, isPluggedIn: false) }
            ))
            .frame(width: side, height: side)
        }
    }

    #Preview {
        ComplicationGallery()
    }
#endif
