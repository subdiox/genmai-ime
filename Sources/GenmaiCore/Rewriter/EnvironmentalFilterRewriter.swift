// Port of mozc/src/rewriter/environmental_filter_rewriter.{h,cc} (3.35.6354).
//
// This rewriter is used for environment specific filtering.
// There are roughly three major roles of this rewriter.
//
// 1. Normalization
// There were characters which should be rewriten in some platforms. For
// example, in Windows environment, U+FF0D is preferred than U+2212 for the
// glyph of 'full-width minus', due to historical reason. This rewriter rewrites
// candidate containing U+2212 if the environment is Windows.
//
// 2. Validation
// This rewriter checks validity as UTF-8 string for each candidate. If
// unacceptable candidates were to be found, this rewriter removes such
// candidates.
//
// 3. Unavailable glyph removal
// There are some glyphs that can be in candidates but not always available
// among environments. For example, newer emojis tend to be unavailable in old
// OSes. In order to reject such glyphs appearing as candidates, this rewriter
// removes candidates containing unavailable glyphs. Information about font
// availability in environments are sent by clients.
//
// Deviations from C++:
// - `std::u32string` is `[Char32]`.
// - The constructor also has a convenience overload taking the
//   `(tokenArray, stringArray)` pair returned by
//   `DataManager.getEmojiRewriterData()` (C++ `make_unique_from_tuples`).

import GenmaiBase
import GenmaiProtocol

private typealias AdditionalRenderableCharacterGroup =
  Genmai_Commands_Request.AdditionalRenderableCharacterGroup

// Returns (base ** multiplier) % modulo.
private func power(_ base: Int64, _ multiplier: Int, _ modulo: Int64) -> Int64 {
  if multiplier <= 0 {
    return 1
  }
  return (power(base, multiplier - 1, modulo) * base) % modulo
}

// Calculates Rolling Hash for given String.
// ref: https://en.wikipedia.org/wiki/Rolling_hash
private struct RollingHasher {
  // kBase and kModulo are choosed considering
  // 1. kModulo * kBase < 2**63
  // 2. kModulo is as large as possible
  // 3. kBase is coprime with kModulo and large.
  static let kBase: Int64 = 2_147_483_634
  static let kModulo: Int64 = 2_147_483_647
  static let kMaxLength = 15
  static let kPowers: [Int64] = (0...kMaxLength).map { power(kBase, $0, kModulo) }

  private var hashes: [Int64] = [0]

  mutating func append(_ value: Char32) {
    hashes.append((hashes[hashes.count - 1] * Self.kBase + Int64(value)) % Self.kModulo)
  }

  mutating func reserve(_ size: Int) { hashes.reserveCapacity(size) }

  // Calculates hash for [l, r) partial string for target.
  func hashBetween(_ l: Int, _ r: Int) -> Int64 {
    assert(l < r)
    var l = l
    // Because kPowers is only prepared for up to kMaxLength, check it required.
    if r - l > Self.kMaxLength {
      // DLOG(ERROR) << "The hash length is more than the max: " << kMaxLength;
      l = r - Self.kMaxLength
    }
    // Enforce modulo to be non-negative.
    // This function is optimized. Intended implementation is
    // return (hashes_[r] - kPowers[r - l] * hashes_[l]) % kModulo;
    let d = hashes[r] - (Self.kPowers[r - l] * hashes[l]) % Self.kModulo
    if d >= 0 {
      return d
    } else {
      return d + Self.kModulo
    }
  }
}

private func checkCodepointsAcceptable(_ codepoints: [Char32]) -> Bool {
  for c in codepoints {
    if !Util.isAcceptableCharacterAsCandidate(c) {
      return false
    }
  }
  return true
}

private func findCodepointsInClosedRange(
  _ codepoints: [Char32], _ left: Char32, _ right: Char32
) -> Bool {
  for c in codepoints {
    if left <= c && c <= right {
      return true
    }
  }
  return false
}

private func getNonrenderableGroups(
  _ additionalGroups: [AdditionalRenderableCharacterGroup]
) -> [AdditionalRenderableCharacterGroup] {
  // WARNING: Though it is named k'All'Cases, 'Empty' is intentionally omitted
  // here. All other cases should be added.
  let kAllCases: [AdditionalRenderableCharacterGroup] = [
    .kanaSupplement60,
    .kanaSupplementAndKanaExtendedA100,
    .kanaExtendedA140,
    .emoji121,
    .emoji130,
    .emoji131,
    .emoji140,
    .emoji150,
    .emoji151,
    .emoji160,
    .emoji170,
    .emoji180,
    .egyptianHieroglyph52,
    .ivsCharacter,
  ]

  var result: [AdditionalRenderableCharacterGroup] = []
  for group in kAllCases {
    if additionalGroups.contains(group) {
      continue
    }
    result.append(group)
  }
  return result
}

