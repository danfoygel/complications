import Foundation
import Testing

struct BackoffTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let here = PhoneLocation(date: .distantPast, latitude: 37.77, longitude: -122.42)

    @Test func waitsLongerAfterEachFailureUpToTwoHours() throws {
        let defaults = try #require(UserDefaults(suiteName: "BackoffTests"))
        defaults.removePersistentDomain(forName: "BackoffTests")
        #expect(throws: Never.self) { try Backoff.check("fetch", at: start, for: here, in: defaults) }

        Backoff.recordFailure("fetch", at: start, for: here, in: defaults)
        #expect(throws: Backoff.Waiting.self) {
            try Backoff.check("fetch", at: start.addingTimeInterval(14 * 60), for: here, in: defaults)
        }
        #expect(throws: Never.self) {
            try Backoff.check("fetch", at: start.addingTimeInterval(15 * 60), for: here, in: defaults)
        }
        for _ in 0 ..< 5 {
            Backoff.recordFailure("fetch", at: start, for: here, in: defaults)
        }
        #expect(Backoff.load("fetch", from: defaults)?.wait == Backoff.longest)

        Backoff.reset("fetch", in: defaults)
        #expect(throws: Never.self) { try Backoff.check("fetch", at: start, for: here, in: defaults) }
    }

    @Test func aMoveStartsOver() throws {
        let defaults = try #require(UserDefaults(suiteName: "BackoffMoveTests"))
        defaults.removePersistentDomain(forName: "BackoffMoveTests")
        Backoff.recordFailure("fetch", at: start, for: here, in: defaults)
        var away = here
        away.latitude += 0.05 // About 5.6 km north.
        #expect(throws: Never.self) { try Backoff.check("fetch", at: start, for: away, in: defaults) }
        Backoff.recordFailure("fetch", at: start, for: away, in: defaults)
        #expect(Backoff.load("fetch", from: defaults)?.failures == 1)
    }
}
