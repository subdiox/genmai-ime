// Port of mozc/src/request/conversion_request.h (3.35.6354).
//
// Deviations from C++:
// - `internal::copy_or_view_ptr<T>` (a lifetime optimization holding either a
//   view or a copy) has no Swift equivalent: every member is stored as a value
//   (protobuf messages and ComposerData are copy-on-write). The *View setters
//   are kept for API parity and behave like the copying ones, except that
//   `setConfigView` does not trim the config (as in C++).
// - `prediction::Result` belongs to GenmaiCore/Prediction, which is ported
//   separately. ConversionRequest only needs the history key/value suffix,
//   rid and cost, so the history result is abstracted by the
//   `ConversionRequestHistoryResult` protocol defined below. Prediction's
//   Result should conform to it (and callers that need the concrete type
//   downcast `historyResult`).
// - The builder is a value type whose setters return the updated builder.

import GenmaiBase
import GenmaiProtocol

/// The subset of prediction::Result used by ConversionRequest (left context
/// history). prediction::Result is expected to conform to this protocol.
public protocol ConversionRequestHistoryResult: Sendable {
  /// `inner_segments().GetSuffixKeyAndValue(size)`: the last `size` history
  /// key/value (all when size = -1).
  func historySuffixKeyAndValue(_ size: Int) -> (key: String, value: String)
  /// `inner_segments().size()`.
  var historyInnerSegmentsSize: Int { get }
  /// The right context id of the history (`Result::rid`).
  var historyRid: Int { get }
  /// The cost of the history (`Result::cost`).
  var historyCost: Int { get }
}

/// Stand-in for `prediction::Result::DefaultResult()` (empty key/value,
/// rid = cost = 0, no inner segments).
public struct EmptyConversionRequestHistoryResult: ConversionRequestHistoryResult {
  public init() {}
  public func historySuffixKeyAndValue(_ size: Int) -> (key: String, value: String) { ("", "") }
  public var historyInnerSegmentsSize: Int { 0 }
  public var historyRid: Int { 0 }
  public var historyCost: Int { 0 }
}

/// absl::StripAsciiWhitespace.
private func stripAsciiWhitespace(_ s: String) -> String {
  func isSpace(_ b: UInt8) -> Bool {
    b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0B || b == 0x0C || b == 0x0D
  }
  let bytes = Array(s.utf8)
  var begin = 0
  var end = bytes.count
  while begin < end && isSpace(bytes[begin]) { begin += 1 }
  while end > begin && isSpace(bytes[end - 1]) { end -= 1 }
  return String(decoding: bytes[begin..<end], as: UTF8.self)
}

/// Contains utilizable information for conversion, suggestion and prediction,
/// including composition, preceding text, etc.
/// TODO(team, yukawa): Refactor this class so it can represents that more
/// detailed context information such as commands::Context.
public struct ConversionRequest: Sendable {
  public typealias Options = ConversionOptions

  // Required options
  // Input composer to generate a key for conversion, suggestion, etc.
  fileprivate var composerData: ComposerData

  // Input request.
  fileprivate var requestValue: Genmai_Commands_Request

  // Input context.
  fileprivate var contextValue: Genmai_Commands_Context

  // Input config.
  fileprivate var configValue: Genmai_Config_Config

  // Left context history.
  fileprivate var historyResultValue: any ConversionRequestHistoryResult

  // Options for conversion request.
  fileprivate var optionsValue: Options

  // Key used for conversion.
  // This is typically a Hiragana text to be converted to Kanji words.
  fileprivate var keyValue = ""

  /// Default constructor: all members are the global defaults.
  public init() {
    composerData = Composer.emptyComposerData()
    requestValue = Genmai_Commands_Request()
    contextValue = Genmai_Commands_Context()
    configValue = ConfigHandler.defaultConfig()
    historyResultValue = EmptyConversionRequestHistoryResult()
    optionsValue = Options()
  }

  public func requestType() -> RequestType { optionsValue.requestType }

  public func composer() -> ComposerData { composerData }

  public func request() -> Genmai_Commands_Request { requestValue }

  public func context() -> Genmai_Commands_Context { contextValue }

  public func config() -> Genmai_Config_Config { configValue }