// If the candidate should not by modified by this rewriter, returns true.
private func shouldKeepCandidate(_ candidate: Candidate) -> Bool {
  candidate.attributes & (Attribute.noModification | Attribute.userDictionary) != 0
}

private func normalizeCandidate(_ candidate: Candidate, _ flag: TextNormalizer.Flag) -> Bool {
  // ShouldKeepCandidate should be called before.
  let value = TextNormalizer.normalizeTextWithFlag(candidate.value, flag)
  let contentValue = TextNormalizer.normalizeTextWithFlag(candidate.contentValue, flag)

  if contentValue.bytesEqual(candidate.contentValue) && value.bytesEqual(candidate.value) {
    // No update.
    return false
  }

  candidate.value = value
  candidate.contentValue = contentValue
  // Clear the description which might be wrong.
  candidate.description = ""

  return true
}

private func extractTargetEmojis(
  _ targetVersions: [EmojiVersion], _ tokenArrayData: DataView, _ stringArrayData: DataView
) -> [EmojiVersion: [[Char32]]] {
  var stringArray = SerializedStringArray()
  stringArray.set(stringArrayData)

  var results: [EmojiVersion: [[Char32]]] = [:]
  for targetVersion in targetVersions {
    results[targetVersion] = []
  }

  let tokens = EmojiDataArray(tokenArrayData)

  for token in tokens {
    let unicodeVersionIndex = token.unicodeVersionIndex
    // unicode_version_index will not be negative.
    if unicodeVersionIndex > EmojiVersion.emojiMaxVersion.rawValue {
      continue
    }
    guard let version = EmojiVersion(rawValue: unicodeVersionIndex),
      results[version] != nil
    else {
      continue
    }
    let utf8Emoji = stringArray[Int(token.emojiIndex)]
    results[version]!.append(Util.utf8ToUtf32(utf8Emoji))
  }
  return results
}

private func sortAndUnique(_ codepoints: [Char32]) -> [Char32] {
  var result = codepoints.sorted()
  var unique: [Char32] = []
  unique.reserveCapacity(result.count)
  for c in result where unique.last != c {
    unique.append(c)
  }
  result = unique
  return result
}

/// Sorted set intersection (`std::set_intersection`) of two sorted unique
/// arrays.
private func setIntersection(_ a: [Char32], _ b: [Char32]) -> [Char32] {
  var result: [Char32] = []
  var i = 0
  var j = 0
  while i < a.count && j < b.count {
    if a[i] < b[j] {
      i += 1
    } else if b[j] < a[i] {
      j += 1
    } else {
      result.append(a[i])
      i += 1
      j += 1
    }
  }
  return result
}

