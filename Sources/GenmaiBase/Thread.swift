// Port of the TaskManager of mozc/src/base/thread.h (3.35.6354).
//
// Deviations from C++:
// - The scheduled tasks are serialized by an actor (`TaskManager.Worker`)
//   instead of a mutex + std::thread. The actor (and the tasks, through their
//   executor preference) runs on a `ThreadExecutor`: a serial executor that
//   drains its jobs on a Foundation `Thread` started on demand, which ends
//   when the queue is empty. It is not the Swift cooperative pool on purpose:
//   C++ BackgroundFuture starts its std::thread at once, and callers depend on
//   that (e.g. UserHistoryPredictor skips learning while the user history
//   syncer is running). On a busy pool (parallel tests, the AI converter) a
//   pool task could wait for seconds before starting, so the syncer would
//   seem to run for seconds and learning would be lost.
// - `schedule` never blocks the caller. C++ `Schedule` waits for the previous
//   task before starting the new one; here the new task is queued on the
//   actor, so tasks still run one at a time and in scheduling order.
// - `wait` is `async`: it suspends (instead of blocking a thread) until the
//   scheduled tasks have finished.
// - `isRunning` is true while a scheduled task has not finished yet (C++: the
//   current task is not ready; a queued task here corresponds to a C++ caller
//   still blocked in `Schedule`).

import Foundation
import Synchronization

/// A serial executor (and task executor) that runs its jobs in order on a
/// background Foundation `Thread`. The thread is started when a job arrives
/// and ends when the queue is empty, so an idle executor holds no thread.
/// Nothing waits: an idle thread exits instead of sleeping.
public final class ThreadExecutor: SerialExecutor, TaskExecutor {
  private struct State {
    var jobs: [UnownedJob] = []
    var draining = false
  }

  private let state = Mutex(State())

  public init() {}

  public func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    let start = state.withLock { state in
      state.jobs.append(job)
      if state.draining {
        return false
      }
      state.draining = true
      return true
    }
    if start {
      let thread = Thread { [self] in drain() }
      thread.start()
    }
  }

  private func drain() {
    while let job = state.withLock({ state -> UnownedJob? in
      if state.jobs.isEmpty {
        state.draining = false
        return nil
      }
      return state.jobs.removeFirst()
    }) {
      job.runSynchronously(
        isolatedTo: asUnownedSerialExecutor(), taskExecutor: asUnownedTaskExecutor())
    }
  }

  public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
    UnownedSerialExecutor(ordinary: self)
  }
}

/// base/thread.h TaskManager: runs scheduled tasks one at a time in the
/// background.
public final class TaskManager: Sendable {
  /// Serializes the scheduled tasks.
  private actor Worker {
    private let executor: ThreadExecutor

    init(_ executor: ThreadExecutor) {
      self.executor = executor
    }

    nonisolated var unownedExecutor: UnownedSerialExecutor {
      executor.asUnownedSerialExecutor()
    }

    func run(_ body: @Sendable () -> Void) {
      body()
    }
  }

  private struct State {
    // The number of scheduled tasks that have not finished yet.
    var unfinished = 0
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let executor: ThreadExecutor
  private let worker: Worker
  private let state = Mutex(State())

  public init() {
    executor = ThreadExecutor()
    worker = Worker(executor)
  }

  /// Schedules `body` to run in the background after the previously
  /// scheduled tasks.
  public func schedule(_ body: @escaping @Sendable () -> Void) {
    state.withLock { $0.unfinished += 1 }
    Task(executorPreference: executor) { [worker] in
      await worker.run(body)
      self.finished()
    }
  }

  private func finished() {
    let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.unfinished -= 1
      if state.unfinished > 0 {
        return []
      }
      let waiters = state.waiters
      state.waiters.removeAll()
      return waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  /// Returns true if a scheduled task has not finished yet.
  public func isRunning() -> Bool {
    state.withLock { $0.unfinished > 0 }
  }

  /// Suspends until the scheduled tasks have finished.
  public func wait() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let idle = state.withLock { state in
        if state.unfinished == 0 {
          return true
        }
        state.waiters.append(continuation)
        return false
      }
      if idle {
        continuation.resume()
      }
    }
  }
}