  /// Returns options by value. Cheap to copy and avoids reference lifetime
  /// issues.
  public func options() -> Options { optionsValue }

  public func historyResult() -> any ConversionRequestHistoryResult { historyResultValue }

  public func isKanaModifierInsensitiveConversion() -> Bool {
    requestValue.kanaModifierInsensitiveConversion
      && configValue.useKanaModifierInsensitiveConversion
      && optionsValue.kanaModifierInsensitiveConversion
  }

  public func isZeroQuerySuggestion() -> Bool { keyValue.isEmpty }

  /// Clients needs to check ConversionRequest::incognito_mode() instead
  /// of Config::incognito_mode() or Request::is_incognito_mode(), as the
  /// incognito mode can also set via Options.
  public func incognitoMode() -> Bool {
    optionsValue.incognitoMode || configValue.incognitoMode || requestValue.isIncognitoMode
  }

  public func key() -> String { keyValue }

  /// Takes the last `size` history key. return all value when size = -1.
  public func converterHistoryKey(_ size: Int = -1) -> String {
    historyResultValue.historySuffixKeyAndValue(size).key
  }

  /// Takes the last `size` history value. return all value when size = -1.
  public func converterHistoryValue(_ size: Int = -1) -> String {
    historyResultValue.historySuffixKeyAndValue(size).value
  }

  public func converterHistorySize() -> Int {
    historyResultValue.historyInnerSegmentsSize
  }

  /// Returns the right context id of the history.
  public func converterHistoryRid() -> Int { historyResultValue.historyRid }

  /// Returns the cost of the history if defined.
  public func converterHistoryCost() -> Int { historyResultValue.historyCost }

  /// Returns normalized preceding and following surrounding context text.
  /// First: preceding context (left)
  /// Second: following context (right)
  public func getSurroundingContext() -> (String, String) {
    var leftBytes = Array(contextValue.precedingText.utf8)
    if let lpos = leftBytes.lastIndex(where: { $0 == 0x0D || $0 == 0x0A }) {
      leftBytes.removeFirst(lpos + 1)
    }
    var rightBytes = Array(contextValue.followingText.utf8)
    if let rpos = rightBytes.firstIndex(where: { $0 == 0x0D || $0 == 0x0A }) {
      rightBytes.removeLast(rightBytes.count - rpos)
    }
    let leftContext = Japanese.fullWidthAsciiToHalfWidthAscii(
      String(decoding: leftBytes, as: UTF8.self))
    let rightContext = Japanese.fullWidthAsciiToHalfWidthAscii(
      String(decoding: rightBytes, as: UTF8.self))
    return (stripAsciiWhitespace(leftContext), stripAsciiWhitespace(rightContext))
  }
}

public struct ConversionRequestBuilder: Sendable {
  // The stage of the builder.
  // 0: No data set
  // 1: ConversionRequest set.
  // 2: ComposerData, Request, Context, Config, Options set.
  // 3: RequestType, Key, as values of Options set.
  // 100: Build() called.
  private var stage = 0
  private var request = ConversionRequest()

  public init() {}

  public func build() -> ConversionRequest {
    // If the key is specified, use it. Otherwise, generate it.
    // NOTE: Specifying Composer is preferred over specifying key directly.
    assert(stage <= 3)
    var request = self.request
    if request.keyValue.isEmpty {
      request.keyValue = Self.getKey(
        request.composerData, request.optionsValue.requestType,
        request.optionsValue.composerKeySelection)
    }
    // Populate decoupled ConversionOptions fields from commands::Request and
    // config::Config.
    request.optionsValue.incognitoMode = request.incognitoMode()
    request.optionsValue.kanaModifierInsensitiveConversion =
      request.isKanaModifierInsensitiveConversion()
    request.optionsValue.useSpellingCorrection = request.configValue.useSpellingCorrection
    request.optionsValue.useZipCodeConversion = request.configValue.useZipCodeConversion
    request.optionsValue.useT13nConversion = request.configValue.useT13NConversion
    if request.configValue.preeditMethod == .roman {
      request.optionsValue.inputMode = .roman
    } else {
      request.optionsValue.inputMode = .kana
    }
    request.optionsValue.particleOmissionTransitionCostBonus = Int(
      request.requestValue.decoderExperimentParams.particleOmissionTransitionCostBonus)
    if request.requestValue.decoderExperimentParams.suppressRealtimeConversionWithConverter {
      request.optionsValue.useActualConverterForRealtimeConversion = false
    }
    return request
  }

