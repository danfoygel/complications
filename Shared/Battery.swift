import Foundation
import WatchKit
import WidgetKit

struct BatteryEntry: TimelineEntry {
    var date: Date
    /// 0...1, or `nil` when the watch can't report it.
    var level: Double?
    /// The phone's latest reading, if the phone app has ever sent one.
    var phone: PhoneBatteryReading?

    var percent: Int? {
        level.map { Int(($0 * 100).rounded()) }
    }
}

/// One look at the battery, kept so later reloads can tell how fast the level is moving.
struct BatteryReading: Codable, Sendable {
    var date: Date
    var level: Double
    /// Charging or full.
    var isPluggedIn: Bool
}

/// Predicts the level between reloads from how fast it has been moving.
///
/// Widget reloads are rationed but timeline entries are not, so each reload returns an entry for every whole
/// percent the level should reach in the next hour. The next reload replaces the prediction with a real reading.
enum BatteryForecast {
    /// How far back readings are used. Long enough to smooth out 1% steps, short enough to follow a workout.
    static let window: TimeInterval = 60 * 60
    /// Readings closer together than this give too noisy a rate.
    static let minimumSpan: TimeInterval = 10 * 60
    /// Fastest believable change, about 2% a minute.
    static let maximumRate = 0.02 / 60

    /// Level change per second from the oldest reading to the newest; `nil` when there isn't enough to go on
    /// or the level is moving the wrong way for the charger state.
    static func rate(_ history: [BatteryReading]) -> Double? {
        guard let first = history.first, let last = history.last else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= minimumSpan else { return nil }
        let rate = (last.level - first.level) / span
        guard last.isPluggedIn ? rate > 0 : rate < 0 else { return nil }
        return max(-maximumRate, min(maximumRate, rate))
    }

    /// Seconds from the latest reading until the battery is full (charging) or empty (unplugged).
    static func timeRemaining(_ history: [BatteryReading]) -> TimeInterval? {
        guard let current = history.last, let rate = rate(history) else { return nil }
        let target = rate > 0 ? 1.0 : 0.0
        return (target - current.level) / rate
    }

    /// The latest reading, then an entry for each whole percent the level is predicted to reach by `horizon`.
    static func entries(for history: [BatteryReading], until horizon: Date) -> [BatteryEntry] {
        guard let current = history.last else { return [] }
        let now = BatteryEntry(date: current.date, level: current.level)
        guard let rate = rate(history) else { return [now] }

        let step = rate > 0 ? 1 : -1
        var entries = [now]
        var target = Int((current.level * 100).rounded()) + step
        while (0 ... 100).contains(target) {
            // The shown percent is rounded, so it changes when the level crosses the half percent before it.
            let crossing = (Double(target) - 0.5 * Double(step)) / 100
            let date = current.date.addingTimeInterval((crossing - current.level) / rate)
            guard date <= horizon else { break }
            if date > current.date {
                entries.append(BatteryEntry(date: date, level: Double(target) / 100))
            }
            target += step
        }
        return entries
    }

    /// Puts `phone` on every entry, adding one for when it goes stale so the complication dims it on time.
    static func adding(_ phone: PhoneBatteryReading?, to entries: [BatteryEntry]) -> [BatteryEntry] {
        var result = entries.map {
            var entry = $0
            entry.phone = phone
            return entry
        }
        guard let phone, let first = result.first else { return result }
        let staleDate = phone.date.addingTimeInterval(PhoneBatteryReading.staleAfter + 1)
        guard staleDate > first.date, let before = result.last(where: { $0.date < staleDate }) else { return result }
        result.append(BatteryEntry(date: staleDate, level: before.level, phone: phone))
        return result.sorted { $0.date < $1.date }
    }

    /// How old the last reading may be and still give a rate when there's none inside the `window`.
    static let longestGap: TimeInterval = 3 * 60 * 60

    /// Adds `reading` to the saved history and returns it, oldest first. A charger change starts a new history.
    /// The app and the widget both record, so this holds the app group's lock.
    static func record(_ reading: BatteryReading, in defaults: UserDefaults = AppGroup.defaults) -> [BatteryReading] {
        AppGroup.withLock {
            let key = "batteryHistory"
            var history = defaults.data(forKey: key)
                .flatMap { try? JSONDecoder().decode([BatteryReading].self, from: $0) } ?? []
            if history.last?.isPluggedIn != reading.isPluggedIn {
                history = []
            }
            var recent = history.filter { (0 ... window).contains(reading.date.timeIntervalSince($0.date)) }
            // The system often spaces reloads out past the window; the last one's reading then still gives a rate,
            // rather than none until two reloads land within an hour.
            if recent.isEmpty, let last = history.last {
                recent = (0 ... longestGap).contains(reading.date.timeIntervalSince(last.date)) ? [last] : []
            }
            history = recent + [reading]
            defaults.set(try? JSONEncoder().encode(history), forKey: key)
            return history
        }
    }
}

@MainActor
extension BatteryReading {
    static func current() -> BatteryReading? {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        guard level >= 0 else { return nil }
        // As the phone reads it: an unknown state isn't taken for charging, which would also start a new history.
        let isPluggedIn = device.batteryState == .charging || device.batteryState == .full
        return BatteryReading(date: .now, level: min(1, Double(level)), isPluggedIn: isPluggedIn)
    }
}

/// The phone's latest reading, saved where the complication can read it.
extension PhoneBatteryReading {
    private static let key = "phoneBattery"

    static func saved(in defaults: UserDefaults = AppGroup.defaults) -> PhoneBatteryReading? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    /// Saves this reading unless a newer one is already saved; returns whether it did.
    @discardableResult func save(in defaults: UserDefaults = AppGroup.defaults) -> Bool {
        if let saved = Self.saved(in: defaults), saved.date >= date {
            return false
        }
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
        return true
    }

    private static let timelineKey = "phoneBatteryInTimeline"

    /// The reading the battery complication's timeline was last built with.
    static func inTimeline(in defaults: UserDefaults = AppGroup.defaults) -> PhoneBatteryReading? {
        defaults.data(forKey: timelineKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    static func setInTimeline(_ reading: PhoneBatteryReading?, in defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(reading.flatMap { try? JSONEncoder().encode($0) }, forKey: timelineKey)
    }

    /// Whether the battery complication needs reloading for this reading, when its timeline was built with `shown`:
    /// the percent or charger state differs, or the dimming that timeline has for `shown` is due within half an hour,
    /// which a reload on its usual schedule might not come in time to undo. Reloads asked for in the background count
    /// against the widget's daily budget, and the phone sends far more readings than change the face.
    func needsReload(after shown: PhoneBatteryReading?, at now: Date) -> Bool {
        guard let shown else { return true }
        return percent != shown.percent || isPluggedIn != shown.isPluggedIn
            || now.timeIntervalSince(shown.date) > Self.staleAfter - 30 * 60
    }
}
