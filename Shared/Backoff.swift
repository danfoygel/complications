import Foundation

/// Spaces out the retries of a fetch that keeps failing (offline, or refused by the server), so each widget reload
/// doesn't spend the radio on another attempt: after one failure it waits `first`, then twice as long each time, up to
/// `longest`. Saved in the app group under the fetch's key, so the app and the extension share it. A success, or a
/// move of `PhoneLocation.significantDistance` from where it failed, starts over.
struct Backoff: Codable, Equatable {
    var date: Date
    var failures: Int
    var location: PhoneLocation

    static let first: TimeInterval = 15 * 60
    static let longest: TimeInterval = 2 * 60 * 60

    struct Waiting: Error {}

    /// How long after the last failure to wait.
    var wait: TimeInterval {
        min(Self.longest, Self.first * pow(2, Double(max(0, failures - 1))))
    }

    /// Throws `Waiting` while the last failure for about `location` is too recent to try again.
    static func check(
        _ key: String, at now: Date, for location: PhoneLocation, in defaults: UserDefaults = AppGroup.defaults
    ) throws {
        guard let saved = load(key, from: defaults), !location.isFar(from: saved.location),
              now.timeIntervalSince(saved.date) < saved.wait else { return }
        throw Waiting()
    }

    static func recordFailure(
        _ key: String, at now: Date, for location: PhoneLocation, in defaults: UserDefaults = AppGroup.defaults
    ) {
        let previous = load(key, from: defaults).flatMap { location.isFar(from: $0.location) ? nil : $0 }
        let backoff = Backoff(date: now, failures: (previous?.failures ?? 0) + 1, location: location)
        defaults.set(try? JSONEncoder().encode(backoff), forKey: key)
    }

    static func reset(_ key: String, in defaults: UserDefaults = AppGroup.defaults) {
        defaults.removeObject(forKey: key)
    }

    static func load(_ key: String, from defaults: UserDefaults = AppGroup.defaults) -> Backoff? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Backoff.self, from: $0) }
    }
}
