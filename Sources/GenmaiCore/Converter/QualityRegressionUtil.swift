// Port of mozc/src/converter/quality_regression_util.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - absl::Status / StatusOr are Swift `throws` (StatusError).
// - RE2::FullMatch is NSRegularExpression anchored to the whole string (ICU
//   syntax; the patterns used by the regression data are compatible).

import Foundation
import GenmaiBase
import GenmaiProtocol

private let kConversionExpect = "Conversion Expected"
private let kConversionNotExpect = "Conversion Not Expected"
private let kConversionMatch = "Conversion Match"
private let kConversionNotMatch = "Conversion Not Match"
private let kReverseConversionExpect = "ReverseConversion Expected"
private let kReverseConversionNotExpect = "ReverseConversion Not Expected"
// For now, suggestion and prediction are using same implementation
private let kPredictionExpect = "Prediction Expected"
private let kPredictionNotExpect = "Prediction Not Expected"
private let kSuggestionExpect = "Suggestion Expected"
private let kSuggestionNotExpect = "Suggestion Not Expected"
// Zero query
private let kZeroQueryExpect = "ZeroQuery Expected"
private let kZeroQueryNotExpect = "ZeroQuery Not Expected"

private func getRank(_ value: Substring, _ segments: Segments, _ currentSegment: Int) -> Int {
  if currentSegment >= segments.segmentsSize {
    return value.isEmpty ? 0 : -1
  }
  let seg = segments.segment(currentSegment)
  var rank = 0
  var dedup = Set<[UInt8]>()
  for cand in seg.candidates {
    let candValue = cand.value
    let newValue = dedup.insert(Array(candValue.utf8)).inserted
    if !newValue {
      // The value is duplicated and already checked.
      // The duplicated values are trimmed after the conversion process
      // anyway.
      continue
    }

    if !value.hasBytePrefix(candValue) {
      rank += 1
      continue
    }
    let nextSegment = currentSegment + Int(cand.effectiveConvertedSegmentCount)
    let rest = getRank(value.byteSubstring(from: candValue.utf8.count), segments, nextSegment)
    if rest == -1 {
      rank += 1
      continue
    }
    return rank + rest
  }
  return -1
}

private func getPlatformFromString(_ str: some StringProtocol) throws -> UInt32 {
  var lower = String(str)
  Util.lowerString(&lower)
  switch lower {
  case "desktop": return QualityRegressionUtil.Platform.desktop
  case "oss": return QualityRegressionUtil.Platform.oss
  case "mobile": return QualityRegressionUtil.Platform.mobile
  case "preload": return QualityRegressionUtil.Platform.preload
  case "all": return QualityRegressionUtil.Platform.all
  default:
    throw StatusError.invalidArgument("Unknown platform name: \(str)")
  }
}

/// `absl::StrSplit(s, c, absl::SkipEmpty())`.
private func splitSkipEmpty(_ s: some StringProtocol, _ c: Character) -> [Substring] {
  Substring(s).split(separator: c, omittingEmptySubsequences: true)
}

public final class QualityRegressionUtil {
  /// bit fields
  public enum Platform {
    public static let desktop: UInt32 = 1 << 0
    public static let oss: UInt32 = 1 << 1
    public static let mobile: UInt32 = 1 << 2
    public static let preload: UInt32 = 1 << 3
    public static let all: UInt32 = desktop | oss | mobile | preload
  }

  public struct TestItem: Sendable {
    public var label = ""
    public var key = ""
    public var expectedValue = ""
    public var command = ""
    public var accuracy: Double = 0
    public var expectedRank = 0
    /// Target platform. Can set multiple platform defined in `Platform`.
    public var platform: UInt32 = 0

    public init() {}

    public func outputAsTSV() -> String {
      // std::ostream formats a double with 6 significant digits (%g).
      "\(label)\t\(key)\t\(expectedValue)\t\(command)\t\(expectedRank)\t"
        + "\(String(format: "%g", accuracy))\t\(platform)"
      // TODO(toshiyuki): platform enum to string
    }

