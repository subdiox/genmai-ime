// Port of mozc/src/session/session_handler_scenario_test.cc (3.35.6354).
//
// Runs the scenario files in Vendor/mozc/src/data/test/session/scenario with
// the mock data engine (MockDataEngineFactory), like the C++ test.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

// Tests should be passed.
let kScenarioFileList: [String] = [
  "auto_partial_suggestion.txt",
  "b12751061_scenario.txt",
  "b16123009_scenario.txt",
  "b18112966_scenario.txt",
  "b7132535_scenario.txt",
  "b7548679_scenario.txt",
  "b8690065_scenario.txt",
  "b8703702_scenario.txt",
  "change_request.txt",
  "clear_user_prediction.txt",
  "commit.txt",
  "commit_by_space.txt",
  "composing_alphanumeric.txt",
  "composition_display_as.txt",
  "composition_itchome.txt",
  "conversion.txt",
  "conversion_display_as.txt",
  "conversion_with_history_segment.txt",
  "conversion_with_long_history_segments.txt",
  "convert_from_full_ascii_to_t13n.txt",
  "convert_from_full_katakana_to_t13n.txt",
  "convert_from_half_ascii_to_t13n.txt",
  "convert_from_half_katakana_to_t13n.txt",
  "convert_from_hiragana_to_t13n.txt",
  "delete_history.txt",
  "description.txt",
  "desktop_t13n_candidates.txt",
  "domain_suggestion.txt",
  // "InputModeX" commands are not supported on Mac (input_mode.txt is
  // excluded on __APPLE__).
  "handwriting.txt",
  "insert_characters.txt",
  "mobile_partial_variant_candidates.txt",
  "on_off_cancel.txt",
  "partial_suggestion.txt",
  "pending_character.txt",
  "predict_and_convert.txt",
  "reconvert.txt",
  "revert.txt",
  "segment_focus.txt",
  "segment_width.txt",
  "suggest_after_zero_query.txt",
  "switch_kana_type.txt",
  "t13n_negative_number.txt",
  "t13n_rewriter_twice.txt",
  "toggle_flick_hiragana_preedit_a.txt",
  "toggle_flick_hiragana_preedit_ka.txt",
  "toggle_flick_hiragana_preedit_sa.txt",
  "toggle_flick_hiragana_preedit_ta.txt",
  "toggle_flick_hiragana_preedit_na.txt",
  "toggle_flick_hiragana_preedit_ha.txt",
  "toggle_flick_hiragana_preedit_ma.txt",
  "toggle_flick_hiragana_preedit_ya.txt",
  "toggle_flick_hiragana_preedit_ra.txt",
  "toggle_flick_hiragana_preedit_wa.txt",
  "toggle_flick_hiragana_preedit_symbol.txt",
  "transliterations_f10.txt",
  "twelvekeys_switch_inputmode_scenario.txt",
  "twelvekeys_toggle_flick_alphabet_scenario.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_a.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_ka.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_sa.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_ta.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_na.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_ha.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_ma.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_ya.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_ra.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_wa.txt",
  "twelvekeys_toggle_hiragana_preedit_scenario_symbol.txt",
  "undo.txt",
  "undo_partial_commit.txt",
  "zero_query_suggestion.txt",
]

let kScenariosForExperimentParams: [String] = [
  "mobile_apply_user_segment_history_rewriter.txt",
  "mobile_delete_history.txt",
  "mobile_preedit.txt",
  "mobile_qwerty_transliteration_scenario.txt",
  "mobile_revert_user_history_learning.txt",
  "mobile_switch_composition_mode.txt",
  "mobile_t13n_candidates.txt",
  "mobile_zero_query.txt",
]

func getMobileRequest() -> Genmai_Commands_Request {
  var request = Genmai_Commands_Request()
  RequestTestUtil.fillMobileRequest(&request)
  return request
}

struct ScenarioResult {
  var steps = 0
  var failures: [String] = []
}

/// Runs one scenario file (TestImplBase). Failures are collected per line
/// (FAIL() in ParseLine does not stop the loop in C++).
func runScenario(
  _ file: String, request: Genmai_Commands_Request? = nil,
  engineFactory: () throws -> any EngineInterface = { try MockDataEngineFactory.create() }
) async throws -> ScenarioResult {
  try await withScopedSessionEnvironment {
    // SessionHandlerTestBase::SetUp -> ClearState.
    var config = Genmai_Config_Config()
    ConfigHandler.getDefaultConfig(&config)
    ConfigHandler.setConfig(config)
    CharacterFormManager.getCharacterFormManager().reloadConfig(config)

    let engine = try engineFactory()
    let handler = SessionHandlerInterpreter(engine)

    // Open the scenario file.
    let scenarioPath = SessionTestPaths.upstreamSourceFile(["data", "test", "session", "scenario", file])
    guard let inputStream = try? String(contentsOfFile: scenarioPath, encoding: .utf8) else {
      throw SessionHandlerInterpreterError.invalidArgument("cannot open \(scenarioPath)")
    }
    await handler.clearAll()
    if let request {
      handler.setRequest(request)
    }

    var result = ScenarioResult()
    // std::getline splits at '\n' only.
    var lines = inputStream.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if inputStream.hasSuffix("\n") {
      lines.removeLast()
    }
    for (index, lineText) in lines.enumerated() {
      let lineNumber = index + 1
      let args = handler.parse(lineText)
      if args.isEmpty {
        continue
      }
      result.steps += 1
      do {
        try await handler.eval(args)
      } catch {
        result.failures.append("Scenario: \(lineText) [\(file):\(lineNumber)]\n\(error)")
      }
    }
    return result
  }
}

