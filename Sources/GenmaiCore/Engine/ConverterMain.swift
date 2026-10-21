// Port of the conversion command interpreter and printing of
// mozc/src/converter/converter_main.cc (3.35.6354).
//
// converter_main.cc is the CLI used as the parity oracle (Tools/oracle.sh).
// Its `ConverterMain` class and the segment printing functions live here (in
// the Engine folder, since they need Engine) so that both the `genmai-engine`
// CLI (Sources/genmai-engine/main.swift: flags and main()) and the in-process
// parity tests (Tests/GenmaiCoreTests/Engine/ConverterMainParityTests.swift)
// use the same code.
//
// Deviations from C++:
// - The absl flags read by the printing code (--max_conversion_candidates_size,
//   --max_candidates_to_show, --show_meta_candidates, --id_def) are
//   `ConverterMain.Options`.
// - `log:` lines (candidate debug logs) are printed only in debug builds, as
//   with MOZC_DEBUG in C++. The Swift logs are not expected to match the C++
//   ones; parity tools exclude them.
// - Output is returned as a String instead of written to std::ostream.

import GenmaiBase
import GenmaiProtocol

// MARK: - Printing

private func findCandidate(_ segment: Segment, _ value: String) -> Int {
  for i in 0..<segment.candidatesSize {
    if segment.candidate(i).value.bytesEqual(value) { return i }
  }
  return -1
}

/// IdToString with the --id_def printer.
private func idToString(_ printer: PosIdPrinter, _ id: Int) -> String {
  let posString = printer.idToString(id)
  if posString.isEmpty {
    return "\(id)"
  }
  return "\(posString) (\(id))"
}

private func segmentTypeToString(_ type: Segment.SegmentType) -> String {
  switch type {
  case .free: return "FREE"
  case .fixedBoundary: return "FIXED_BOUNDARY"
  case .fixedValue: return "FIXED_VALUE"
  case .submitted: return "SUBMITTED"
  case .history: return "HISTORY"
  }
}

private func candidateAttributesToString(_ attrs: UInt32) -> String {
  var v: [String] = []
  func add(_ attribute: UInt32, _ name: String) {
    if attrs & attribute != 0 { v.append(name) }
  }
  add(Attribute.bestCandidate, "BEST_CANDIDATE")
  add(Attribute.reranked, "RERANKED")
  add(Attribute.noHistoryLearning, "NO_HISTORY_LEARNING")
  add(Attribute.noSuggestLearning, "NO_SUGGEST_LEARNING")
  add(Attribute.contextSensitive, "CONTEXT_SENSITIVE")
  add(Attribute.spellingCorrection, "SPELLING_CORRECTION")
  add(Attribute.noVariantsExpansion, "NO_VARIANTS_EXPANSION")
  add(Attribute.noExtraDescription, "NO_EXTRA_DESCRIPTION")
  add(Attribute.realtimeConversion, "REALTIME_CONVERSION")
  add(Attribute.userDictionary, "USER_DICTIONARY")
  add(Attribute.commandCandidate, "COMMAND_CANDIDATE")
  add(Attribute.partiallyKeyConsumed, "PARTIALLY_KEY_CONSUMED")
  add(Attribute.typingCorrection, "TYPING_CORRECTION")
  add(Attribute.autoPartialSuggestion, "AUTO_PARTIAL_SUGGESTION")
  add(Attribute.userHistoryPrediction, "USER_HISTORY_PREDICTION")
  add(Attribute.noModification, "NO_MODIFICATION")
  add(Attribute.userSegmentHistoryRewriter, "USER_SEGMENT_HISTORY_REWRITER")
  return v.joined(separator: " | ")
}

