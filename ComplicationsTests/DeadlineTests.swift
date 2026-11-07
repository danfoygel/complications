import Foundation
import Testing

struct DeadlineTests {
    @Test func returnsInTime() async throws {
        #expect(try await Deadline.run(within: .seconds(5)) { 42 } == 42)
    }

    @Test func passesOnErrors() async {
        struct Failure: Error {}
        await #expect(throws: Failure.self) {
            try await Deadline.run(within: .seconds(5)) { throw Failure() }
        }
    }

    /// Without waiting for work that ignores cancellation.
    @Test func givesUpAtTheLimit() async {
        let start = ContinuousClock.now
        await #expect(throws: Deadline.Exceeded.self) {
            try await Deadline.run(within: .milliseconds(100)) {
                let end = Date.now.addingTimeInterval(2)
                while Date.now < end {
                    await Task.yield()
                }
                return 0
            }
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }
}
