// Port of mozc/src/prediction/realtime_decoder.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `open class` with `open` methods (virtual in C++) for test doubles.
// - Conforms to UserHistoryRealtimeDecoder (the subset used by
//   UserHistoryPredictor).
// - The suffix cache is keyed by (prefix_rid, suffix bytes) instead of
//   `absl::HashOf(prefix_rid, suffix)`, so hash collisions cannot return a
//   wrong entry. The cached values are deterministic, so the eviction policy
//   does not change the output.

import GenmaiBase

open class RealtimeDecoder: @unchecked Sendable {
  private static let kSuffixCacheSize = 256

  private struct SuffixCacheKey: Hashable {
    let prefixRid: UInt16
    let suffix: [UInt8]
  }

  private let immutableConverterStorage: (any ImmutableConverterInterface)?
  private let converterStorage: (any ConverterInterface)?

  // Cache for DecodeSuffix.
  private let suffixCache = FlatConcurrentCache<SuffixCacheKey, PredictionResult>(
    RealtimeDecoder.kSuffixCacheSize)

  public init() {
    immutableConverterStorage = nil
    converterStorage = nil
  }

  public init(
    _ immutableConverter: any ImmutableConverterInterface, _ converter: any ConverterInterface
  ) {
    immutableConverterStorage = immutableConverter
    converterStorage = converter
  }

  private var immutableConverter: any ImmutableConverterInterface {
    guard let immutableConverterStorage else {
      fatalError("RealtimeDecoder: immutable converter is not set")
    }
    return immutableConverterStorage
  }

  private var converter: any ConverterInterface {
    guard let converterStorage else {
      fatalError("RealtimeDecoder: converter is not set")
    }
    return converterStorage
  }

  private func pushBackTopConversionResult(
    _ request: ConversionRequest, _ results: inout [PredictionResult]
  ) -> Bool {
    var options = ConversionOptions()
    options.maxConversionCandidatesSize = 20
    options.composerKeySelection = .predictionKey
    // Some rewriters cause significant performance loss. So we skip them.
    options.skipSlowRewriters = true
    // This method emulates usual converter's behavior so here disable
    // partial candidates.
    options.createPartialCandidates = false
    options.usedInPredictorRealtimeConversion = true
    options.requestType = .conversion
    let tmpRequest = ConversionRequestBuilder()
      .setConversionRequestView(request)
      .setOptions(options)
      .build()

    let tmpSegments = ConverterUtil.prepareSegmentsFromRequest(request)

    assert(tmpSegments.conversionSegmentsSize == 1)

    if !converter.startConversion(tmpRequest, tmpSegments) {
      return false
    }

    guard var result = ConverterUtil.conversionSegmentsToResult(tmpSegments.conversionSegments)
    else {
      return false
    }

    result.setTypesAndTokenAttributes(
      Attribute.realtimeConversion | Attribute.realtimeTop, Token.Attribute.none)
    result.attributes |= Attribute.noVariantsExpansion

    results.append(result)

    return true
  }

