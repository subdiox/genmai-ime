// Port of mozc/src/base/cpu_stats_test.cc (3.35.6354).

import Foundation
import Synchronization
import Testing

@testable import GenmaiBase

@Suite struct CPUStatsTest {
  @Test func cpuStatsTest() {
    let stats = CPUStats()
    #expect(stats.getSystemCPULoad() >= 0.0)
    #expect(stats.getSystemCPULoad() <= 1.0)
    #expect(stats.getCurrentProcessCPULoad() >= 0.0)
    #expect(stats.getNumberOfProcessors() >= 1)
  }

  @Test func multiThreadTest() async {
    let kDummyThreadsSize = 32
    let cancel = CancelFlag()
    // Real threads (not tasks): busy tasks would starve the cooperative pool.
    let (finished, finish) = AsyncStream<Void>.makeStream()
    for _ in 0..<kDummyThreadsSize {
      let thread = Thread {
        var n: UInt64 = 0
        // Makes busy loop.
        while !cancel.isSet {
          n &+= 1
          n &-= 1
        }
        finish.yield()
      }
      thread.start()
    }
    let stats = CPUStats()
    let kNumIterations = 10
    for _ in 0..<kNumIterations {
      #expect(stats.getSystemCPULoad() >= 0.0)
      #expect(stats.getCurrentProcessCPULoad() >= 0.0)
      #expect(stats.getNumberOfProcessors() >= 1)
      try? await Task.sleep(for: .milliseconds(10))
    }
    cancel.set()
    // Joins the threads.
    var running = kDummyThreadsSize
    for await _ in finished {
      running -= 1
      if running == 0 { break }
    }
  }
}

private final class CancelFlag: Sendable {
  private let flag = Mutex(false)
  var isSet: Bool { flag.withLock { $0 } }
  func set() { flag.withLock { $0 = true } }
}
