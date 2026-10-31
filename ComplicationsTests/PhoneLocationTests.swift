import CoreLocation
import Foundation
import Testing

struct PhoneLocationTests {
    private let base = PhoneLocation(
        date: Date(timeIntervalSince1970: 1_800_000_000), latitude: 37.77, longitude: -122.42
    )

    @Test func travelsInAMessage() throws {
        let decoded = try #require(PhoneLocation(message: base.message))
        #expect(decoded == base)
        #expect(PhoneLocation(message: PhoneBatteryReading(date: .now, level: 0.5, isPluggedIn: false).message) == nil)
    }

    @Test func farOnlyAfterASignificantMove() {
        var nearby = base
        nearby.latitude += 0.01 // About 1.1 km north.
        var away = base
        away.latitude += 0.05 // About 5.6 km north.
        #expect(base.isFar(from: nil))
        #expect(!nearby.isFar(from: base))
        #expect(away.isFar(from: base))
    }

    @Test func keepsTheNewest() throws {
        let defaults = try #require(UserDefaults(suiteName: "PhoneLocationTests"))
        defaults.removePersistentDomain(forName: "PhoneLocationTests")
        #expect(PhoneLocation.saved(in: defaults) == nil)

        #expect(base.save(in: defaults))
        var older = base
        older.date = base.date.addingTimeInterval(-60)
        older.latitude = 0
        #expect(!older.save(in: defaults))
        #expect(PhoneLocation.saved(in: defaults) == base)
    }
}
