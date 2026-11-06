import Foundation

/// A LIFO job pool shared by a fixed set of worker threads. Processing a job may
/// produce more jobs; the pool drains once no job is queued or in progress.
final class WorkStack<Job: Sendable>: @unchecked Sendable {
    private let condition = NSCondition()
    private var jobs: [Job]
    /// Jobs queued or currently being processed.
    private var outstanding: Int
    private var stopped = false

    init(_ initialJobs: [Job]) {
        jobs = initialJobs
        outstanding = initialJobs.count
    }

    /// Blocks until a job is available. Returns nil once all work is done or the pool stopped.
    func next() -> Job? {
        condition.lock()
        defer { condition.unlock() }
        while jobs.isEmpty, outstanding > 0, !stopped {
            condition.wait()
        }
        return stopped ? nil : jobs.popLast()
    }

    /// Marks the job returned by `next()` as finished and queues the jobs it produced.
    func complete(spawning newJobs: [Job]) {
        condition.lock()
        defer { condition.unlock() }
        jobs.append(contentsOf: newJobs)
        outstanding += newJobs.count - 1
        if outstanding == 0 || newJobs.count > 1 {
            condition.broadcast()
        } else if newJobs.count == 1 {
            condition.signal()
        }
    }

    func stop() {
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
    }

    /// Runs `body(workerIndex)` on `count` threads (the caller's included) and waits for all.
    static func runWorkers(count: Int, stackSize: Int = 1 << 20, body: @escaping @Sendable (Int) -> Void) {
        let group = DispatchGroup()
        for index in 1..<max(count, 1) {
            group.enter()
            let thread = Thread {
                body(index)
                group.leave()
            }
            thread.stackSize = stackSize
            thread.qualityOfService = .userInitiated
            thread.start()
        }
        body(0)
        group.wait()
    }
}
