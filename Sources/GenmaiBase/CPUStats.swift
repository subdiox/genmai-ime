// Port of mozc/src/base/cpu_stats.{h,cc} (3.35.6354). macOS (mach) path.

#if canImport(Darwin)
  import Darwin
#endif

public protocol CPUStatsInterface: AnyObject {
  /// Returns the percentage of total CPU load since the last time
  /// this method was called. The return value must be in the range of
  /// [0.0 .. 1.0].
  func getSystemCPULoad() -> Float
  /// Returns the percentage of current process's CPU load
  /// since the last time this method was called.
  /// If the process has multi-threads, the return value
  /// may be larger than 1.0.
  func getCurrentProcessCPULoad() -> Float
  /// returns the number of processors.
  func getNumberOfProcessors() -> Int
}

/// default implementation
public final class CPUStats: CPUStatsInterface {
  private var prevSystemTotalTimes: UInt64 = 0
  private var prevSystemCPUTimes: UInt64 = 0
  private var prevCurrentProcessTotalTimes: UInt64 = 0
  private var prevCurrentProcessCPUTimes: UInt64 = 0

  public init() {}

  private static func timeValueToInt64(_ t: time_value_t) -> UInt64 {
    1_000_000 &* UInt64(t.seconds) &+ UInt64(t.microseconds)
  }

  private static func updateCPULoad(
    _ currentTotalTimes: UInt64, _ currentCPUTimes: UInt64,
    _ prevTotalTimes: inout UInt64, _ prevCPUTimes: inout UInt64
  ) -> Float {
    var result: Float = 0.0
    if currentTotalTimes < prevTotalTimes || currentCPUTimes < prevCPUTimes {
      GenmaiLog.error("Inconsistent time values are passed. ignored")
    } else {
      let totalDiff = currentTotalTimes - prevTotalTimes
      let cpuDiff = currentCPUTimes - prevCPUTimes
      result = totalDiff == 0 ? 0.0 : Float(1.0 * Double(cpuDiff) / Double(totalDiff))
    }
    prevTotalTimes = currentTotalTimes
    prevCPUTimes = currentCPUTimes
    return result
  }

  /// return 0.0 if CPU load is unknown
  public func getSystemCPULoad() -> Float {
    var cpuInfo = host_cpu_load_info_data_t()
    var infoCount = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &cpuInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &infoCount)
      }
    }
    if kr != KERN_SUCCESS {
      GenmaiLog.error("::host_statistics() failed")
      return 0.0
    }
    let ticks = cpuInfo.cpu_ticks
    // CPU_STATE_USER = 0, CPU_STATE_SYSTEM = 1, CPU_STATE_IDLE = 2,
    // CPU_STATE_NICE = 3.
    let cpuTimes = UInt64(ticks.3) + UInt64(ticks.1) + UInt64(ticks.0)  // NICE + SYSTEM + USER
    let totalTimes = cpuTimes + UInt64(ticks.2)  // + IDLE
    return CPUStats.updateCPULoad(totalTimes, cpuTimes, &prevSystemTotalTimes, &prevSystemCPUTimes)
  }

  /// return 0.0 if CPU load is unknown
  public func getCurrentProcessCPULoad() -> Float {
    var info = task_thread_times_info_data_t()
    var infoCount = mach_msg_type_number_t(
      MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
        task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &infoCount)
      }
    }
    if kr != KERN_SUCCESS {
      GenmaiLog.error("::task_info() failed")
      return 0.0
    }
    // OSX has no host_get_time(), use gettimeofday instead.
    var tv = timeval()
    gettimeofday(&tv, nil)
    let totalTimes = 1_000_000 &* UInt64(tv.tv_sec) &+ UInt64(tv.tv_usec)
    let cpuTimes =
      CPUStats.timeValueToInt64(info.user_time)
      &+ CPUStats.timeValueToInt64(info.system_time)
    return CPUStats.updateCPULoad(
      totalTimes, cpuTimes, &prevCurrentProcessTotalTimes, &prevCurrentProcessCPUTimes)
  }

  /// return the number of processors
  public func getNumberOfProcessors() -> Int {
    var basicInfo = host_basic_info_data_t()
    var infoCount = mach_msg_type_number_t(
      MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &basicInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
        host_info(mach_host_self(), HOST_BASIC_INFO, $0, &infoCount)
      }
    }
    if kr != KERN_SUCCESS {
      GenmaiLog.error("::host_info() failed")
      return 1
    }
    return Int(basicInfo.avail_cpus)
  }
}
