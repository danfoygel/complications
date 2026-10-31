import Foundation
import Synchronization
import WatchConnectivity
import WidgetKit

/// The watch's side of WatchConnectivity: receives the phone's battery readings, and asks for one while the app is
/// open. Every newer reading is saved for the complication, which is then reloaded.
final class PhoneLink: NSObject, WCSessionDelegate, Sendable {
    static let shared = PhoneLink()

    private let activation = SessionActivation()

    func start() {
        activation.start(delegate: self)
    }

    /// Asks the phone for its battery now; returns the latest reading, which is the saved one if the phone
    /// can't be reached (not nearby, or no answer within `timeout`).
    func refresh(timeout: Duration = .seconds(5)) async -> PhoneBatteryReading? {
        start()
        await activation.wait()
        if let reading = await ask(timeout: timeout) {
            store(reading)
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

    private func ask(timeout: Duration) async -> PhoneBatteryReading? {
        guard WCSession.default.activationState == .activated else { return nil }
        return await withCheckedContinuation { continuation in
            let reply = ReplyOnce(continuation)
            WCSession.default.sendMessage(
                PhoneBatteryReading.request,
                replyHandler: { reply.resume(PhoneBatteryReading(message: $0)) },
                errorHandler: { _ in reply.resume(nil) }
            )
            Task {
                try? await Task.sleep(for: timeout)
                reply.resume(nil)
            }
        }
    }

    private func store(_ reading: PhoneBatteryReading) {
        if reading.save() {
            WidgetCenter.shared.reloadTimelines(ofKind: Route.battery.widgetKind)
        }
    }

    // MARK: WCSessionDelegate

    func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        activation.complete()
        if let reading = PhoneBatteryReading(message: WCSession.default.receivedApplicationContext) {
            store(reading)
        }
    }

    /// A complication transfer, sent when the phone's level changes; it wakes this app in the background.
    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        PhoneBatteryReading(message: userInfo).map(store)
    }

    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        PhoneBatteryReading(message: applicationContext).map(store)
    }
}

/// Resumes a continuation with whichever comes first, the phone's reply or the timeout.
private final class ReplyOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<PhoneBatteryReading?, Never>?>

    init(_ continuation: CheckedContinuation<PhoneBatteryReading?, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ reading: PhoneBatteryReading?) {
        continuation.withLock { continuation in
            defer { continuation = nil }
            return continuation
        }?.resume(returning: reading)
    }
}
