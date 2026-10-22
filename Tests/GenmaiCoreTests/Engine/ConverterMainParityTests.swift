// Parity of ConverterMain (port of mozc/src/converter/converter_main.cc,
// 3.35.6354) with the C++ converter_main oracle, in process.
//
// Runs the command fixtures of Tests/Fixtures/oracle through a fresh Engine
// (Data/genmai.data) with an empty temporary user profile, exactly like
// Tools/compare_oracle.sh does with the genmai-engine CLI, and compares the
// printed output with the stored oracle output:
//   conversion_commands.txt -> conversion_top10.txt (734 conversions)
//   prediction_commands.txt -> prediction_top10.txt, prediction_mobile_top10.txt
//   sessions_commands.txt   -> sessions_top5.txt (50 scripted sessions)
//   sessions_mobile_commands.txt -> sessions_mobile_top5.txt
// Excluded from the comparison: the banner lines (paths) and the `log:` lines
// with their continuation lines. The oracle is a debug (fastbuild) build of
// converter_main whose candidates carry MOZC_DEBUG logs; they are not part of
// the parity target.
//
// Fixture runs start with "=== <name> @<unix time>": the time the oracle ran.
// The clock is mocked to that time (advancing in real time) so that date /
// time candidates (いま → 20:31, きょう → 2026/10/20, ...) match. The
// prediction fixtures have no header and run with the real clock.
// Regenerate the fixtures with `Tools/compare_oracle.sh --regenerate`.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private enum ParityPaths {
  static let oracleDir: URL = {
    var url = URL(fileURLWithPath: #filePath)
    // Tests/GenmaiCoreTests/Engine/<file>.swift -> repository root
    for _ in 0..<4 {
      url.deleteLastPathComponent()
    }
    return url.appendingPathComponent("Tests/Fixtures/oracle")
  }()

  static let idDef = DataManagerTestSupport.sourcePath("data", "dictionary_oss", "id.def")

  static func lines(_ name: String) throws -> [String] {
    let text = try String(contentsOf: oracleDir.appendingPathComponent(name), encoding: .utf8)
    var lines = text.components(separatedBy: "\n")
    if lines.last == "" {
      lines.removeLast()
    }
    return lines
  }
}

/// The clock of `--fake_time_for_testing`: starts at `base` and advances in
/// real time.
private final class ParityClock: ClockInterface {
  private let base: Date
  private let start = Date()
  init(_ base: Date) { self.base = base }
  func getAbslTime() -> Date { base.addingTimeInterval(Date().timeIntervalSince(start)) }
  func getTimeZone() -> TimeZone { TimeZone.current }
}

/// One converter_main run: a name, the oracle time and lines (banner + output).
private struct OracleRun {
  var name: String
  var time: Int64?
  var lines: [String]
}

/// Splits "=== <name> @<time>" runs (a single run without a header otherwise).
private func splitRuns(_ lines: [String]) -> [OracleRun] {
  guard let first = lines.first, first.hasPrefix("=== ") else {
    return [OracleRun(name: "", time: nil, lines: lines)]
  }
  var runs: [OracleRun] = []
  for line in lines {
    if line.hasPrefix("=== ") {
      var header = String(line.dropFirst(4))
      var time: Int64?
      if let at = header.range(of: " @", options: .backwards) {
        time = Int64(header[at.upperBound...])
        header = String(header[..<at.lowerBound])
      }
      runs.append(OracleRun(name: header, time: time, lines: []))
    } else {
      runs[runs.count - 1].lines.append(line)
    }
  }
  return runs
}

/// Removes `log:` lines and their indented continuation lines.
private func stripLogs(_ lines: [String]) -> [String] {
  var out: [String] = []
  var inLog = false
  for line in lines {
    if line == "       log:" {
      inLog = true
      continue
    }
    if inLog && line.hasPrefix("           ") {
      continue
    }
    inLog = false
    out.append(line)
  }
  return out
}

/// Per-command output blocks (see Tools/compare_oracle.py).
private func outputBlocks(_ lines: [String]) -> [[String]] {
  var result: [[String]] = []
  var current: [String] = []
  var expectKey = false
  for line in stripLogs(lines) {
    if expectKey {
      // The segment key line (may be empty, e.g. for zero query suggestion).
      current.append(line)
      expectKey = false
      continue
    }
    if line.hasPrefix("---------- Segment ") {
      current.append(line)
      expectKey = true
      continue
    }
    if current.isEmpty && line == "ExecCommand() return false" {
      result.append([line])
      continue
    }
    if line.isEmpty {
      result.append(current)
      current = []
      continue
    }
    current.append(line)
  }
  if !current.isEmpty {
    result.append(current)
  }
  return result
}

