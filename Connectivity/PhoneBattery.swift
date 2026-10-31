import Foundation

/// The phone's battery as the iPhone app last read it. Compiled into both the iPhone and watch apps, and travels
/// between them over WatchConnectivity as JSON under a single message key.
struct PhoneBatteryReading: Codable, Equatable, Sendable {
    var date: Date
    /// 0...1
    var level: Double
    /// Charging or full.
    var isPluggedIn: Bool

    /// After this long the complication dims the phone's percent, since it may be well off.
    static let staleAfter: TimeInterval = 60 * 60

    var percent: Int {
        Int((level * 100).rounded())
    }

    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(self.date) > Self.staleAfter
    }

    /// What the watch sends to ask the phone for a reading; the phone replies with `message`.
    static var request: [String: Any] {
        ["request": "phoneBattery"]
    }

    static func isRequest(_ message: [String: Any]) -> Bool {
        message["request"] as? String == "phoneBattery"
    }

    var message: [String: Any] {
        (try? JSONEncoder().encode(self)).map { ["phoneBattery": $0] } ?? [:]
    }

    init(date: Date, level: Double, isPluggedIn: Bool) {
        self.date = date
        self.level = level
        self.isPluggedIn = isPluggedIn
    }

    init?(message: [String: Any]) {
        guard let data = message["phoneBattery"] as? Data,
              let reading = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = reading
    }
}