@Suite struct SessionHandlerScenarioTest {
  @Test(arguments: kScenarioFileList)
  func testImplBase(_ file: String) async throws {
    let result = try await runScenario(file)
    for failure in result.failures {
      Issue.record(Comment(rawValue: failure))
    }
  }
}

@Suite struct SessionHandlerScenarioTestForRequest {
  // Makes sure that the results are not changed by experiment params.
  @Test(arguments: kScenariosForExperimentParams)
  func testImplBase(_ file: String) async throws {
    let result = try await runScenario(file, request: getMobileRequest())
    for failure in result.failures {
      Issue.record(Comment(rawValue: failure))
    }
  }
}

/// Sanity checks of the scenario runner itself (not in the C++ test): an
/// unmet expectation must be reported, and every scenario line is evaluated.
@Suite struct SessionHandlerScenarioRunnerSanityTest {
  @Test func failingExpectationIsReported() async throws {
    try await withScopedSessionEnvironment {
      let handler = SessionHandlerInterpreter(try MockDataEngineFactory.create())
      await handler.clearAll()
      try await handler.eval(handler.parse("SEND_KEYS\tkyouha"))
      try await handler.eval(handler.parse("EXPECT_PREEDIT\tきょうは"))
      await #expect(throws: SessionHandlerInterpreterError.self) {
        try await handler.eval(handler.parse("EXPECT_PREEDIT\tきのうは"))
      }
      await #expect(throws: SessionHandlerInterpreterError.self) {
        try await handler.eval(handler.parse("NO_SUCH_COMMAND"))
      }
    }
  }

  @Test func allScenarioStepsAreEvaluated() async throws {
    var files = 0
    var steps = 0
    var failures = 0
    for file in kScenarioFileList {
      let result = try await runScenario(file)
      files += 1
      steps += result.steps
      failures += result.failures.count
    }
    for file in kScenariosForExperimentParams {
      let result = try await runScenario(file, request: getMobileRequest())
      files += 1
      steps += result.steps
      failures += result.failures.count
    }
    print("Scenario summary: \(files) files, \(steps) steps, \(failures) failures")
    #expect(files == kScenarioFileList.count + kScenariosForExperimentParams.count)
    #expect(steps > 5000)
  }
}

// MARK: - Parity with the C++ oracle (session/session_handler_main --test)

/// Runs a scenario file like session_handler_main.cc `--test`: a fresh user
/// profile, no ClearAll / SetRequest, every line evaluated. Returns the line
/// numbers whose evaluation failed.
func runScenarioLikeSessionHandlerMain(
  _ file: String, engineFactory: () throws -> any EngineInterface
) async throws -> [Int] {
  try await withScopedSessionEnvironment {
    let handler = SessionHandlerInterpreter(try engineFactory())
    let scenarioPath = SessionTestPaths.upstreamSourceFile(["data", "test", "session", "scenario", file])
    let text = try String(contentsOfFile: scenarioPath, encoding: .utf8)
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if text.hasSuffix("\n") {
      lines.removeLast()
    }
    var failed: [Int] = []
    for (index, line) in lines.enumerated() {
      let args = handler.parse(line)
      if args.isEmpty {
        continue
      }
      do {
        try await handler.eval(args)
      } catch {
        failed.append(index + 1)
      }
    }
    return failed
  }
}

struct ScenarioOracleRow: Sendable, CustomStringConvertible {
  let dictionary: String
  let file: String
  let failedLines: [Int]
  var description: String { "\(dictionary)/\(file)" }
}

/// Tests/Fixtures/session/scenario_oracle.tsv
let kScenarioOracleRows: [ScenarioOracleRow] = {
  let path = SessionTestPaths.repoRoot.appendingPathComponent(
    "Tests/Fixtures/session/scenario_oracle.tsv"
  ).path
  guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
  var rows: [ScenarioOracleRow] = []
  for line in text.split(separator: "\n") where !line.hasPrefix("#") {
    let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard cols.count >= 3 else { continue }
    let failed = cols.count > 3 ? cols[3].split(separator: ",").compactMap { Int($0) } : []
    rows.append(ScenarioOracleRow(dictionary: cols[0], file: cols[1], failedLines: failed))
  }
  return rows
}()

/// The failing lines of every scenario file must be exactly those of the C++
/// session_handler_main with the same data set (mock: data_manager/testing,
/// oss: Data/genmai.data).
@Suite struct SessionHandlerScenarioOracleParityTest {
  @Test(arguments: kScenarioOracleRows)
  func sameFailingLinesAsOracle(_ row: ScenarioOracleRow) async throws {
    if row.dictionary == "oss" && !SessionTestPaths.ossDataAvailable {
      return
    }
    let failed = try await runScenarioLikeSessionHandlerMain(
      row.file,
      engineFactory: {
        row.dictionary == "oss"
          ? try OssEngineFactory.create() : try MockDataEngineFactory.create()
      })
    #expect(failed == row.failedLines, "\(row.dictionary) \(row.file)")
  }
}
