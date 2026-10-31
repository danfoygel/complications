import Synchronization
import WatchConnectivity

/// Activates `WCSession.default` once and lets callers wait until it's done. The delegate that owns it calls
/// `complete()` from `session(_:activationDidCompleteWith:error:)`.
final class SessionActivation: Sendable {
    private struct State {
        var started = false
        var done = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    /// Call as early as possible at launch: messages that woke the app wait for the session to activate.
    func start(delegate: some WCSessionDelegate) {
        guard WCSession.isSupported() else { return }
        let first = state.withLock { state in
            defer { state.started = true }
            return !state.started
        }
        guard first else { return }
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    /// Returns once activation has finished, successfully or not. `start` must have been called.
    func wait() async {
        guard WCSession.isSupported() else { return }
        await withCheckedContinuation { continuation in
            let done = state.withLock { state in
                if !state.done {
                    state.waiters.append(continuation)
                }
                return state.done
            }
            if done {
                continuation.resume()
            }
        }
    }

    func complete() {
        let waiters = state.withLock { state in
            state.done = true
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }
}