  /// Decodes `request`. The request type must not be CONVERSION because
  /// we assume that Decode doesn't return multiple-segments.
  open func decode(_ request: ConversionRequest) -> [PredictionResult] {
    var results: [PredictionResult] = []
    if request.options().maxConversionCandidatesSize == 0 {
      return results
    }

    // Accepts only single-segment request.
    assert(request.requestType() != .conversion)
    if request.requestType() == .conversion {
      return results
    }

    let requestForRealtime = ConversionRequestBuilder().setConversionRequestView(request).build()

    let tmpSegments = ConverterUtil.prepareSegmentsFromRequest(request)
    assert(tmpSegments.conversionSegmentsSize == 1)

    // First insert a top conversion result.
    // Note: Do not call actual converter for partial suggestion /
    // prediction. Converter::StartConversion() resets conversion key from
    // composer rather than using the key in segments.
    if request.options().useActualConverterForRealtimeConversion
      && request.requestType() != .partialSuggestion
      && request.requestType() != .partialPrediction
    {
      if !pushBackTopConversionResult(requestForRealtime, &results) {
        GenmaiLog.warning("Realtime conversion with converter failed")
      }
    }

    // non-CONVERSION request returns concatenated single segment.
    if !immutableConverter.convert(requestForRealtime.options(), tmpSegments)
      || tmpSegments.conversionSegmentsSize != 1
      || tmpSegments.conversionSegment(0).candidatesSize == 0
    {
      GenmaiLog.warning("Convert failed")
      return results
    }

    // Move candidates into the array of Results.
    let segment = tmpSegments.mutableConversionSegment(0)
    for i in 0..<segment.candidatesSize {
      let candidate = segment.mutableCandidate(i)

      var result = PredictionResult()
      result.cost = Int(candidate.cost)
      result.wcost = Int(candidate.wcost)
      result.lid = candidate.lid
      result.rid = candidate.rid
      result.setTypesAndTokenAttributes(Attribute.realtimeConversion, Token.Attribute.none)
      result.attributes |= Attribute.noVariantsExpansion
      if candidate.key.utf8.count < segment.key.utf8.count {
        result.attributes |= Attribute.partiallyKeyConsumed
        result.consumedKeySize = UInt32(Util.charsLen(candidate.key))
      }
      // Kana expansion happens inside the decoder.
      if (candidate.attributes & Attribute.keyExpandedInDictionary) != 0 {
        result.attributes |= Attribute.keyExpandedInDictionary
      }
      result.attributes |= candidate.attributes
      result.key = candidate.key
      result.value = candidate.value
      result.innerSegmentBoundary = candidate.innerSegmentBoundary
      results.append(result)
    }

    return results
  }

  /// value is reading, key is the input.
  open func reverseDecode(_ request: ConversionRequest) -> [PredictionResult] {
    let tmpSegments = ConverterUtil.prepareSegmentsFromRequest(request)

    let requestForReverse = ConversionRequestBuilder()
      .setConversionRequestView(request)
      .setRequestType(.reverseConversion)
      .build()

    if !immutableConverter.convert(requestForReverse.options(), tmpSegments)
      || tmpSegments.conversionSegmentsSize == 0
    {
      GenmaiLog.warning("Reverse conversion failed")
      return []
    }

    if let result = ConverterUtil.conversionSegmentsToResult(tmpSegments.conversionSegments) {
      return [result]
    }

    return []
  }

  /// Decodes suffix with the prefix rid as constraint.
  /// Request is used to pass configurations or flags that are not directly
  /// required for the conversion. Actual conversion key is passed via
  /// `suffix`. When `prefix_rid` is zero, performs the full decoding. The
  /// result is automatically cached. Note that we cannot use
  /// ConversionRequest::history_rid() as the prefix_rid, as history_rid is
  /// not used as the constraint of realtime decoding.
  open func decodeSuffix(
    _ request: ConversionRequest, _ prefixRid: UInt16, _ suffix: String
  ) -> PredictionResult? {
    if suffix.isEmpty {
      return nil
    }

    let cacheKey = SuffixCacheKey(prefixRid: prefixRid, suffix: Array(suffix.utf8))

    if let cached = suffixCache.lookup(cacheKey) {
      return cached
    }

    var options = request.options()
    options.maxConversionCandidatesSize = 1
    options.createPartialCandidates = false
    options.kanaModifierInsensitiveConversion = false
    options.useActualConverterForRealtimeConversion = false
    options.usedInPredictorRealtimeConversion = true

    let hasPrefix = prefixRid != 0

    if hasPrefix {
      // The left context of the suffix must be prefix_rid.
      options.bosId = prefixRid
      // suffix is not a beginning of the input, so disable the prefix penalty.
      options.disablePrefixPenalty = true
    }

    let req = ConversionRequestBuilder()
      .setConversionRequestView(request)
      .setOptions(options)
      .setEmptyHistoryResult()
      .setKey(suffix)
      .build()

    let results = decode(req)
    guard let result = results.first else {
      return nil
    }

    suffixCache.insert(cacheKey, result)

    return result
  }
}

extension RealtimeDecoder: UserHistoryRealtimeDecoder {}