    public mutating func parseFromTSV(_ line: some StringProtocol) throws {
      let tokens = splitSkipEmpty(line, "\t")
      if tokens.count < 4 {
        throw StatusError.invalidArgument("Invalid token size: \(line)")
      }
      label = String(tokens[0])
      key = String(tokens[1])
      expectedValue = TextNormalizer.normalizeText(tokens[2])
      command = String(tokens[3])

      if tokens.count == 4 {
        if command.hasBytePrefix(kConversionExpect) && !command.bytesEqual(kConversionExpect) {
          let kSize = kConversionExpect.utf8.count  // std::size(string_view)
          expectedRank = NumberUtil.simpleAtoi(command.byteSubstring(from: kSize))
          command = kConversionExpect
        } else {
          expectedRank = 0
        }
      } else {
        expectedRank = NumberUtil.simpleAtoi(tokens[4])
      }

      if tokens.count > 5 {
        if let d = NumberUtil.safeStrToDouble(tokens[5]) {
          accuracy = d
        }
      } else {
        accuracy = 1.0
      }
      platform = 0
      if tokens.count >= 7 {
        let platforms = splitSkipEmpty(tokens[6], ",")
        for p in platforms {
          platform |= try getPlatformFromString(p)
        }
      } else {
        // Default platform: desktop
        platform = Platform.desktop
      }
    }
  }

  private let converter: any ConverterInterface
  private var request = Genmai_Commands_Request()
  private var config = Genmai_Config_Config()

  public init(_ converter: any ConverterInterface) {
    self.converter = converter
  }

  private static func parseFileInternal(_ filename: String, _ outputs: inout [TestItem]) throws {
    // TODO(taku): support an XML file of Genmaisu.
    guard let data = FileManager.default.contents(atPath: filename) else {
      throw StatusError(.unavailable, "Failed to read: \(filename)")
    }
    let text = String(decoding: data, as: UTF8.self)
    // std::getline: the last line may lack a newline.
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    if text.hasSuffix("\n") { lines.removeLast() }
    for line in lines {
      if line.isEmpty || line.utf8.first == UInt8(ascii: "#") {
        continue
      }
      var item = TestItem()
      do {
        try item.parseFromTSV(line)
      } catch {
        throw StatusError.invalidArgument("Failed to parse: \(line)")
      }
      outputs.append(item)
    }
  }

  /// Pase |filename| and save the all test items into |outputs|.
  public static func parseFile(_ filename: String, _ outputs: inout [TestItem]) throws {
    outputs.removeAll()
    try parseFileInternal(filename, &outputs)
  }

  public static func parseFiles(_ filenames: [String], _ outputs: inout [TestItem]) throws {
    outputs.removeAll()
    for filename in filenames {
      try parseFileInternal(filename, &outputs)
    }
  }