  public func setConversionRequest(_ baseConvreq: ConversionRequest) -> Self {
    assert(stage <= 1)
    var b = self
    b.stage = 1
    b.request = baseConvreq
    return b
  }

  public func setConversionRequestView(_ baseConvreq: ConversionRequest) -> Self {
    setConversionRequest(baseConvreq)
  }

  public func setComposerData(_ composerData: ComposerData) -> Self {
    assert(stage <= 2)
    var b = self
    b.stage = 2
    b.request.composerData = composerData
    return b
  }

  public func setComposer(_ composer: Composer) -> Self {
    assert(stage <= 2)
    var b = self
    b.stage = 2
    b.request.composerData = composer.createComposerData()
    return b
  }

  public func setRequest(_ request: Genmai_Commands_Request) -> Self {
    assert(stage <= 2)
    var b = self
    b.stage = 2
    b.request.requestValue = request
    return b
  }

  public func setRequestView(_ request: Genmai_Commands_Request) -> Self {
    setRequest(request)
  }

  public func setContext(_ context: Genmai_Commands_Context) -> Self {
    assert(stage <= 2)
    var b = self
    b.stage = 2
    b.request.contextValue = context
    return b
  }

  public func setContextView(_ context: Genmai_Commands_Context) -> Self {
    setContext(context)
  }

  public func setConfig(_ config: Genmai_Config_Config) -> Self {
    assert(stage <= 2)
    var b = self
    b.stage = 2
    b.request.configValue = Self.trimConfig(config)
    return b
  }

  public func setConfigView(_ config: Genmai_Config_Config) -> Self {
    assert(stage <= 2)
    var b = self
    b.stage = 2
    b.request.configValue = config
    return b
  }

  public func setHistoryResult(_ historyResult: any ConversionRequestHistoryResult) -> Self {
    assert(stage <= 2)
    var b = self
    b.stage = 2
    b.request.historyResultValue = historyResult
    return b
  }

  public func setHistoryResultView(_ historyResult: any ConversionRequestHistoryResult) -> Self {
    setHistoryResult(historyResult)
  }

  public func setEmptyHistoryResult() -> Self {
    setHistoryResultView(EmptyConversionRequestHistoryResult())
  }

  public func setOptions(_ options: ConversionRequest.Options) -> Self {
    assert(stage <= 2)
    var b = self
    b.stage = 2
    b.request.optionsValue = options
    return b
  }

  public func setRequestType(_ requestType: RequestType) -> Self {
    assert(stage <= 3)
    var b = self
    b.stage = 3
    b.request.optionsValue.requestType = requestType
    return b
  }

  /// We cannot set empty key (SetKey("")). When key is empty,
  /// key is created from composer.
  public func setKey(_ key: some StringProtocol) -> Self {
    assert(stage <= 3)
    var b = self
    b.stage = 3
    b.request.keyValue = String(key)
    return b
  }

  // Remove unnecessary but potentially large options for ConversionRequest
  // from Config and return it.
  // TODO(b/365909808): Move this method to Session after updating the
  // ConversionRequest constructor.
  private static func trimConfig(_ baseConfig: Genmai_Config_Config) -> Genmai_Config_Config {
    var config = baseConfig
    config.clearCustomKeymapTable()
    config.clearCustomRomanTable()
    return config
  }

  private static func getKey(
    _ composerData: ComposerData, _ type: RequestType, _ selection: ComposerKeySelection
  ) -> String {
    if type == .conversion && selection == .conversionKey {
      return composerData.getQueryForConversion()
    }

    if (type == .conversion && selection == .predictionKey) || type == .prediction
      || type == .suggestion
    {
      return composerData.getQueryForPrediction()
    }

    if type == .partialPrediction || type == .partialSuggestion {
      let predictionKey = composerData.getQueryForConversion()
      return String(Util.utf8SubString(predictionKey, 0, composerData.getCursor()))
    }
    return ""
  }
}