private func numberStyleToString(_ style: NumberUtil.NumberString.Style) -> String {
  switch style {
  case .defaultStyle: return "DEFAULT_STYLE"
  case .numberSeparatedArabicHalfwidth: return "NUMBER_SEPARATED_ARABIC_HALFWIDTH"
  case .numberSeparatedArabicFullwidth: return "NUMBER_SEPARATED_ARABIC_FULLWIDTH"
  case .numberArabicAndKanjiHalfwidth: return "NUMBER_ARABIC_AND_KANJI_HALFWIDTH"
  case .numberArabicAndKanjiFullwidth: return "NUMBER_ARABIC_AND_KANJI_FULLWIDTH"
  case .numberKanji: return "NUMBER_KANJI"
  case .numberOldKanji: return "NUMBER_OLD_KANJI"
  case .numberRomanCapital: return "NUMBER_ROMAN_CAPITAL"
  case .numberRomanSmall: return "NUMBER_ROMAN_SMALL"
  case .numberCircled: return "NUMBER_CIRCLED"
  case .numberKanjiArabic: return "NUMBER_KANJI_ARABIC"
  case .numberHex: return "NUMBER_HEX"
  case .numberOct: return "NUMBER_OCT"
  case .numberBin: return "NUMBER_BIN"
  case .numberSuperscript: return "NUMBER_SUPERSCRIPT"
  case .numberSubscript: return "NUMBER_SUBSCRIPT"
  @unknown default: return "UNKNOWN"
  }
}

private func innerSegmentBoundaryToString(_ cand: Candidate) -> String {
  var pieces: [String] = []
  for iter in cand.innerSegments() {
    pieces.append(
      "<\(iter.getKey()), \(iter.getValue()), \(iter.getContentKey()), \(iter.getContentValue())>")
  }
  return pieces.joined(separator: " | ")
}

private func printCandidate(
  _ printer: PosIdPrinter, _ parent: Segment, _ candidatesSize: Int, _ num: Int, _ cand: Candidate,
  _ os: inout String
) {
  var lines: [String] = []
  if !parent.key.bytesEqual(cand.key) {
    lines.append("key: " + cand.key)
  }
  lines.append("content_vk: " + cand.contentValue + "  " + cand.contentKey)
  lines.append("cost: \(cand.cost)  scost: \(cand.structureCost)  wcost: \(cand.wcost)")
  lines.append("lid: " + idToString(printer, Int(cand.lid)))
  lines.append("rid: " + idToString(printer, Int(cand.rid)))
  lines.append("attr: " + candidateAttributesToString(cand.attributes))
  lines.append("num_style: " + numberStyleToString(cand.style))
  let segbddStr = innerSegmentBoundaryToString(cand)
  if !segbddStr.isEmpty {
    lines.append("segbdd: " + segbddStr)
  }
  #if DEBUG
    if !cand.log.isEmpty {
      lines.append("log:")
      for line in cand.log.split(separator: "\n", omittingEmptySubsequences: true) {
        lines.append("    " + line)
      }
    }
  #endif

  os += "  \(num)/\(candidatesSize) \(cand.value)\n"
  for line in lines where !line.isEmpty {
    os += "       \(line)\n"
  }
}

private func printSegment(
  _ options: ConverterMain.Options, _ printer: PosIdPrinter, _ num: Int, _ segmentsSize: Int,
  _ segment: Segment, _ os: inout String
) {
  os += "---------- Segment \(num)/\(segmentsSize) [\(segmentTypeToString(segment.segmentType))]"
  os += " ----------\n\(segment.key)\n"
  if options.showMetaCandidates {
    for i in 0..<segment.metaCandidatesSize {
      printCandidate(printer, segment, segment.metaCandidatesSize, -i - 1, segment.metaCandidate(i), &os)
    }
  }
  let n = min(segment.candidatesSize, options.maxCandidatesToShow)
  for i in 0..<n {
    printCandidate(printer, segment, segment.candidatesSize, i, segment.candidate(i), &os)
  }
}

