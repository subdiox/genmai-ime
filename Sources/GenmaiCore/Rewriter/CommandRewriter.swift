// Port of mozc/src/rewriter/command_rewriter.{h,cc} (3.35.6354).

import GenmaiProtocol

private let kPrefix = "【"
private let kSuffix = "】"
private let kDescription = "設定を変更します"

private let kIncoginitoModeOn = "シークレットモードをオン"
private let kIncoginitoModeOff = "シークレットモードをオフ"
private let kDisableAllSuggestionOn = "サジェスト機能の一時停止"
private let kDisableAllSuggestionOff = "サジェスト機能を元に戻す"

private let kTriggerKeys = [
  "こまんど", "しーくれっと", "しーくれっともーど", "ひみつ",
  "ぷらいばしー", "ぷらいべーと", "さじぇすと", "ぷれぜんてーしょん",
  "ぷれぜん", "よそく", "よそくにゅうりょく", "よそくへんかん",
  "すいそくこうほ",
]

private let kCommandValues = ["コマンド"]

private let kIncognitoModeValues = [
  "秘密", "シークレット", "シークレットモード", "プライバシー", "プライベート",
]

private let kDisableAllSuggestionValues = [
  "サジェスト", "予測", "予測入力", "予測変換", "プレゼンテーション", "プレゼン",
]

private func findString(_ query: String, _ values: [String]) -> Bool {
  values.contains { $0.bytesEqual(query) }
}

private func insertCommandCandidate(_ segment: Segment, _ referencePos: Int, _ insertPos: Int)
  -> Candidate
{
  let candidate = segment.insertCandidate(min(segment.candidatesSize, insertPos))!
  candidate.assign(from: segment.candidate(referencePos))
  candidate.attributes |= Attribute.commandCandidate
  candidate.attributes |= Attribute.noLearning
  candidate.description = kDescription
  candidate.prefix = kPrefix
  candidate.suffix = kSuffix
  candidate.innerSegmentBoundary.removeAll()
  return candidate
}

private func isSuggestionEnabled(_ config: Genmai_Config_Config) -> Bool {
  config.useHistorySuggest || config.useDictionarySuggest || config.useRealtimeConversion
}

public final class CommandRewriter: RewriterInterface {
  public init() {}

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if segments.conversionSegmentsSize != 1 {
      return false
    }

    let segment = segments.mutableConversionSegment(0)
    let key = segment.key

    // TODO(taku): we want to replace the linear search with STL map when
    // kTriggerKeys become bigger.
    if !findString(key, kTriggerKeys) {
      return false
    }

    return rewriteSegment(request.config(), segment)
  }

  private func rewriteSegment(_ config: Genmai_Config_Config, _ segment: Segment) -> Bool {
    for i in 0..<segment.candidatesSize {
      let value = segment.candidate(i).value
      if findString(value, kCommandValues) {
        // insert command candidate at an fixed position.
        insertDisableAllSuggestionToggleCommand(config, segment, i, 6)
        insertIncognitoModeToggleCommand(config, segment, i, 6)
        return true
      }
      if findString(value, kIncognitoModeValues) {
        insertIncognitoModeToggleCommand(config, segment, i, i + 3)
        return true
      }
      if findString(value, kDisableAllSuggestionValues) {
        insertDisableAllSuggestionToggleCommand(config, segment, i, i + 3)
        return true
      }
    }
    return false
  }

  /// Insert a new IncogitoModeToggle Command candidate.
  /// Use segment->candidate(base_pos) as a reference candidate.
  /// |insert_pos| is the actual position where the new candidate
  /// is inserted.
  private func insertIncognitoModeToggleCommand(
    _ config: Genmai_Config_Config, _ segment: Segment, _ referencePos: Int, _ insertPos: Int
  ) {
    let candidate = insertCommandCandidate(segment, referencePos, insertPos)
    if config.incognitoMode {
      candidate.value = kIncoginitoModeOff
      candidate.command = .disableIncognitoMode
    } else {
      candidate.value = kIncoginitoModeOn
      candidate.command = .enableIncognitoMode
    }
    candidate.contentValue = candidate.value
  }

  /// Insert a new DisableAllSuggestionToggle Command candidate.
  private func insertDisableAllSuggestionToggleCommand(
    _ config: Genmai_Config_Config, _ segment: Segment, _ referencePos: Int, _ insertPos: Int
  ) {
    if !isSuggestionEnabled(config) {
      return
    }
    let candidate = insertCommandCandidate(segment, referencePos, insertPos)
    if config.presentationMode {
      candidate.value = kDisableAllSuggestionOff
      candidate.command = .disablePresentationMode
    } else {
      candidate.value = kDisableAllSuggestionOn
      candidate.command = .enablePresentationMode
    }
    candidate.contentValue = candidate.value
  }
}