/// Returns the index of the first element greater than `value`.
private func upperBound(_ array: [Char32], _ value: Char32) -> Int {
  var lo = 0
  var hi = array.count
  while lo < hi {
    let mid = (lo + hi) / 2
    if array[mid] <= value {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  return lo
}

private func binarySearch(_ array: [Int64], _ value: Int64) -> Bool {
  var lo = 0
  var hi = array.count
  while lo < hi {
    let mid = (lo + hi) / 2
    if array[mid] < value {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  return lo < array.count && array[lo] == value
}

public struct CharacterGroupFinder: Sendable {
  // Closed range of single codepoints, like {{U+1F000, U+1F100}, {U+1F202,
  // U+1F202}}. For implementation reason, they are split into two.
  private var sortedSingleCodepointLefts: [Char32] = []
  private var sortedSingleCodepointRights: [Char32] = []
  private var minSingleCodepoint: Char32 = 0
  // First: Vector of Emoji which requires multiple codepoints, like {{U+1Fxxx,
  // U+200D, U+1Fyyy}, {U+1Fzzz, U+200D, U+1Fwww}}.
  // Second: rolling hash of the given codepoints.
  private var multipleCodepoints: [[Char32]] = []
  private var multipleCodepointsHashes: [Int64] = []
  // This is max length of multiple codepoints.
  private var maxLength = 0
  // Intersection of multiple_codepoints_. For example, for emoji, it is very
  // likely to have ZWJ (U+200D) in common.
  private var sortedMultipleCodepointsIntersection: [Char32] = []

  public init() {}

  /// Sets target_codepoints, which represents target group.
  public mutating func initialize(_ targetCodepoints: [[Char32]]) {
    var singleCodepoints: [Char32] = []
    for codepoints in targetCodepoints {
      let size = codepoints.count
      if size == 1 {
        singleCodepoints.append(codepoints[0])
      } else {
        maxLength = max(maxLength, size)
        var hasher = RollingHasher()
        hasher.reserve(size)
        for codepoint in codepoints {
          hasher.append(codepoint)
        }
        multipleCodepoints.append(codepoints)
        multipleCodepointsHashes.append(hasher.hashBetween(0, size))
      }
    }

    multipleCodepointsHashes.sort()

    // Create intersection of multiple_codepoints_ to use early return key in
    // search algorithm.
    if !multipleCodepoints.isEmpty {
      var intersection = sortAndUnique(multipleCodepoints[0])
      for codepoints in multipleCodepoints {
        let cpSet = sortAndUnique(codepoints)
        intersection = setIntersection(cpSet, intersection)
      }
      sortedMultipleCodepointsIntersection = intersection
    }

    // sort and summarize them into range;
    singleCodepoints.sort()
    if !singleCodepoints.isEmpty {
      minSingleCodepoint = singleCodepoints[0]
    }
    var lastLeft: Char32 = 0
    var lastRight: Char32 = 0
    for codepoint in singleCodepoints {
      if lastRight == 0 {
        lastLeft = codepoint
        lastRight = codepoint
        continue
      }
      if lastRight &+ 1 == codepoint {
        lastRight += 1
        continue
      }
      sortedSingleCodepointLefts.append(lastLeft)
      sortedSingleCodepointRights.append(lastRight)
      lastLeft = codepoint
      lastRight = codepoint
    }
    if lastRight != 0 {
      sortedSingleCodepointLefts.append(lastLeft)
      sortedSingleCodepointRights.append(lastRight)
    }
  }

  /// Finds targeted character in given target codepoints. If found, returns
  /// true. If not found, returns false.
  public func findMatch(_ target: [Char32]) -> Bool {
    for codepoint in target {
      // Single codepoint check
      // If codepoint is smaller than min value, continue before executing
      // binary search.
      if codepoint < minSingleCodepoint {
        continue
      }
      let indexUpper = upperBound(sortedSingleCodepointLefts, codepoint)
      if indexUpper != 0 && codepoint <= sortedSingleCodepointRights[indexUpper - 1] {
        return true
      }
    }

    // If target does not contain any intersection of multiple_codepoints_,
    // return false here.
    for codepoint in sortedMultipleCodepointsIntersection {
      if !target.contains(codepoint) {
        return false
      }
    }

    // Multiple Codepoint Check.
    var hasher = RollingHasher()
    hasher.reserve(target.count)
    for right in 0..<target.count {
      hasher.append(target[right])
      var left = right - 1
      while left >= 0 {
        defer { left -= 1 }
        if right - left > maxLength {
          break
        }
        // Example:
        //  For codepoints {0x0, 0x1, 0x2, 0x3, 0x4} and left = 1 and right = 3,
        //  `hash` is hash for {0x1, 0x2}
        let hash = hasher.hashBetween(left, right + 1)
        if binarySearch(multipleCodepointsHashes, hash) {
          // As hash can collide in some unfortunate case, double-check here.
          let hashedTarget = target[left...right]
          for codepoints in multipleCodepoints {
            if hashedTarget.elementsEqual(codepoints) {
              return true
            }
          }
        }
      }
    }
    return false
  }
}

public final class EnvironmentalFilterRewriter: RewriterInterface {
  // Controls the normalization behavior.
  private var flag: TextNormalizer.Flag = .kDefault

  // Filters for filtering target Emoji versions.
  private var finderE12_1 = CharacterGroupFinder()
  private var finderE13_0 = CharacterGroupFinder()
  private var finderE13_1 = CharacterGroupFinder()
  private var finderE14_0 = CharacterGroupFinder()
  private var finderE15_0 = CharacterGroupFinder()
  private var finderE15_1 = CharacterGroupFinder()
  private var finderE16_0 = CharacterGroupFinder()
  private var finderE17_0 = CharacterGroupFinder()
  private var finderE18_0 = CharacterGroupFinder()

  /// This class does not take an ownership of the data (the views keep the
  /// mapped data alive).
  public init(_ tokenArrayData: DataView, _ stringArrayData: DataView) {
    // TODO(mozc-team):
    // Currently, this rewriter uses data from emoji_data.tsv, which is for
    // Emoji conversion, as a source of Emoji version information. However,
    // emoji_data.tsv lacks some Emoji, including Emoji with skin-tones and
    // family/couple Emojis. As a future work, the data source should be
    // refined.
    let versionToTargets = extractTargetEmojis(
      [.e12_1, .e13_0, .e13_1, .e14_0, .e15_0, .e15_1, .e16_0, .e17_0, .e18_0],
      tokenArrayData, stringArrayData)
    finderE12_1.initialize(versionToTargets[.e12_1]!)
    finderE13_0.initialize(versionToTargets[.e13_0]!)
    finderE13_1.initialize(versionToTargets[.e13_1]!)
    finderE14_0.initialize(versionToTargets[.e14_0]!)
    finderE15_0.initialize(versionToTargets[.e15_0]!)
    finderE15_1.initialize(versionToTargets[.e15_1]!)
    finderE16_0.initialize(versionToTargets[.e16_0]!)
    finderE17_0.initialize(versionToTargets[.e17_0]!)
    finderE18_0.initialize(versionToTargets[.e18_0]!)
  }

  /// `make_unique_from_tuples<EnvironmentalFilterRewriter>(
  ///     data_manager.GetEmojiRewriterData())`.
  public convenience init(_ data: (tokenArray: DataView, stringArray: DataView)) {
    self.init(data.tokenArray, data.stringArray)
  }

  public func setNormalizationFlag(_ flag: TextNormalizer.Flag) { self.flag = flag }

  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType {
    .all
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    let nonrenderableGroups = getNonrenderableGroups(
      request.request().additionalRenderableCharacterGroups)

    var modified = false
    for segment in segments.conversionSegments {
      // Meta candidate
      for j in 0..<segment.metaCandidatesSize {
        let candidate = segment.mutableMetaCandidate(j)
        if shouldKeepCandidate(candidate) {
          continue
        }
        modified = normalizeCandidate(candidate, flag) || modified
      }

      // Regular candidate.
      let candidatesSize = segment.candidatesSize

      for j in 0..<candidatesSize {
        let reversedJ = candidatesSize - j - 1
        let candidate = segment.mutableCandidate(reversedJ)

        if shouldKeepCandidate(candidate) {
          continue
        }

        // Character Normalization
        modified = normalizeCandidate(candidate, flag) || modified

        let codepoints = Util.utf8ToUtf32(candidate.value)

        // Check acceptability of code points as a candidate.
        if !checkCodepointsAcceptable(codepoints) {
          segment.eraseCandidate(reversedJ)
          modified = true
          continue
        }

        // WARNING: Current implementation assumes cases are mutually
        // exclusive. If that assumption becomes no longer correct, revise this
        // implementation.
        //
        // Performance Notes:
        // - Order for checking impacts performance. It is ideal to re-order
        // character groups into often-hit order.
        // - Some groups can be merged when they are both rejected, For example,
        // if KANA_SUPPLEMENT_6_0 and KANA_SUPPLEMENT_AND_KANA_EXTENDED_A_10_0
        // are both rejected, range can be [0x1B000, 0x1B11E], and then the
        // number of check can be reduced.
        for group in nonrenderableGroups {
          var foundNonrenderable = false
          // Come here when the group is un-adapted option.
          // For this switch statement, 'default' case should not be added.
          switch group {
          case .empty:
            break
          case .kanaSupplement60:
            foundNonrenderable = findCodepointsInClosedRange(codepoints, 0x1B000, 0x1B001)
          case .kanaSupplementAndKanaExtendedA100:
            foundNonrenderable = findCodepointsInClosedRange(codepoints, 0x1B002, 0x1B11E)
          case .kanaExtendedA140:
            foundNonrenderable = findCodepointsInClosedRange(codepoints, 0x1B11F, 0x1B122)
          case .emoji121:
            foundNonrenderable = finderE12_1.findMatch(codepoints)
          case .emoji130:
            foundNonrenderable = finderE13_0.findMatch(codepoints)
          case .emoji131:
            foundNonrenderable = finderE13_1.findMatch(codepoints)
          case .emoji140:
            foundNonrenderable = finderE14_0.findMatch(codepoints)
          case .emoji150:
            foundNonrenderable = finderE15_0.findMatch(codepoints)
          case .emoji151:
            foundNonrenderable = finderE15_1.findMatch(codepoints)
          case .emoji160:
            foundNonrenderable = finderE16_0.findMatch(codepoints)
          case .emoji170:
            foundNonrenderable = finderE17_0.findMatch(codepoints)
          case .emoji180:
            foundNonrenderable = finderE18_0.findMatch(codepoints)
          case .egyptianHieroglyph52:
            foundNonrenderable = findCodepointsInClosedRange(codepoints, 0x13000, 0x1342E)
          case .ivsCharacter:
            foundNonrenderable = findCodepointsInClosedRange(codepoints, 0xE0100, 0xE010E)
          }
          if foundNonrenderable {
            segment.eraseCandidate(reversedJ)
            modified = true
            break
          }
        }
      }
    }

    return modified
  }
}
