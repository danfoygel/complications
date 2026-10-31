import Foundation
import UIKit
import WatchConnectivity

/// The phone's side of WatchConnectivity: answers the watch's requests for a reading and pushes readings to it.
final class WatchLink: NSObject, WCSessionDelegate, Sendable {
    static let shared = WatchLink()

    private let activation = SessionActivation()

    func start() {
        activation.start(delegate: self)
    }

    enum Outcome: Sendable {
        case noBattery
        case noWatch
        case noWatchApp
        /// `woke` is whether a complication transfer went out (which wakes the watch app now), rather than only
        /// the application context the watch picks up the next time it runs.
        case sent(woke: Bool)
    }

    /// Sends the current reading. A complication transfer, which wakes the watch app and is limited to about 50 a
    /// day, only goes out when the percent or charger state has changed since the last one.
    @discardableResult
    @MainActor func send() async -> Outcome {
        start()
        await activation.wait()
        let session = WCSession.default
        guard let reading = PhoneBatteryReading.current() else { return .noBattery }
        guard session.activationState == .activated, session.isPaired else { return .noWatch }
        guard session.isWatchAppInstalled else { return .noWatchApp }

        try? session.updateApplicationContext(reading.message)
        let last = Sent.lastTransfer
        let changed = last?.percent != reading.percent || last?.isPluggedIn != reading.isPluggedIn
        let woke = changed && session.isComplicationEnabled && session.remainingComplicationUserInfoTransfers > 0
        if woke {
            session.transferCurrentComplicationUserInfo(reading.message)
            Sent.lastTransfer = reading
        }
        Sent.last = reading
        return .sent(woke: woke)
    }

    struct Status: Sendable {
        var isPaired: Bool
        var isWatchAppInstalled: Bool
        var isComplicationEnabled: Bool
        var transfersLeft: Int
    }

    @MainActor func status() async -> Status {
        start()
        await activation.wait()
        let session = WCSession.default
        return Status(
            isPaired: session.isPaired,
            isWatchAppInstalled: session.isWatchAppInstalled,
            isComplicationEnabled: session.isComplicationEnabled,
            transfersLeft: session.remainingComplicationUserInfoTransfers
        )
    }

    // MARK: WCSessionDelegate

    func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        activation.complete()
    }

    func sessionDidBecomeInactive(_: WCSession) {}

    /// Happens when the phone switches to another watch; the session has to be activated again for the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The watch app asking for a reading. iOS launches this app in the background to answer if it isn't running.
    func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard PhoneBatteryReading.isRequest(message) else { return replyHandler([:]) }
        // Delegate calls come on a background queue; UIDevice needs the main thread.
        let reading = DispatchQueue.main.sync { MainActor.assumeIsolated { PhoneBatteryReading.current() } }
        if let reading {
            Sent.last = reading
        }
        replyHandler(reading?.message ?? [:])
    }
}

@MainActor
extension PhoneBatteryReading {
    /// `nil` where there's no battery to read (the simulator).
    static func current() -> PhoneBatteryReading? {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        guard device.batteryLevel >= 0 else { return nil }
        return PhoneBatteryReading(
            date: .now,
            level: Double(device.batteryLevel),
            isPluggedIn: device.batteryState == .charging || device.batteryState == .full
        )
    }
}

/// Readings the phone has sent, kept in the phone app's own defaults.
enum Sent {
    /// The last reading sent by any route, shown in the phone app.
    static var last: PhoneBatteryReading? {
        get { load("lastSent") }
        set { store(newValue, "lastSent") }
    }

    /// The last reading sent as a complication transfer, so an unchanged one isn't sent again.
    static var lastTransfer: PhoneBatteryReading? {
        get { load("lastTransfer") }
        set { store(newValue, "lastTransfer") }
    }

    private static func load(_ key: String) -> PhoneBatteryReading? {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(PhoneBatteryReading.self, from: $0) }
    }

    private static func store(_ reading: PhoneBatteryReading?, _ key: String) {
        UserDefaults.standard.set(reading.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}
