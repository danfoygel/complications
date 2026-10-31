#if DEBUG
    import SwiftUI

    /// The battery and weather complications' faces at their size on a 41mm watch (45 pt), for sample entries.
    /// Real data rarely reaches the simulator (no battery, and WeatherKit usually fails there), so this is the way to
    /// see the faces there: `xcrun simctl launch <sim> com.danfoygel.complications.watchkitapp -complicationGallery`.
    /// The top row has a hairline at the complication's bounds.
    struct ComplicationGallery: View {
        private let side: CGFloat = 45

        var body: some View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        }

        private var bounds: some View {
            Circle().stroke(.red, lineWidth: 0.5)
        }

        private func weather(_ index: Int) -> some View {
            PrecipitationClock(weather: WeatherEntry.samples[index])
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
