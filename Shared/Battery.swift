import Foundation
import WatchKit
import WidgetKit

struct BatteryEntry: TimelineEntry {
    var date: Date
    /// 0...1, or `nil` when the watch can't report it.
    var level: Double?

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

    /// Adds `reading` to the saved history and returns it, oldest first. A charger change starts a new history.
    static func record(_ reading: BatteryReading, in defaults: UserDefaults = AppGroup.defaults) -> [BatteryReading] {
        let key = "batteryHistory"
        var history = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([BatteryReading].self, from: $0) } ?? []
        if history.last?.isPluggedIn != reading.isPluggedIn {
            history = []
        }
        history = history.filter { (0 ... window).contains(reading.date.timeIntervalSince($0.date)) } + [reading]
        defaults.set(try? JSONEncoder().encode(history), forKey: key)
        return history
    }
}

@MainActor
extension BatteryReading {
    static func current() -> BatteryReading? {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        guard level >= 0 else { return nil }
        return BatteryReading(date: .now, level: min(1, Double(level)), isPluggedIn: device.batteryState != .unplugged)
    }
}
