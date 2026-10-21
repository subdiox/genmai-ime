// Port of mozc/src/session/session_watch_dog_test.cc (3.35.6354).
//
// client::ClientMock becomes MockWatchDogClient (PingServer returns true,
// Cleanup returns true and is counted). The timing tests sleep 5.6 s like the
// C++ ones; since Task.sleep scheduling is not exact, the cleanup count is
// checked with a tolerance of one call. The watch dog loop and the test body
// run at high priority: the other suites keep the cooperative pool busy, and
// the C++ watch dog runs on its own thread.

import Foundation
import GenmaiBase
import Testing
import Synchronization

@testable import GenmaiSession

/// Returns the given CPU load values in order.
private final class TestCPUStats: CPUStatsInterface, Sendable {
  private let cpuLoads: Mutex<[Float]>

  init(_ cpuLoads: [Float]) {
    self.cpuLoads = Mutex(cpuLoads.reversed())
  }

  func getSystemCPULoad() -> Float {
    // C++ CHECKs that loads remain; return 0 when exhausted instead of crashing.
    cpuLoads.withLock { $0.popLast() ?? 0.0 }
  }

  func getCurrentProcessCPULoad() -> Float { 0.0 }

  func getNumberOfProcessors() -> Int { 1 }
}

private final class MockWatchDogClient: SessionWatchDogClient, Sendable {
  private let cleanupCount = Mutex(0)

  var cleanupCalls: Int { cleanupCount.withLock { $0 } }

  func setTimeout(_ timeout: Duration) {}
  func cleanup() -> Bool {
    cleanupCount.withLock { $0 += 1 }
    return true
  }
  func reset() {}
  func pingServer() -> Bool { true }
}

@Suite struct SessionWatchDogTests {
  @Test func sessionWatchDogTest() async throws {
    try await Task(priority: .high) {
      let kInterval = Duration.seconds(1)
      let client = MockWatchDogClient()
      let stats = TestCPUStats([Float](repeating: 0.0, count: 5))

      let watchdog = SessionWatchDog(kInterval, client, stats, priority: .high)
      #expect(watchdog.interval == kInterval)

      try await Task.sleep(for: .milliseconds(100))
      #expect(watchdog.interval == kInterval)

      try await Task.sleep(for: .milliseconds(5500))  // 5.5 sec
      watchdog.stop()
      // EXPECT_CALL(*client, Cleanup()).Times(5)
      #expect((4...5).contains(client.cleanupCalls), "cleanup calls: \(client.cleanupCalls)")
    }.value
  }

  @Test func sessionWatchDogCPUStatsTest() async throws {
    try await Task(priority: .high) {
      let kInterval = Duration.seconds(1)
      let client = MockWatchDogClient()
      let cpuLoads = TestCPUStats([Float](repeating: 0.8, count: 5))

      let watchdog = SessionWatchDog(kInterval, client, cpuLoads, priority: .high)
      #expect(watchdog.interval == kInterval)

      try await Task.sleep(for: .milliseconds(100))
      #expect(watchdog.interval == kInterval)
      try await Task.sleep(for: .milliseconds(5500))  // 5.5 sec
      watchdog.stop()
      // The CPU load is too high; no Cleanup is sent while the loads last.
      #expect(client.cleanupCalls <= 1, "cleanup calls: \(client.cleanupCalls)")
    }.value
  }

  @Test func sessionCanSendCleanupCommandTest() {
    let watchdog = SessionWatchDog(.seconds(2))

    // suspend
    #expect(!watchdog.canSendCleanupCommand([0.0, 0.0], Date(unixSeconds: 5), Date(unixSeconds: 0)))

    // not suspend
    #expect(watchdog.canSendCleanupCommand([0.0, 0.0], Date(unixSeconds: 1), Date(unixSeconds: 0)))

    // error (the same time stamp)
    #expect(!watchdog.canSendCleanupCommand([0.0, 0.0], Date(unixSeconds: 0), Date(unixSeconds: 0)))

    // average CPU loads >= 0.33
    #expect(
      !watchdog.canSendCleanupCommand(
        [0.4, 0.5, 0.4, 0.6], Date(unixSeconds: 1), Date(unixSeconds: 0)))

    // recent CPU loads >= 0.66
    #expect(
      !watchdog.canSendCleanupCommand(
        [0.1, 0.1, 0.7, 0.7], Date(unixSeconds: 1), Date(unixSeconds: 0)))

    // average CPU loads >= 0.33
    #expect(
      !watchdog.canSendCleanupCommand(
        [1.0, 1.0, 1.0, 1.0, 0.1, 0.1], Date(unixSeconds: 1), Date(unixSeconds: 0)))

    #expect(
      watchdog.canSendCleanupCommand(
        [0.1, 0.1, 0.1, 0.1, 0.1], Date(unixSeconds: 1), Date(unixSeconds: 0)))
  }
}
