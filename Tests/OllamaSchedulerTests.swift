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

        let hold = Task {
            _ = try? await scheduler.run(priority: .analyze, isCancelled: { false }) {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        try await Task.sleep(nanoseconds: 5_000_000)

        let analyze = Task {
            _ = try? await scheduler.run(priority: .analyze, isCancelled: { false }) {
                await counter.append("analyze")
            }
        }
        try await Task.sleep(nanoseconds: 5_000_000)
        let organize = Task {
            _ = try? await scheduler.run(priority: .organize, isCancelled: { false }) {
                await counter.append("organize")
            }
        }

        await hold.value
        await analyze.value
        await organize.value
        let order = await counter.order
        XCTAssertEqual(order, ["organize", "analyze"])
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
