import XCTest
@testable import Hort

final class OllamaSchedulerTests: XCTestCase {
    actor Counter {
        private(set) var concurrent = 0
        private(set) var maxConcurrent = 0
        private(set) var order: [String] = []
        private(set) var ran = false

        func enter() {
            concurrent += 1
            maxConcurrent = max(maxConcurrent, concurrent)
        }

        func leave() {
            concurrent -= 1
        }

        func append(_ value: String) {
            order.append(value)
        }

        func markRan() {
            ran = true
        }
    }

    func testSerializesConcurrentWork() async throws {
        let scheduler = OllamaScheduler()
        let counter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    _ = try? await scheduler.run(priority: .analyze, isCancelled: { false }) {
                        await counter.enter()
                        try await Task.sleep(nanoseconds: 20_000_000)
                        await counter.leave()
                    }
                }
            }
        }

        let maxConcurrent = await counter.maxConcurrent
        XCTAssertEqual(maxConcurrent, 1)
    }

    func testOrganizePriorityRunsBeforeAnalyze() async throws {
        let scheduler = OllamaScheduler()
        let counter = Counter()
        let holdGate = Gate()
        let holdReady = Gate()

        // Hold the slot until both waiters are queued — sleep-based races
        // flake on CI when the holder finishes before organize enqueues.
        let hold = Task {
            _ = try? await scheduler.run(priority: .analyze, isCancelled: { false }) {
                await holdReady.open()
                await holdGate.wait()
            }
        }
        await holdReady.wait()

        let analyze = Task {
            _ = try? await scheduler.run(priority: .analyze, isCancelled: { false }) {
                await counter.append("analyze")
            }
        }
        let organize = Task {
            _ = try? await scheduler.run(priority: .organize, isCancelled: { false }) {
                await counter.append("organize")
            }
        }

        // Wait until both jobs are parked, then release — no wall-clock race.
        for _ in 0..<200 {
            if await scheduler.pendingWaiterCount >= 2 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let parked = await scheduler.pendingWaiterCount
        XCTAssertGreaterThanOrEqual(parked, 2)
        await holdGate.open()

        await hold.value
        await analyze.value
        await organize.value
        let order = await counter.order
        XCTAssertEqual(order, ["organize", "analyze"])
    }

    /// One-shot async latch for deterministic scheduler tests.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false

        func wait() async {
            if opened { return }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if opened {
                    cont.resume()
                } else {
                    continuation = cont
                }
            }
        }

        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }

    func testCancelledWaiterDoesNotRun() async throws {
        let scheduler = OllamaScheduler()
        let counter = Counter()

        let hold = Task {
            _ = try? await scheduler.run(priority: .organize, isCancelled: { false }) {
                try await Task.sleep(nanoseconds: 40_000_000)
            }
        }
        try await Task.sleep(nanoseconds: 5_000_000)

        let waiter = Task {
            _ = try? await scheduler.run(priority: .analyze, isCancelled: { true }) {
                await counter.markRan()
            }
        }
        await scheduler.cancelAllWaiters()
        await hold.value
        await waiter.value
        let ran = await counter.ran
        XCTAssertFalse(ran)
    }
}
