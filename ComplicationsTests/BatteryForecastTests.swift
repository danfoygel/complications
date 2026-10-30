import Foundation
import Testing

struct BatteryForecastTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func reading(minutes: Double, level: Double, pluggedIn: Bool = false) -> BatteryReading {
        BatteryReading(date: start.addingTimeInterval(minutes * 60), level: level, isPluggedIn: pluggedIn)
    }

    @Test func noRateUntilReadingsSpanTenMinutes() {
        #expect(BatteryForecast.rate([reading(minutes: 0, level: 0.8), reading(minutes: 5, level: 0.79)]) == nil)
        #expect(BatteryForecast.rate([reading(minutes: 0, level: 0.8), reading(minutes: 10, level: 0.79)]) != nil)
    }

    @Test func noRateWhenLevelMovesAgainstChargerState() {
        let rising = [reading(minutes: 0, level: 0.5), reading(minutes: 20, level: 0.6)]
        #expect(BatteryForecast.rate(rising) == nil)
        #expect(BatteryForecast.rate(rising.map { BatteryReading(date: $0.date, level: $0.level, isPluggedIn: true) })
            != nil)
    }

    @Test func timeRemainingOnBattery() throws {
        // 1% every 6 minutes from 50%: 300 minutes to empty.
        let history = [reading(minutes: 0, level: 0.52), reading(minutes: 12, level: 0.5)]
        let remaining = try #require(BatteryForecast.timeRemaining(history))
        #expect(abs(remaining - 300 * 60) < 1)
    }

    @Test func timeRemainingWhileCharging() throws {
        // 1% a minute from 90%: 10 minutes to full.
        let history = [
            reading(minutes: 0, level: 0.8, pluggedIn: true),
            reading(minutes: 10, level: 0.9, pluggedIn: true),
        ]
        let remaining = try #require(BatteryForecast.timeRemaining(history))
        #expect(abs(remaining - 10 * 60) < 1)
    }

    @Test func entriesStepOnePercentAtATime() {
        // 1% every 6 minutes, so 10 more entries in the next hour.
        let history = [reading(minutes: 0, level: 0.52), reading(minutes: 12, level: 0.5)]
        let entries = BatteryForecast.entries(for: history, until: start.addingTimeInterval(72 * 60))
        #expect(entries.map(\.percent) == [50, 49, 48, 47, 46, 45, 44, 43, 42, 41, 40])
        #expect(zip(entries, entries.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    @Test func recordStartsOverWhenChargerChanges() throws {
        let defaults = try #require(UserDefaults(suiteName: "BatteryForecastTests"))
        defaults.removePersistentDomain(forName: "BatteryForecastTests")
        _ = BatteryForecast.record(reading(minutes: 0, level: 0.5), in: defaults)
        #expect(BatteryForecast.record(reading(minutes: 5, level: 0.49), in: defaults).count == 2)
        #expect(BatteryForecast.record(reading(minutes: 6, level: 0.49, pluggedIn: true), in: defaults).count == 1)
    }
}

struct RouteTests {
    @Test func urlRoundTrips() throws {
        for route in Route.allCases {
            #expect(Route(url: route.url) == route)
        }
        #expect(try Route(url: #require(URL(string: "https://battery"))) == nil)
        #expect(try Route(url: #require(URL(string: "complications://nope"))) == nil)
    }
}
