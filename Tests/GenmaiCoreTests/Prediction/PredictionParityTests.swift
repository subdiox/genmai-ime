// Parity check of the prediction stack against the C++ oracle (not a port of
// a C++ test).
//
// Tests/Fixtures/oracle/prediction_top10.txt is the output of
//   head -200 Tests/Fixtures/oracle/conversion_inputs.txt | sed 's/^/p /' |
//     Tools/oracle.sh --max_candidates_to_show 10 --user_profile_dir <empty dir>
// (the "User profile dir:" header line is replaced by a placeholder), and
// prediction_mobile_top10.txt the same with --engine_type mobile.
//
// The full engine-level text comparison is done by the engine port. This test
// runs Converter.startPrediction with the Swift Predictor (DictionaryPredictor
// + UserHistoryPredictor), ImmutableConverter and RewriterImpl like
// converter_main's "p" command, and compares the candidate values (top 10)
// of each input with their key, cost, structure cost, wcost, lid and rid.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

/// engine::Modules for the full stack (OSS data).
private final class FullStackModules: PredictionModules, UserHistoryPredictorModules,
  RewriterModules
{
  let base: PredictionTestModules
  let posGroup: PosGroup
  let immutableConverter: ImmutableConverter

  init(_ base: PredictionTestModules) {
    self.base = base
    posGroup = PosGroup(base.dataManager.getPosGroupData())
    immutableConverter = ImmutableConverter(
      dictionary: base.dictionary, suffixDictionary: base.suffixDictionary,
      userDictionary: base.userDictionary, connector: base.connector, segmenter: base.segmenter,
      posMatcher: base.posMatcher, posGroup: posGroup, suggestionFilter: base.suggestionFilter)
  }

  func getPosMatcher() -> PosMatcher { base.getPosMatcher() }
  func getUserDictionary() -> any UserDictionaryInterface { base.getUserDictionary() }
  func getSupplementalModel() -> any ConverterSupplementalModel { base.getSupplementalModel() }
  func getDataManager() -> DataManager { base.getDataManager() }
  func getConnector() -> Connector { base.getConnector() }
  func getSegmenter() -> Segmenter { base.getSegmenter() }
  func getDictionary() -> any DictionaryInterface { base.getDictionary() }
  func getSuffixDictionary() -> any DictionaryInterface { base.getSuffixDictionary() }
  func getSuggestionFilter() -> SuggestionFilter { base.getSuggestionFilter() }
  func getSingleKanjiDictionary() -> SingleKanjiDictionary { base.getSingleKanjiDictionary() }
  func getZeroQueryDict() -> ZeroQueryDict { base.getZeroQueryDict() }
  func getZeroQueryNumberDict() -> ZeroQueryDict { base.getZeroQueryNumberDict() }
  func getUserHistoryStorage() -> UserHistoryStorage { base.getUserHistoryStorage() }
  func getUserHistorySupplementalModel() -> any UserHistorySupplementalModel {
    base.getUserHistorySupplementalModel()
  }
  func getPosGroup() -> PosGroup { posGroup }
  func getReadingAlignmentSupplementalModel() -> (any ReadingAlignmentSupplementalModel)? { nil }
}

/// One printed candidate: "value key cost wcost lid rid".
private struct OracleCandidate: Equatable, CustomStringConvertible {
  var value = ""
  var key = ""
  var cost = 0
  var structureCost = 0
  var wcost = 0
  var lid = 0
  var rid = 0
  var description: String {
    "\(value)[\(key)] c=\(cost) s=\(structureCost) w=\(wcost) l=\(lid) r=\(rid)"
  }
}