private func printSegments(
  _ options: ConverterMain.Options, _ printer: PosIdPrinter, _ segments: Segments, _ os: inout String
) {
  for i in 0..<segments.segmentsSize {
    printSegment(options, printer, i, segments.segmentsSize, segments.segment(i), &os)
  }
}

// MARK: - ConverterMain

public final class ConverterMain {
  /// The absl flags used by ConverterMain and the printing functions.
  public struct Options: Sendable {
    /// --max_conversion_candidates_size
    public var maxConversionCandidatesSize: Int32 = 200
    /// --max_candidates_to_show
    public var maxCandidatesToShow = 100
    /// --show_meta_candidates
    public var showMetaCandidates = false
    /// --id_def (POS names; ids are printed as numbers when it cannot be read)
    public var idDef = ""

    public init() {}
  }

  private let options: Options
  private let printer: PosIdPrinter
  private let engine: Engine
  private let request: Genmai_Commands_Request
  private var config: Genmai_Config_Config
  private let converter: any ConverterInterface
  private let segments = Segments()
  private var composer: Composer

  public init(
    _ engine: Engine, _ request: Genmai_Commands_Request, _ config: Genmai_Config_Config,
    _ options: Options
  ) {
    self.options = options
    printer = PosIdPrinter(InputFileStream(options.idDef))
    self.engine = engine
    self.request = request
    self.config = config
    converter = engine.getConverter()
    composer = Composer(request, config)
  }

  // Empty for the OSS edition.
  private static let kSupplementalModelDefaultPath = ""

  // When supplemental model is not enabled, the Load function is a no-op and
  // returns ACCEPTED that is 0 as the default value of the enum.
  private static let kSupplementalModelExpectedStatus = Genmai_EngineReloadResponse.Status.accepted

  public func loadSupplementalModel(_ pathIn: String) {
    var path = pathIn
    if path.isEmpty {
      // Default spelling model
      path = FileUtil.joinPath(
        SystemUtil.getProgramRunfilesDirectory(), ConverterMain.kSupplementalModelDefaultPath)
    }
    var req = Genmai_EngineReloadRequest()
    req.filePath = path
    let response = engine.getModulesForTesting().getSupplementalModelInterface().load(req)
    precondition(
      response.status == ConverterMain.kSupplementalModelExpectedStatus,
      "Check failed: response.status() == kSupplementalModelExpectedStatus")
    GenmaiLog.info("Set the supplemental model: path = \(path)")
  }

  private func buildRequest(_ conversionOptions: ConversionOptions) -> ConversionRequest {
    ConversionRequestBuilder()
      .setComposer(composer)
      .setRequestView(request)
      .setConfigView(config)
      .setOptions(conversionOptions)
      .build()
  }

