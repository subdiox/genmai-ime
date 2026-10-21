// Port of mozc/src/rewriter/fortune_rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The random level is drawn from an injectable generator
//   (`init(levelGenerator:)`, returns a value in [0, kMaxLevel)) so that tests
//   can make the result deterministic; the default uses the system random
//   generator (absl::BitGen in C++).
// - absl::CivilDay is represented by (year, month, day) in the Clock's time
//   zone (Gregorian calendar).

import Foundation
import GenmaiBase

private enum FortuneType: Int {
  case excellentLuck = 0
  case luck = 1
  case middleLuck = 2
  case littleLuck = 3
  case luckAtTheEnd = 4
  case misfortune = 5
}

private let kNumFortuneTypes = 6
private let kMaxLevel = 100
private let kNormalLevels = [20, 40, 60, 80, 90]
private let kNewYearLevels = [30, 60, 80, 90, 95]
private let kMyBirthdayLevels = [30, 60, 80, 90, 95]
private let kFriday13Levels = [10, 25, 40, 55, 70]

private func insertCandidate(_ fortuneType: FortuneType, _ insertPos: Int, _ segment: Segment)
  -> Bool
{
  if segment.candidatesSize == 0 {
    // LOG(WARNING) << "candidates_size is 0";
    return false
  }

  let baseCandidate = segment.candidate(0)
  let offset = min(insertPos, segment.candidatesSize)

  let triggerC = segment.candidate(offset - 1)
  let value: String
  switch fortuneType {
  case .excellentLuck: value = "大吉"
  case .luck: value = "吉"
  case .middleLuck: value = "中吉"
  case .littleLuck: value = "小吉"
  case .luckAtTheEnd: value = "末吉"
  case .misfortune: value = "凶"
  }

  guard let c = segment.insertCandidate(offset) else {
    // LOG(ERROR) << "cannot insert candidate at " << offset;
    return false
  }

  c.lid = triggerC.lid
  c.rid = triggerC.rid
  c.cost = triggerC.cost
  c.value = value
  c.contentValue = value
  c.key = baseCandidate.key
  c.contentKey = baseCandidate.contentKey
  c.attributes |= Attribute.noVariantsExpansion
  c.attributes |= Attribute.noLearning
  c.description = "今日の運勢"
  return true
}

public final class FortuneRewriter: RewriterInterface {
  /// Returns a level in [0, 100).
  public typealias LevelGenerator = () -> Int

  private final class FortuneData {
    private struct CivilDay: Equatable {
      var year: Int
      var month: Int
      var day: Int
    }

    private(set) var fortuneType: FortuneType = .excellentLuck
    // absl::CivilDay() is 1970-01-01.
    private var lastUpdatedDay = CivilDay(year: 1970, month: 1, day: 1)
    private let levelGenerator: LevelGenerator

    init(levelGenerator: @escaping LevelGenerator) {
      self.levelGenerator = levelGenerator
      changeFortune()
    }

    func changeFortune() {
      var levels = kNormalLevels
      let at = Clock.getAbslTime()
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = Clock.getTimeZone()
      let comps = calendar.dateComponents([.year, .month, .day, .weekday], from: at)
      let today = CivilDay(year: comps.year!, month: comps.month!, day: comps.day!)

      // Modify once per one day
      if today == lastUpdatedDay {
        return
      }
      lastUpdatedDay = today

      // More happy at New Year's Day
      if today.month == 1 && today.day == 1 {
        levels = kNewYearLevels
      } else if today.month == 3 && today.day == 3 {
        // It's my birthday :)
        levels = kMyBirthdayLevels
      } else if today.day == 13 && comps.weekday == 6 {  // Friday (Sunday = 1)
        // Friday the 13th
        levels = kFriday13Levels
      }

      let level = levelGenerator()
      for i in 0..<kNormalLevels.count where level <= levels[i] {
        fortuneType = FortuneType(rawValue: i)!
        break
      }
      assert(fortuneType.rawValue < kNumFortuneTypes)
    }
  }

  private let fortuneData: FortuneData

  public init() {
    fortuneData = FortuneData(levelGenerator: { Int.random(in: 0..<kMaxLevel) })
  }

  /// For tests: `levelGenerator` returns a level in [0, 100).
  public init(levelGenerator: @escaping LevelGenerator) {
    fortuneData = FortuneData(levelGenerator: levelGenerator)
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    if segments.conversionSegmentsSize != 1 {
      return false
    }

    let segment = segments.conversionSegment(0)
    let key = segment.key
    if key.isEmpty {
      // LOG(ERROR) << "Key is empty";
      return false
    }
    if !key.bytesEqual("おみくじ") {
      return false
    }

    fortuneData.changeFortune()

    // Insert a fortune candidate into the last of all candidates.
    return insertCandidate(
      fortuneData.fortuneType, segment.candidatesSize, segments.mutableConversionSegment(0))
  }
}
