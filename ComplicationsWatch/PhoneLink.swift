import Foundation
import Synchronization
import WatchConnectivity
import WidgetKit

/// The watch's side of WatchConnectivity: receives the phone's battery readings and location, and asks for them while
/// the app is open. Every newer reading is saved for the complication, which is then reloaded; so is every newer
/// location, reloading the weather only after a significant move.
final class PhoneLink: NSObject, WCSessionDelegate, Sendable {
    static let shared = PhoneLink()

    private let activation = SessionActivation()
    /// Updates arrive on the session's queue and from `refresh()` at once; one at a time, an older one can't
    /// overwrite a newer one between checking and saving.
    private let storing = Mutex(())

    func start() {
        activation.start(delegate: self)
    }

    /// Asks the phone for its battery unless the saved reading is younger than `maxAge`: the phone sends changes on
    /// its own, and each ask uses both devices' radios. Returns the latest reading, which is the saved one if the
    /// phone wasn't asked or can't be reached (not nearby, or no answer within `timeout`).
    func refresh(maxAge: TimeInterval = 5 * 60, timeout: Duration = .seconds(5)) async -> PhoneBatteryReading? {
        if let saved = PhoneBatteryReading.saved(), Date.now.timeIntervalSince(saved.date) < maxAge {
            return saved
        }
        start()
        await activation.wait()
        if let update = await ask(timeout: timeout) {
            store(update)
        }
        return PhoneBatteryReading.saved()
    }

    /// Lets a background wake for WatchConnectivity finish once everything queued for us has been delivered.
    func waitForPendingContent() async {
        start()
        await activation.wait()
        for _ in 0 ..< 50 where WCSession.default.hasContentPending {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func ask(timeout: Duration) async -> PhoneUpdate? {
        guard WCSession.default.activationState == .activated else { return nil }
        return await withCheckedContinuation { continuation in
            let reply = ReplyOnce(continuation)
            WCSession.default.sendMessage(
                PhoneBatteryReading.request,
                replyHandler: { reply.resume(PhoneUpdate(message: $0)) },
                errorHandler: { _ in reply.resume(nil) }
            )
            Task {
                try? await Task.sleep(for: timeout)
                reply.resume(nil)
            }
        }
    }

    private func store(_ update: PhoneUpdate) {
        storing.withLock { _ in
            if let reading = update.reading, reading.save() {
                Route.battery.widgetKinds.forEach(WidgetCenter.shared.reloadTimelines(ofKind:))
            }
            if let location = update.location {
                let previous = PhoneLocation.saved()
                if location.save(), location.isFar(from: previous) {
                    Route.weather.widgetKinds.forEach(WidgetCenter.shared.reloadTimelines(ofKind:))
                }
            }
        }
    }

    // MARK: WCSessionDelegate

    func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        activation.complete()
        store(PhoneUpdate(message: WCSession.default.receivedApplicationContext))
    }

    /// A complication transfer, sent when the phone's level changes; it wakes this app in the background.
    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        store(PhoneUpdate(message: userInfo))
    }

    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        store(PhoneUpdate(message: applicationContext))
    }
}

/// What one message from the phone carried: a battery reading, its location, or both.
private struct PhoneUpdate: Sendable {
    var reading: PhoneBatteryReading?
    var location: PhoneLocation?

    init(message: [String: Any]) {
        reading = PhoneBatteryReading(message: message)
        location = PhoneLocation(message: message)
    }
}

/// Resumes a continuation with whichever comes first, the phone's reply or the timeout.
private final class ReplyOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<PhoneUpdate?, Never>?>

    init(_ continuation: CheckedContinuation<PhoneUpdate?, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ update: PhoneUpdate?) {
        continuation.withLock { continuation in
            defer { continuation = nil }
            return continuation
        }?.resume(returning: update)
    }
}