/// Parses converter_main output into per-command candidate lists.
private func parseOracle(_ text: String) -> [[OracleCandidate]] {
  var blocks: [[OracleCandidate]] = []
  var current: [OracleCandidate]?
  var segmentKey = ""
  var expectSegmentKey = false
  func lastNumber(_ line: Substring) -> Int {
    // "... (1906)"
    guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")") else { return -1 }
    return Int(line[line.index(after: open)..<close]) ?? -1
  }
  for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
    if line.hasPrefix("---------- Segment 0/") {
      if let current { blocks.append(current) }
      current = []
      expectSegmentKey = true
      continue
    }
    if expectSegmentKey {
      segmentKey = String(line)
      expectSegmentKey = false
      continue
    }
    guard current != nil else { continue }
    if line.hasPrefix("       ") {
      let field = line.drop { $0 == " " }
      guard var c = current?.popLast() else { continue }
      if field.hasPrefix("key: ") {
        c.key = String(field.dropFirst(5))
      } else if field.hasPrefix("cost: ") {
        let nums = field.split(separator: " ").compactMap { Int($0) }
        if nums.count == 3 {
          c.cost = nums[0]
          c.structureCost = nums[1]
          c.wcost = nums[2]
        }
      } else if field.hasPrefix("lid: ") {
        c.lid = lastNumber(field)
      } else if field.hasPrefix("rid: ") {
        c.rid = lastNumber(field)
      }
      current?.append(c)
      continue
    }
    // "  i/N value"
    guard line.hasPrefix("  ") else { continue }
    let body = line.dropFirst(2)
    guard let space = body.firstIndex(of: " ") else { continue }
    let index = body[..<space]
    guard index.contains("/"), index.split(separator: "/").allSatisfy({ Int($0) != nil }) else {
      continue
    }
    var c = OracleCandidate()
    c.value = String(body[body.index(after: space)...])
    c.key = segmentKey
    current?.append(c)
  }
  if let current { blocks.append(current) }
  return blocks
}

@Suite(
  .enabled(if: DataManagerTestSupport.hasOssData, "genmai.data is missing; run Tools/build_oracle.sh"))
struct PredictionParityTests {
  @Test func predictionTop10Values() throws {
    try checkParity("prediction_top10.txt", mobile: false)
  }

  /// `--engine_type mobile` (FillMobileRequest, kana modifier insensitive
  /// conversion and typing correction enabled in the config).
  @Test func mobilePredictionTop10Values() throws {
    try checkParity("prediction_mobile_top10.txt", mobile: true)
  }

  private func checkParity(_ fixture: String, mobile: Bool) throws {
    let oracleText = try String(
      contentsOf: PredictionTestPaths.oracleDir.appendingPathComponent(fixture),
      encoding: .utf8)
    let expected = parseOracle(oracleText)
    let inputs = try String(
      contentsOf: PredictionTestPaths.oracleDir.appendingPathComponent("conversion_inputs.txt"),
      encoding: .utf8
    ).split(separator: "\n").prefix(200).map(String.init)
    try #require(expected.count == inputs.count)

    try SystemUtil.withTempUserProfile { _ in
      try CharacterFormManager.withScopedManagerForTesting {
        let base = try #require(try PredictionTestModules.oss())
        let modules = FullStackModules(base)
        let converter = Converter(
          modules, { _ in modules.immutableConverter },
          { _, conv, immutable in Predictor(modules, conv, immutable) },
          { _ in RewriterImpl(modules) })

        var config = Genmai_Config_Config()
        ConfigHandler.getDefaultConfig(&config)
        var request = Genmai_Commands_Request()
        if mobile {
          RequestTestUtil.fillMobileRequest(&request)
          config.useKanaModifierInsensitiveConversion = true
          config.useTypingCorrection = true
        }
        var composer = Composer(request, config)
        let segments = Segments()

        var mismatches = 0
        for (i, input) in inputs.enumerated() {
          var options = ConversionOptions()
          options.maxConversionCandidatesSize = 200
          options.useActualConverterForRealtimeConversion = true
          options.createPartialCandidates = request.autoPartialSuggestion
          options.requestType = .prediction
          composer.reset()
          composer.setPreeditTextForTestOnly(input)
          let convreq = ConversionRequestBuilder()
            .setComposer(composer)
            .setRequestView(request)
            .setConfigView(config)
            .setOptions(options)
            .build()
          var actual: [OracleCandidate] = []
          if converter.startPrediction(convreq, segments), segments.conversionSegmentsSize > 0 {
            let segment = segments.conversionSegment(0)
            for j in 0..<min(10, segment.candidatesSize) {
              let cand = segment.candidate(j)
              actual.append(
                OracleCandidate(
                  value: cand.value, key: cand.key, cost: Int(cand.cost),
                  structureCost: Int(cand.structureCost), wcost: Int(cand.wcost),
                  lid: Int(cand.lid), rid: Int(cand.rid)))
            }
          }
          if actual != expected[i] {
            mismatches += 1
            if mismatches <= 10 {
              print("PREDICTION MISMATCH (\(fixture)) \(input):")
              for k in 0..<max(actual.count, expected[i].count) {
                let o = k < expected[i].count ? expected[i][k].description : "-"
                let w = k < actual.count ? actual[k].description : "-"
                print("  \(o == w ? " " : "*") oracle: \(o)\n    swift:  \(w)")
              }
            }
          }
        }
        print("prediction parity (\(fixture)): \(inputs.count - mismatches)/\(inputs.count) inputs match")
        #expect(mismatches == 0)
      }
    }
  }
}
