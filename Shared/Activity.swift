import Foundation
import HealthKit
import WidgetKit

/// A day's Move, Exercise and Stand rings, copied out of HealthKit's `HKActivitySummary` so they can cross actors, live
/// in timeline entries and be saved in the app group.
struct ActivityRings: Codable, Equatable, Sendable {
    /// The start of the day these are for.
    var day: Date
    var move: Ring
    var exercise: Ring
    var stand: Ring
    /// Whether the Move ring counts active calories or, for those who chose Move time, minutes.
    var moveUnit: MoveUnit = .calories
    /// Rings paused for the day in the Activity app.
    var isPaused = false

    enum MoveUnit: String, Codable, Sendable {
        case calories
        case minutes
    }

    struct Ring: Codable, Equatable, Sendable {
        var value: Double
        var goal: Double

        /// How far round the ring is: 1 is closed, past 1 it laps itself.
        var progress: Double {
            goal > 0 ? max(value, 0) / goal : 0
        }
    }

    /// The same goals with nothing done yet, as the rings start each day.
    func reset(to day: Date) -> ActivityRings {
        var rings = self
        rings.day = day
        rings.move.value = 0
        rings.exercise.value = 0
        rings.stand.value = 0
        rings.isPaused = false
        return rings
    }
}

struct ActivityEntry: TimelineEntry {
    var date: Date
    /// `nil` before the first summary has been read (no access yet): just the empty tracks.
    var rings: ActivityRings?
}

enum ActivitySummaries {
    private static let store = HKHealthStore()
    private static let types: Set<HKObjectType> = [.activitySummaryType()]
    private static let key = "activityRings"

    /// Asks for access the first time; afterwards it returns without prompting. HealthKit never says whether reading
    /// was allowed, so a refusal only shows as summaries that never come.
    static func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [], read: types)
    }

    /// Today's rings from HealthKit, saved for when HealthKit can't be read; `nil` when there's no summary for today
    /// (no access, or the day's has yet to be written).
    static func today(now: Date = .now, calendar: Calendar = .current) async throws -> ActivityRings? {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: now)
        components.calendar = calendar
        let query = HKActivitySummaryQueryDescriptor(predicate: HKQuery.predicateForActivitySummary(with: components))
        guard let summary = try await query.result(for: store).first else { return nil }
        let rings = ActivityRings(summary, day: calendar.startOfDay(for: now))
        AppGroup.defaults.set(try? JSONEncoder().encode(rings), forKey: key)
        return rings
    }

    /// Today's rings, or the last ones read when HealthKit can't be read (the extension sometimes can't), back to empty
    /// if they're from an earlier day.
    static func latest(now: Date = .now, calendar: Calendar = .current) async -> ActivityRings? {
        if let rings = try? await today(now: now, calendar: calendar) {
            return rings
        }
        return current(saved(), now: now, calendar: calendar)
    }

    static func saved(in defaults: UserDefaults = AppGroup.defaults) -> ActivityRings? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ActivityRings.self, from: $0) }
    }

    /// `rings` as they stand at `now`: emptied, goals kept, once their day is over.
    static func current(_ rings: ActivityRings?, now: Date, calendar: Calendar = .current) -> ActivityRings? {
        guard let rings else { return nil }
        let today = calendar.startOfDay(for: now)
        return rings.day < today ? rings.reset(to: today) : rings
    }

    /// `rings` now, then empty from the next midnight on, so the face starts the day over even when the next reload is
    /// late.
    static func entries(for rings: ActivityRings?, now: Date, calendar: Calendar = .current) -> [ActivityEntry] {
        let rings = current(rings, now: now, calendar: calendar)
        guard let rings, let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        else { return [ActivityEntry(date: now, rings: rings)] }
        return [ActivityEntry(date: now, rings: rings), ActivityEntry(date: midnight, rings: rings.reset(to: midnight))]
    }
}

extension ActivityRings {
    init(_ summary: HKActivitySummary, day: Date) {
        let calories = HKUnit.kilocalorie()
        let minutes = HKUnit.minute()
        let hours = HKUnit.count()
        let isMoveTime = summary.activityMoveMode == .appleMoveTime
        self.init(
            day: day,
            move: isMoveTime
                ? Ring(
                    value: summary.appleMoveTime.doubleValue(for: minutes),
                    goal: summary.appleMoveTimeGoal.doubleValue(for: minutes)
                )
                : Ring(
                    value: summary.activeEnergyBurned.doubleValue(for: calories),
                    goal: summary.activeEnergyBurnedGoal.doubleValue(for: calories)
                ),
            exercise: Ring(
                value: summary.appleExerciseTime.doubleValue(for: minutes),
                goal: summary.exerciseTimeGoal?.doubleValue(for: minutes) ?? 30
            ),
            stand: Ring(
                value: summary.appleStandHours.doubleValue(for: hours),
                goal: summary.standHoursGoal?.doubleValue(for: hours) ?? 12
            ),
            moveUnit: isMoveTime ? .minutes : .calories,
            isPaused: summary.isPaused
        )
    }

    /// Partway through a day: Move closed and lapping, Exercise most of the way, Stand under half.
    static let sample = ActivityRings(
        day: Calendar.current.startOfDay(for: .now),
        move: Ring(value: 640, goal: 500),
        exercise: Ring(value: 24, goal: 30),
        stand: Ring(value: 5, goal: 12)
    )
}