  @discardableResult
  private func execCommand(_ line: String) -> Bool {
    let fields = line.split(
      omittingEmptySubsequences: true, whereSeparator: { $0 == "\t" || $0 == " " }
    ).map(String.init)

    if fields.count < 1 { return false }

    var options = ConversionOptions()
    options.maxConversionCandidatesSize = Int(self.options.maxConversionCandidatesSize)
    options.useActualConverterForRealtimeConversion = true
    options.createPartialCandidates = request.autoPartialSuggestion

    let atoi = { (s: String) in NumberUtil.simpleAtoi(s) }

    let function = fields[0]
    switch function {
    case "startconversion", "start", "s":
      options.requestType = .conversion
      options.createPartialCandidates = false
      if fields.count < 2 { return false }
      composer.reset()
      composer.setPreeditTextForTestOnly(fields[1])
      return converter.startConversion(buildRequest(options), segments)
    case "reverseconversion", "reverse", "r":
      if fields.count < 2 { return false }
      return converter.startReverseConversion(segments, fields[1])
    case "startprediction", "predict", "p":
      options.requestType = .prediction
      if fields.count >= 2 {
        composer.reset()
        composer.setPreeditTextForTestOnly(fields[1])
      }
      return converter.startPrediction(buildRequest(options), segments)
    case "startsuggestion", "suggest":
      options.requestType = .suggestion
      if fields.count >= 2 {
        composer.reset()
        composer.setPreeditTextForTestOnly(fields[1])
      }
      return converter.startPrediction(buildRequest(options), segments)
    case "finishconversion", "finish":
      options.requestType = .conversion
      converter.finishConversion(buildRequest(options), segments)
      composer.reset()
      return true
    case "resetconversion", "reset":
      converter.resetConversion(segments)
      composer.reset()
      return true
    case "cancelconversion", "cancel":
      converter.cancelConversion(segments)
      composer.reset()
      return true
    case "commitsegmentvalue", "commit", "c":
      if fields.count < 3 { return false }
      return converter.commitSegmentValue(segments, atoi(fields[1]), atoi(fields[2]))
    case "commitallandfinish":
      for i in 0..<segments.conversionSegmentsSize {
        if segments.conversionSegment(i).segmentType != .fixedValue {
          if !converter.commitSegmentValue(segments, i, 0) { return false }
        }
      }
      options.requestType = .conversion
      converter.finishConversion(buildRequest(options), segments)
      composer.reset()
      return true
    case "focussegmentvalue", "focus":
      if fields.count < 3 { return false }
      return converter.focusSegmentValue(segments, atoi(fields[1]), atoi(fields[2]))
    case "commitfirstsegment":
      if fields.count < 2 { return false }
      return converter.commitSegments(segments, [atoi(fields[1])])
    case "resizesegment", "resize":
      options.requestType = .conversion
      let conversionRequest = buildRequest(options)
      if fields.count == 3 {
        return converter.resizeSegment(
          segments, conversionRequest, atoi(fields[1]), atoi(fields[2]))
      }
    case "resizesegments", "resizes":
      options.requestType = .conversion
      let conversionRequest = buildRequest(options)
      if fields.count > 3 {
        var newArrays: [UInt8] = []
        for i in 2..<fields.count {
          newArrays.append(UInt8(truncatingIfNeeded: atoi(fields[i])))
        }
        return converter.resizeSegments(segments, conversionRequest, atoi(fields[1]), newArrays)
      }
    case "disableuserhistory":
      config.historyLearningLevel = .noHistory
    case "enableuserhistory":
      config.historyLearningLevel = .defaultHistory
    case "zeroquerysuggest", "z":
      if fields.count < 3 { return false }  // command history_key history_value
      if !execCommand("reset") {
        GenmaiLog.error("Reset failed")
        return false
      }
      if !execCommand("predict \(fields[1])") {
        GenmaiLog.error("Predict failed for context key \(fields[1])")
        return false
      }
      let index = findCandidate(segments.conversionSegment(0), fields[2])
      if index == -1 {
        GenmaiLog.error("Cannot find candidate \(fields[2])")
        return false
      }
      if !execCommand("commit 0 \(index)") {
        GenmaiLog.error("commit failed")
        return false
      }
      if !execCommand("finish") {
        GenmaiLog.error("finish failed")
        return false
      }
      if !execCommand("predict") {
        GenmaiLog.error("predict from zero query failed")
        return false
      }
      return true
    default:
      GenmaiLog.warning("Unknown command: \(function)")
      return false
    }
    return true
  }

  public func execCommandToString(_ line: String) -> String {
    var oss = ""
    if execCommand(line) {
      printSegments(options, printer, segments, &oss)
    } else {
      oss += "ExecCommand() return false"
    }
    return oss
  }

  public func runLoop() {
    // std::getline: only '\n' is stripped.
    while let raw = readLine(strippingNewline: false) {
      var line = raw
      if line.utf8.last == UInt8(ascii: "\n") {
        line = String(decoding: line.utf8.dropLast(), as: UTF8.self)
      }
      let result = execCommandToString(line)
      print(result)
    }
  }
}

