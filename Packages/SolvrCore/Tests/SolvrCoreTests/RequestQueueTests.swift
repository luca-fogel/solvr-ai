import Foundation
import Testing
@testable import SolvrCore

private struct Boom: Error {}

@Suite("Request queue")
struct RequestQueueTests {

    @Test("a slot is returned after the work succeeds")
    func slotReturnedOnSuccess() async throws {
        let q = RequestQueue(maxConcurrent: 2)
        _ = try await q.withSlot { 1 }
        #expect(await q.inFlight == 0)
    }

    @Test("a slot is returned after the work throws -- the leak this replaced")
    func slotReturnedOnThrow() async {
        let q = RequestQueue(maxConcurrent: 2)
        await #expect(throws: Boom.self) {
            try await q.withSlot { throw Boom() }
        }
        #expect(await q.inFlight == 0)
    }

    @Test("repeated failures do not narrow the queue")
    func failuresDoNotStarveTheQueue() async {
        let q = RequestQueue(maxConcurrent: 4)
        for _ in 0..<20 {
            _ = try? await q.withSlot { throw Boom() }
        }
        // If each failure had leaked a slot, this would deadlock instead.
        _ = try? await q.withSlot { }
        #expect(await q.inFlight == 0)
    }

    @Test("no more than maxConcurrent run at once")
    func limitIsRespected() async throws {
        let q = RequestQueue(maxConcurrent: 3)
        let peak = Peak()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    try? await q.withSlot {
                        await peak.enter()
                        try? await Task.sleep(for: .milliseconds(20))
                        await peak.leave()
                    }
                }
            }
        }
        #expect(await peak.highWater <= 3)
        #expect(await peak.highWater > 1, "the queue should allow real concurrency, not serialise")
        #expect(await q.inFlight == 0)
    }

    @Test("a queue asked for zero slots still runs, rather than hanging forever")
    func zeroIsClampedToOne() async throws {
        let q = RequestQueue(maxConcurrent: 0)
        _ = try await q.withSlot { 42 }
        #expect(await q.inFlight == 0)
    }
}

private actor Peak {
    private var current = 0
    private(set) var highWater = 0

    func enter() {
        current += 1
        highWater = max(highWater, current)
    }

    func leave() { current -= 1 }
}
