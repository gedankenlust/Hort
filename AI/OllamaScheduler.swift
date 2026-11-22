import Foundation

/// Exclusive access to the local Ollama HTTP endpoint.
/// Replaces busy-wait polling with a continuation queue so waiters resume
/// immediately when the slot frees, while preserving priority (organize > analyze > embed).
actor OllamaScheduler {
    static let shared = OllamaScheduler()

    enum Priority: Int, Comparable {
        case embed = 0
        case analyze = 1
        case organize = 2

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private var locked = false
    private var waiters: [(priority: Priority, continuation: CheckedContinuation<Bool, Never>)] = []

    /// Runs `body` while holding the exclusive slot. Returns `nil` without
    /// running `body` when cancelled before (or upon) acquisition.
    func run<R>(
        priority: Priority,
        isCancelled: @Sendable () -> Bool,
        _ body: () async throws -> R
    ) async rethrows -> R? {
        let acquired = await acquire(priority: priority, isCancelled: isCancelled)
        guard acquired else { return nil }
        defer { release() }
        return try await body()
    }

    var isLocked: Bool { locked }
    /// Waiters parked for the slot (tests use this to avoid sleep races).
    var pendingWaiterCount: Int { waiters.count }

    private func acquire(priority: Priority, isCancelled: @Sendable () -> Bool) async -> Bool {
        if isCancelled() { return false }
        if !locked {
            locked = true
            return true
        }

        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            insertWaiter(priority: priority, continuation: cont)
        }
        if !granted {
            return false
        }
        if isCancelled() {
            // Slot was granted but the job was cancelled — free it for others.
            release()
            return false
        }
        return true
    }

    private func insertWaiter(priority: Priority, continuation: CheckedContinuation<Bool, Never>) {
        let entry = (priority, continuation)
        if let idx = waiters.firstIndex(where: { $0.priority < priority }) {
            waiters.insert(entry, at: idx)
        } else {
            waiters.append(entry)
        }
    }

    private func release() {
        locked = false
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        locked = true
        next.continuation.resume(returning: true)
    }

    /// Wake every waiter as cancelled (used by tests / emergency cancel).
    func cancelAllWaiters() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.continuation.resume(returning: false)
        }
    }
}
