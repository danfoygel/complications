import Foundation
import os

/// A screen in the app, one per complication. Each complication sets its route's `url` as its `widgetURL`,
/// and the app opens that screen when it receives the URL.
enum Route: String, CaseIterable, Hashable, Sendable {
    case calendar
    case battery
    case weather

    static let scheme = "complications"

    var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let route = url.host().flatMap(Route.init(rawValue:)) else { return nil }
        self = route
    }

    /// The widget `kind` of the complication that opens this screen.
    var widgetKind: String {
        switch self {
        case .calendar: "CalendarComplication"
        case .battery: "BatteryComplication"
        case .weather: "WeatherComplication"
        }
    }

    /// Every complication that shows this screen's data, to reload when there's news for them. Up Next has a weather
    /// line.
    var widgetKinds: [String] {
        switch self {
        case .calendar: [widgetKind]
        case .battery: [widgetKind]
        case .weather: [widgetKind, Route.calendar.widgetKind]
        }
    }
}

enum AppGroup {
    static let identifier = "group.com.danfoygel.complications"

    /// Shared between the app and the widget extension. One instance for every caller; `UserDefaults` is thread-safe.
    nonisolated(unsafe) static let defaults: UserDefaults = {
        // `UserDefaults(suiteName:)` succeeds without the entitlement too, it just isn't shared then; the container
        // is what tells. (The hostless tests have none, and pass their own defaults.)
        if containerURL == nil {
            Logger(subsystem: "com.danfoygel.complications", category: "AppGroup").fault(
                """
                No container for \(identifier, privacy: .public): check the entitlements. The app and the widgets \
                won't see each other's data.
                """
            )
        }
        return UserDefaults(suiteName: identifier) ?? .standard
    }()

    /// The group's shared folder, for what's too big for `defaults`; `nil` without the entitlement (the tests).
    static let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)

    /// Runs `body` holding a lock the app and the extension share, for a read-modify-write of `defaults` that the
    /// other process could otherwise interleave with. Without a container, it just runs it.
    static func withLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        guard let url = containerURL?.appendingPathComponent("defaults.lock") else { return try body() }
        let descriptor = open(url.path, O_RDWR | O_CREAT, 0o600)
        guard descriptor >= 0 else { return try body() }
        // Closing it releases the lock.
        defer { close(descriptor) }
        flock(descriptor, LOCK_EX)
        return try body()
    }
}
