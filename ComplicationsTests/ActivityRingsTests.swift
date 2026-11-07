import Foundation
import Testing

struct ActivityRingsTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 7))!
    }

    @Test func progressLapsPastTheGoal() {
        #expect(ActivityRings.Ring(value: 250, goal: 500).progress == 0.5)
        #expect(ActivityRings.Ring(value: 1250, goal: 500).progress == 2.5)
        // No goal and a stray negative both leave the ring empty.
        #expect(ActivityRings.Ring(value: 10, goal: 0).progress == 0)
        #expect(ActivityRings.Ring(value: -1, goal: 30).progress == 0)
    }

    @Test func emptiesAtMidnightKeepingTheGoals() throws {
        var rings = ActivityRings.sample
        rings.day = day
        rings.isPaused = true
        let now = day.addingTimeInterval(20 * 3600)
        let entries = ActivitySummaries.entries(for: rings, now: now, calendar: calendar)
        #expect(entries.map(\.date) == [now, day.addingTimeInterval(24 * 3600)])
        #expect(entries[0].rings == rings)
        let reset = try #require(entries[1].rings)
        #expect(reset.day == day.addingTimeInterval(24 * 3600))
        #expect([reset.move.value, reset.exercise.value, reset.stand.value] == [0, 0, 0])
        #expect(reset.move.goal == rings.move.goal && reset.stand.goal == rings.stand.goal)
        #expect(!reset.isPaused)
    }

    @Test func yesterdaysRingsStartEmpty() throws {
        var rings = ActivityRings.sample
        rings.day = day
        let tomorrow = day.addingTimeInterval(24 * 3600)
        let entries = ActivitySummaries.entries(for: rings, now: tomorrow.addingTimeInterval(3600), calendar: calendar)
        let first = try #require(entries.first?.rings)
        #expect(first.day == tomorrow)
        #expect(first.move.progress == 0)
        #expect(ActivitySummaries.entries(for: nil, now: tomorrow, calendar: calendar).map(\.rings) == [nil])
    }

    @Test func savedRingsRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "ActivityRingsTests"))
        defaults.removePersistentDomain(forName: "ActivityRingsTests")
        #expect(ActivitySummaries.saved(in: defaults) == nil)
        defaults.set(try JSONEncoder().encode(ActivityRings.sample), forKey: "activityRings")
        #expect(ActivitySummaries.saved(in: defaults) == .sample)
    }
}
