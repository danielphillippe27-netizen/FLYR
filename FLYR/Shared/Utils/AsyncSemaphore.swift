import Foundation

// MARK: - Async Semaphore for Concurrency Control

/// Actor-based semaphore for throttling concurrent operations
actor AsyncSemaphore {
    private let limit: Int
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(limit: Int) {
        self.limit = limit
    }
    
    /// Wait for permission to proceed (blocks if at limit)
    func wait() async {
        count += 1
        if count > limit {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }
    
    /// Signal that operation is complete
    func signal() {
        count -= 1
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        }
    }
    
    /// Current number of active operations
    var activeCount: Int {
        return count
    }
    
    /// Number of operations waiting
    var waitingCount: Int {
        return waiters.count
    }
}
