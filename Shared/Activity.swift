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
    /// The summary for the rings, and the samples behind them for the Activity screen's hourly charts.
    private static let types: Set<HKObjectType> = [
        .activitySummaryType(),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleMoveTime),
        HKQuantityType(.appleExerciseTime),
        HKCategoryType(.appleStandHour),
    ]
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

    /// Today's hour-by-hour Move (in `unit`), Exercise minutes and stood hours, for the Activity screen. Hours
    /// HealthKit can't read (no access) are empty.
    static func hours(
        moveUnit: ActivityRings.MoveUnit, now: Date = .now, calendar: Calendar = .current
    ) async -> ActivityHours {
        let day = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        let today = HKQuery.predicateForSamples(withStart: day, end: end)
        func hourly(_ identifier: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> [(Date, Double)] {
            let query = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(identifier), predicate: today),
                options: .cumulativeSum,
                anchorDate: day,
                intervalComponents: DateComponents(hour: 1)
            )
            guard let collection = try? await query.result(for: store) else { return [] }
            return collection.statistics().compactMap { statistics in
                statistics.sumQuantity().map { (statistics.startDate, $0.doubleValue(for: unit)) }
            }
        }
        let move = moveUnit == .minutes
            ? await hourly(.appleMoveTime, .minute())
            : await hourly(.activeEnergyBurned, .kilocalorie())
        let exercise = await hourly(.appleExerciseTime, .minute())
        let standQuery = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.appleStandHour), predicate: today)],
            sortDescriptors: []
        )
        let stood = await ((try? standQuery.result(for: store)) ?? [])
            .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
            .map { ($0.startDate, 1.0) }
        return ActivityHours(
            move: ActivityHours.buckets(move, day: day, calendar: calendar),
            exercise: ActivityHours.buckets(exercise, day: day, calendar: calendar),
            stand: ActivityHours.buckets(stood, day: day, calendar: calendar)
        )
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

/// A day's activity hour by hour, 24 slots from midnight, as the Activity app charts it.
struct ActivityHours: Equatable, Sendable {
    var move: [Double]
    var exercise: [Double]
    /// 1 for each hour stood in, else 0.
    var stand: [Double]

    static let empty = ActivityHours(move: hourSlots, exercise: hourSlots, stand: hourSlots)
    private static let hourSlots = [Double](repeating: 0, count: 24)

    /// `values` added up into the hour of the day each starts in. By clock hour, so a daylight-saving day still has 24
    /// slots (the repeated hour shares one); values from other days are left out.
    static func buckets(_ values: [(Date, Double)], day: Date, calendar: Calendar = .current) -> [Double] {
        var slots = hourSlots
        for (date, value) in values where calendar.isDate(date, inSameDayAs: day) {
            slots[calendar.component(.hour, from: date)] += value
        }
        return slots
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
