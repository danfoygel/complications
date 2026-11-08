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

struct ActivityHoursTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func addsValuesUpByHour() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7))!
        let minute = { (minutes: Double) in day.addingTimeInterval(minutes * 60) }
        let slots = ActivityHours.buckets(
            [
                (minute(5), 10), (minute(50), 2.5), (minute(6 * 60 + 1), 30), (minute(23 * 60 + 59), 1),
                // The days either side.
                (minute(-1), 99), (minute(24 * 60), 99),
            ],
            day: day,
            calendar: calendar
        )
        #expect(slots.count == 24)
        #expect(slots[0] == 12.5)
        #expect(slots[6] == 30)
        #expect(slots[23] == 1)
        #expect(slots.reduce(0, +) == 43.5)
    }
}
