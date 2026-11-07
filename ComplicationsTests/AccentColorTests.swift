import Foundation
import SwiftUI
import Testing

struct AccentColorTests {
    private let pink = AccentColor(date: Date(timeIntervalSince1970: 1_800_000_000), red: 1, green: 0.216, blue: 0.373)

    @Test func travelsInAMessage() throws {
        let decoded = try #require(AccentColor(message: pink.message))
        #expect(decoded == pink)
        #expect(AccentColor(message: PhoneBatteryReading(date: .now, level: 0.5, isPluggedIn: false).message) == nil)
    }

    @Test func keepsTheNewest() throws {
        let defaults = try #require(UserDefaults(suiteName: "AccentColorTests"))
        defaults.removePersistentDomain(forName: "AccentColorTests")
        #expect(AccentColor.saved(in: defaults) == nil)

        #expect(pink.save(in: defaults))
        var older = pink
        older.date = pink.date.addingTimeInterval(-60)
        older.green = 1
        #expect(!older.save(in: defaults))
        #expect(AccentColor.saved(in: defaults) == pink)
        // The standard orange is never newer than a pick.
        #expect(!AccentColor.standard.save(in: defaults))
    }

    @Test func batteryColorFollowsTheLevel() {
        #expect(BatteryComplicationView.color(for: 1) == .green)
        #expect(BatteryComplicationView.color(for: 0.51) == .green)
        #expect(BatteryComplicationView.color(for: 0.5) == .yellow)
        #expect(BatteryComplicationView.color(for: 0.21) == .yellow)
        #expect(BatteryComplicationView.color(for: 0.2) == .red)
        #expect(BatteryComplicationView.color(for: 0) == .red)
        #expect(BatteryComplicationView.color(for: nil) == .gray)
    }
}