/// Splits a commands file into sessions ("=== name" lines) or one run.
private func splitCommands(_ lines: [String], _ singleName: String) -> [(String, [String])] {
  guard let first = lines.first, first.hasPrefix("=== ") else {
    return [(singleName, lines)]
  }
  var result: [(String, [String])] = []
  for line in lines {
    if line.hasPrefix("=== ") {
      result.append((String(line.dropFirst(4)), []))
    } else {
      result[result.count - 1].1.append(line)
    }
  }
  return result
}

/// Runs `commands` through a fresh engine like one converter_main process and
/// returns the output lines without the banner.
private func runConverterMain(
  _ commands: [String], mobile: Bool, maxCandidatesToShow: Int, time: Int64?
) throws -> [String] {
  try SystemUtil.withTempUserProfile { _ in
    try CharacterFormManager.withScopedManagerForTesting {
      let body = { () throws -> [String] in
        let engine = try Engine.createEngine(OssDataManager.create())
        var config = ConfigHandler.defaultConfig()
        var request = Genmai_Commands_Request()
        if mobile {
          RequestTestUtil.fillMobileRequest(&request)
          config.useKanaModifierInsensitiveConversion = true
          config.useTypingCorrection = true
        }
        var options = ConverterMain.Options()
        options.maxCandidatesToShow = maxCandidatesToShow
        options.idDef = ParityPaths.idDef
        let converterMain = ConverterMain(engine, request, config, options)
        converterMain.loadSupplementalModel("")
        var output = ""
        for command in commands {
          output += converterMain.execCommandToString(command)
          output += "\n"
        }
        var lines = output.components(separatedBy: "\n")
        if lines.last == "" {
          lines.removeLast()
        }
        return lines
      }
      if let time {
        return try Clock.withClock(ParityClock(Date(timeIntervalSince1970: TimeInterval(time))), body)
      }
      return try body()
    }
  }
}

@Suite(.enabled(if: DataManagerTestSupport.hasOssData, "genmai.data is missing; run Tools/build_oracle.sh"))
struct ConverterMainParityTests {
  @Test func conversionTop10() throws {
    try checkParity("conversion_commands.txt", "conversion_top10.txt", mobile: false, show: 10)
  }

  @Test func predictionTop10() throws {
    try checkParity("prediction_commands.txt", "prediction_top10.txt", mobile: false, show: 10)
  }

  @Test func mobilePredictionTop10() throws {
    try checkParity(
      "prediction_commands.txt", "prediction_mobile_top10.txt", mobile: true, show: 10)
  }

  /// 50 scripted sessions (learning, resize, focus, commitfirstsegment, user
  /// history disabled / enabled, prediction, zero query, reverse, ...).
  @Test func sessionsTop5() throws {
    try checkParity("sessions_commands.txt", "sessions_top5.txt", mobile: false, show: 5)
  }

  /// The sessions without resize (C++ converter_main CHECK-fails on resize
  /// with a mobile request).
  @Test func mobileSessionsTop5() throws {
    try checkParity(
      "sessions_mobile_commands.txt", "sessions_mobile_top5.txt", mobile: true, show: 5)
  }

  private func checkParity(_ commandsFile: String, _ expectedFile: String, mobile: Bool, show: Int)
    throws
  {
    let sessions = splitCommands(try ParityPaths.lines(commandsFile), commandsFile)
    let runs = splitRuns(try ParityPaths.lines(expectedFile))
    try #require(runs.count == sessions.count, "\(expectedFile) does not match \(commandsFile)")

    var total = 0
    var mismatches = 0
    for (run, (name, commands)) in zip(runs, sessions) {
      if !run.name.isEmpty {
        #expect(run.name == name || runs.count == 1)
      }
      let expected = outputBlocks(Array(run.lines.dropFirst(4)))
      let actual = outputBlocks(
        try runConverterMain(commands, mobile: mobile, maxCandidatesToShow: show, time: run.time))
      #expect(expected.count == commands.count, "\(name): oracle blocks")
      let n = max(expected.count, actual.count)
      total += n
      for i in 0..<n {
        let e = i < expected.count ? expected[i] : ["<missing>"]
        let a = i < actual.count ? actual[i] : ["<missing>"]
        if e == a {
          continue
        }
        mismatches += 1
        if mismatches <= 5 {
          let label = i < commands.count ? commands[i] : "#\(i)"
          print("PARITY MISMATCH (\(expectedFile)) \(name) #\(i): \(label)")
          for k in 0..<max(e.count, a.count) {
            let o = k < e.count ? e[k] : "-"
            let w = k < a.count ? a[k] : "-"
            if o != w {
              print("  oracle: \(o)\n  swift:  \(w)")
            }
          }
        }
      }
    }
    print("converter_main parity (\(expectedFile)): \(total - mismatches)/\(total) commands match")
    #expect(mismatches == 0)
  }
}