  public func convertAndTest(_ item: TestItem, _ actualValue: inout String) throws -> Bool {
    let key = item.key
    let expectedValue = item.expectedValue
    let command = item.command
    let expectedRank = item.expectedRank

    let segments = Segments()
    converter.resetConversion(segments)
    actualValue = ""

    let table = Table()
    config.useTypingCorrection = true

    func makeComposer(_ request: Genmai_Commands_Request, preedit: Bool = true) -> Composer {
      var composer = Composer(table, request, config)
      if preedit {
        composer.setPreeditTextForTestOnly(key)
      }
      return composer
    }

    if command == kConversionExpect || command == kConversionNotExpect
      || command == kConversionMatch || command == kConversionNotMatch
    {
      let convReq = ConversionRequestBuilder()
        .setComposer(makeComposer(request))
        .setRequestView(request)
        .setConfigView(config)
        .build()
      if !converter.startConversion(convReq, segments) {
        throw StatusError.unknown("StartConversionForRequest failed: \(item.outputAsTSV())")
      }
    } else if command == kReverseConversionExpect || command == kReverseConversionNotExpect {
      if !converter.startReverseConversion(segments, key) {
        throw StatusError.unknown("StartReverseConversion failed")
      }
    } else if command == kPredictionExpect || command == kPredictionNotExpect {
      var options = ConversionOptions()
      options.requestType = .prediction
      options.useActualConverterForRealtimeConversion = true
      if request.mixedConversion {
        options.createPartialCandidates = true
      }
      let convReq = ConversionRequestBuilder()
        .setComposer(makeComposer(request))
        .setRequestView(request)
        .setConfigView(config)
        .setOptions(options)
        .build()
      if !converter.startPrediction(convReq, segments) {
        throw StatusError.unknown("StartPredictionForRequest failed: \(item.outputAsTSV())")
      }
    } else if command == kSuggestionExpect || command == kSuggestionNotExpect {
      var options = ConversionOptions()
      options.requestType = .suggestion
      options.useActualConverterForRealtimeConversion = true
      let convReq = ConversionRequestBuilder()
        .setComposer(makeComposer(request))
        .setRequestView(request)
        .setConfigView(config)
        .setOptions(options)
        .build()
      if !converter.startPrediction(convReq, segments) {
        throw StatusError.unknown(
          "StartPrediction for suggestion failed: \(item.outputAsTSV())")
      }
    } else if command == kZeroQueryExpect || command == kZeroQueryNotExpect {
      var request = self.request
      request.zeroQuerySuggestion = true
      request.mixedConversion = true
      do {
        var options = ConversionOptions()
        options.requestType = .suggestion
        options.maxConversionCandidatesSize = 10
        let convReq = ConversionRequestBuilder()
          .setComposer(makeComposer(request))
          .setRequestView(request)
          .setConfigView(config)
          .setOptions(options)
          .build()
        if !converter.startPrediction(convReq, segments) {
          throw StatusError.unknown(
            "StartSuggestion for suggestion failed: \(item.outputAsTSV())")
        }
        if !converter.commitSegmentValue(segments, 0, 0) {
          throw StatusError.unknown("CommitSegmentValue failed: \(item.outputAsTSV())")
        }
        converter.finishConversion(convReq, segments)
      }
      do {
        // Issues zero-query request.
        var options = ConversionOptions()
        options.requestType = .prediction
        options.maxConversionCandidatesSize = 10
        let convReq = ConversionRequestBuilder()
          .setComposer(makeComposer(request, preedit: false))
          .setRequestView(request)
          .setConfigView(config)
          .setOptions(options)
          .build()
        if !converter.startPrediction(convReq, segments) {
          throw StatusError.unknown("StartPredictionForRequest failed: \(item.outputAsTSV())")
        }
        segments.clearHistorySegments()
      }
    } else {
      throw StatusError.invalidArgument("Unknown command: \(item.outputAsTSV())")
    }

    // No results is OK if "prediction not expect" command
    if (command == kPredictionNotExpect || command == kSuggestionNotExpect)
      && (segments.segmentsSize == 0
        || (segments.segmentsSize >= 1 && segments.segment(0).candidatesSize == 0))
    {
      return true
    }

    var i = 0
    while i < segments.segmentsSize {
      let segment = segments.segment(i)
      actualValue += segment.candidate(0).value
      i += Int(segment.candidate(0).effectiveConvertedSegmentCount)
    }

    if command == kConversionMatch || command == kConversionNotMatch {
      let regex: NSRegularExpression
      do {
        regex = try NSRegularExpression(pattern: "\\A(?:\(expectedValue))\\z")
      } catch {
        throw StatusError.invalidArgument("Invalid regex: \(expectedValue)")
      }
      let range = NSRange(actualValue.startIndex..<actualValue.endIndex, in: actualValue)
      let matched = regex.firstMatch(in: actualValue, options: [.anchored], range: range) != nil
      return (command == kConversionMatch) ? matched : !matched
    }

    let actualRank = getRank(Substring(expectedValue), segments, 0)

    var result = actualRank >= 0 && actualRank <= expectedRank

    if command == kConversionNotExpect || command == kReverseConversionNotExpect
      || command == kPredictionNotExpect || command == kSuggestionNotExpect
      || command == kZeroQueryNotExpect
    {
      result = !result
    }

    return result
  }

  public func setRequest(_ request: Genmai_Commands_Request) {
    self.request = request
  }

  public func setConfig(_ config: Genmai_Config_Config) {
    self.config = config
  }

  public static func getPlatformString(_ platformBitfiled: UInt32) -> String {
    var v: [String] = []
    if platformBitfiled & Platform.desktop != 0 {
      v.append("DESKTOP")
    }
    if platformBitfiled & Platform.oss != 0 {
      v.append("OSS")
    }
    if platformBitfiled & Platform.mobile != 0 {
      v.append("MOBILE")
    }
    if platformBitfiled & Platform.preload != 0 {
      v.append("PRELOAD")
    }
    if v.isEmpty {
      v.append("UNKNOWN")
    }
    return v.joined(separator: "|")
  }
}
