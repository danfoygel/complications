import Synchronization

/// Runs work that may hang (a fetch on a poor connection) with a time limit. A widget's timeline has to be returned
/// within the system's budget; without a limit, one stalled fetch would leave the face on its old entries.
enum Deadline {
    struct Exceeded: Error {}

    /// `operation`'s result, or `Exceeded` once `limit` has passed. The operation is cancelled then, but this returns
    /// right away rather than waiting for it, since not every API stops promptly when cancelled.
    static func run<Value: Sendable>(
        within limit: Duration,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let result = ResultOnce<Value>()
        return try await withCheckedThrowingContinuation { continuation in
            result.set(continuation)
            let work = Task {
                do {
                    try result.resume(with: .success(await operation()))
                } catch {
                    result.resume(with: .failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: limit)
                work.cancel()
                result.resume(with: .failure(Exceeded()))
            }
        }
    }
}

/// Resumes a continuation with whichever result comes first.
private final class ResultOnce<Value: Sendable>: Sendable {
    private let continuation = Mutex<CheckedContinuation<Value, Error>?>(nil)

    func set(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation.withLock { $0 = continuation }
    }

    func resume(with result: Result<Value, Error>) {
        continuation.withLock { continuation in
            defer { continuation = nil }
            return continuation
        }?.resume(with: result)
    }
}
