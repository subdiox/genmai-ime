// Port of mozc/src/session/session_watch_dog.{h,cc} (3.35.6354).
//
// Session WatchDog timer
//
// Swift notes: the C++ watch dog talks to the server through
// client::ClientInterface (IPC). GenmaiSession cannot depend on GenmaiClient, so
// the client is abstracted as `SessionWatchDogClient` (the IME passes an
// object that sends CLEANUP to its in-process SessionHandler). The background
// thread is a detached Task; `stop()` (or deinit) cancels it.

import Foundation
import GenmaiBase
import Synchronization

/// The subset of client::ClientInterface used by the watch dog.
public protocol SessionWatchDogClient: AnyObject, Sendable {
  func setTimeout(_ timeout: Duration)
  func cleanup() -> Bool
  func reset()
  func pingServer() -> Bool
}

// IPC timeout
private let kCleanupTimeout = Duration.seconds(30)
private let kPingTimeout = Duration.seconds(5)

// number of trials for ping
private let kPingTrial: Int32 = 3
private let kPingInterval = Duration.seconds(1)

// Average CPU load for last 1 min.
// If the load > kMinimumAllCPULoad, don't send Cleanup
private let kMinimumAllCPULoad: Float = 0.33

// Average CPU load for last 10 secs.
// If the load > kMinimumLatestCPULoad, don't send Cleanup
private let kMinimumLatestCPULoad: Float = 0.66

/// SessionWatchDog class sends Cleanup command to Sessionhandler
/// for every some specified seconds.
public final class SessionWatchDog: Sendable {
  /// Returns the interval of this watch dog.
  public let interval: Duration
  private let task = Mutex<Task<Void, Never>?>(nil)

  /// Constructs the watch dog without a client (CanSendCleanupCommand only).
  public convenience init(_ interval: Duration) {
    self.init(interval, nil, CPUStats(), start: false)
  }

  /// DI constructor. Starts the background loop when `client` is given, as a
  /// detached task with `priority` (tests raise it so that the loop keeps its
  /// timing on a busy cooperative pool, like the C++ watch dog thread).
  /// `cpuStats` (not Sendable) is handed over to the loop's task.
  public init(
    _ interval: Duration, _ client: (any SessionWatchDogClient)?,
    _ cpuStats: sending any CPUStatsInterface, start: Bool = true, priority: TaskPriority? = nil
  ) {
    // allow [1..600].
    self.interval = min(max(interval, .seconds(1)), .seconds(600))
    if start, let client {
      let interval = self.interval
      let t = Task.detached(priority: priority) {
        await SessionWatchDog.threadMain(interval, client, cpuStats)
      }
      task.withLock { $0 = t }
    }
  }

  deinit {
    stop()
  }

  /// Stops the watchdog.
  public func stop() {
    task.withLock {
      $0?.cancel()
      $0 = nil
    }
  }

  /// Sleeps for `d`; returns true if stop was requested.
  private static func waitForStop(_ d: Duration) async -> Bool {
    if d > .zero {
      try? await Task.sleep(for: d)
    }
    return Task.isCancelled
  }

  private static func threadMain(
    _ interval: Duration, _ client: any SessionWatchDogClient, _ cpuStats: any CPUStatsInterface
  ) async {
    // CPU load check
    var cpuLoads = [Float](repeating: 0, count: 16)  // 60/5 = 12 is the minimal size
    let numberOfProcessors = cpuStats.getNumberOfProcessors()

    // the first (interval_sec_ - 60) sec: -> Do nothing
    let idleInterval = max(Duration.zero, interval - .seconds(60))

    // last 60 sec: -> check CPU usage
    let cpuCheckInterval = min(Duration.seconds(60), interval)

    // for every 5 second, get CPU load percentage
    let cpuCheckDuration = min(Duration.seconds(5), interval)

    var lastCleanupTime = Clock.getAbslTime()

    while true {
      if await waitForStop(idleInterval) {
        return
      }

      var cpuLoadsIndex = 0
      var n = Duration.zero
      while n < cpuCheckInterval {
        if await waitForStop(cpuCheckDuration) {
          return
        }
        // save them in stack for debugging
        let totalCpuLoad = cpuStats.getSystemCPULoad()
        let currentProcessCpuLoad = cpuStats.getCurrentProcessCPULoad()
        // subtract the CPU load of my process from total CPU load.
        // This is required for running stress test.
        let extractedCpuLoad = totalCpuLoad - currentProcessCpuLoad / Float(numberOfProcessors)
        cpuLoads[cpuLoadsIndex] = max(0.0, extractedCpuLoad)
        cpuLoadsIndex += 1
        n += cpuCheckDuration
      }

      let currentCleanupTime = Clock.getAbslTime()
      if !canSendCleanupCommand(
        interval, Array(cpuLoads[0..<cpuLoadsIndex]), currentCleanupTime, lastCleanupTime)
      {
        lastCleanupTime = currentCleanupTime
        continue
      }

      lastCleanupTime = currentCleanupTime

      client.setTimeout(kCleanupTimeout)
      if client.cleanup() {
        continue
      }

      GenmaiLog.warning("Cleanup failed execute PingCommand to check server is running")

      var failed = true
      client.reset()
      client.setTimeout(kPingTimeout)
      for i in 0..<kPingTrial {
        if await waitForStop(kPingInterval) {
          return
        }
        if client.pingServer() {
          failed = false
          break
        }
        GenmaiLog.error("Ping command failed, waiting \(kPingInterval), trial: \(i)")
      }

      if failed {
        if await waitForStop(.milliseconds(100)) {
          return
        }
        // C++: LOG(FATAL) << "Cleanup commands failed. Rasing exception...";
        GenmaiLog.error("Cleanup commands failed.")
        return
      }
    }
  }

  /// Returns true if watch dog can send CleanupCommand:
  /// |cpu_loads|: An array of cpu loads.
  /// |cpu_load_index|: the size of cpu loads
  /// |last_cleanup_time|: the last UTC time cleanup is executed
  public func canSendCleanupCommand(
    _ cpuLoads: [Float], _ currentCleanupTime: Date, _ lastCleanupTime: Date
  ) -> Bool {
    SessionWatchDog.canSendCleanupCommand(interval, cpuLoads, currentCleanupTime, lastCleanupTime)
  }

  private static func canSendCleanupCommand(
    _ interval: Duration, _ cpuLoads: [Float], _ currentCleanupTime: Date,
    _ lastCleanupTime: Date
  ) -> Bool {
    if currentCleanupTime <= lastCleanupTime {
      GenmaiLog.error("time stamps are the same. clock may be altered")
      return false
    }

    // std::accumulate with a double init value.
    let sum = cpuLoads.reduce(0.0) { $0 + Double($1) }
    let allAvg = Float(sum / Double(cpuLoads.count))

    let latestSize = min(2, cpuLoads.count)
    let latestAvg = Float(sum / Double(latestSize))

    if allAvg > kMinimumAllCPULoad || latestAvg > kMinimumLatestCPULoad {
      return false
    }

    // if the real interval from the last cleanup command
    // is 2 * interval(), assume that the computer went to
    // suspend mode
    if (currentCleanupTime - lastCleanupTime) > interval * 2 {
      return false
    }

    return true
  }
}
