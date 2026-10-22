// Port of mozc/src/converter/candidate.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::converter::Candidate`.
///
/// A reference type: C++ code holds `Candidate*` into segments and mutates
/// candidates in place (`segment->mutable_candidate(i)->value = ...`). The C++
/// copy constructor / assignment (`Candidate c = other;`, `*c = other;`) are
/// `copy()` / `init(copying:)` / `assign(from:)`.
public final class Candidate {
  public enum Command: UInt8, Sendable {
    case defaultCommand = 0
    case enableIncognitoMode  // enables "incognito mode".
    case disableIncognitoMode  // disables "incognito mode".
    case enablePresentationMode  // enables "presentation mode".
    case disablePresentationMode  // disables "presentation mode".
  }

  public enum Category: UInt8, Sendable {
    case defaultCategory  // Realtime conversion, history prediction, etc
    case symbol  // Symbol, emoji
    case other  // Misc candidate
  }

  /// `converter::Attribute` (for code written as `Candidate::USER_DICTIONARY`).
  public typealias Attribute = GenmaiCore.Attribute

  // LINT.IfChange
  public var key: String = ""  // reading
  public var value: String = ""  // surface form
  public var contentKey: String = ""
  public var contentValue: String = ""

  public var consumedKeySize: UInt32 = 0

  /// Number of whole conversion segments covered/consumed by this candidate,
  /// starting from the current segment.
  ///
  /// Note: This assumes alignment with the existing segment boundaries
  /// (i.e. spans 1, 2, ..., N complete segments). Candidates with non-aligned
  /// boundaries (crossing mid-segment) cannot be represented by this field and
  /// require segment resizing (ResizeSegment).
  ///
  /// Defaults to 1 for standard segment candidates. Even if set to 0,
  /// callers should use effectiveConvertedSegmentCount which clamps to 1.
  public var convertedSegmentCount: UInt32 = 1

  /// Returns the effective number of segments covered by this candidate.
  /// Guaranteed to be at least 1 even if convertedSegmentCount is 0.
  public var effectiveConvertedSegmentCount: UInt32 { max(1, convertedSegmentCount) }

  // Meta information
  public var prefix: String = ""
  public var suffix: String = ""
  /// Description including description type and message
  public var description: String = ""
  /// Description for A11y support (e.g. "あ。ヒラガナ あ")
  public var a11yDescription: String = ""
  /// Actual value to be displayed. Uses it to encode meta information
  /// in the value. e.g., puts "_" to clarify the unrecognizable white spaces.
  public var displayValue: String = ""

  /// Usage ID
  public var usageId: Int32 = 0
  /// Title of the usage containing basic form of this candidate.
  public var usageTitle: String = ""
  /// Content of the usage.
  public var usageDescription: String = ""

  /// Context "sensitive" candidate cost.
  /// Taking adjacent words/nodes into consideration.
  /// Basically, candidate is sorted by this cost.
  public var cost: Int32 = 0
  /// Context "free" candidate cost
  /// NOT taking adjacent words/nodes into consideration.
  public var wcost: Int32 = 0
  /// (cost without transition cost between left/right boundaries)
  /// Cost of only transitions (cost without word cost adjacent context)
  public var structureCost: Int32 = 0

  /// Attributes of this candidate. Can set multiple attributes
  /// defined in `Attribute`.
  public var attributes: UInt32 = 0

  /// lid of left-most node
  public var lid: UInt16 = 0
  /// rid of right-most node
  public var rid: UInt16 = 0

  public var category: Category = .defaultCategory

  /// Candidate style. This is not a bit-field.
  public var style: NumberUtil.NumberString.Style = .defaultStyle

  /// Command of this candidate. This is not a bit-field.
  public var command: Command = .defaultCommand

  /// Boundary information for real time conversion.  This will be set only for
  /// real time conversion result candidates.  Each element is the encoded
  /// lengths of key, value, content key and content value.
  public var innerSegmentBoundary: InnerSegmentBoundary = []
  // LINT.ThenChange(//converter/segments_matchers.h)

  /// Debug log (`MOZC_CANDIDATE_DEBUG`, debug builds only).
  public var log: String = ""

  public init() {}

  /// Convenience initializer for the most common fields.
  public convenience init(
    key: String, value: String, contentKey: String? = nil, contentValue: String? = nil,
    cost: Int32 = 0, wcost: Int32 = 0, structureCost: Int32 = 0, lid: UInt16 = 0, rid: UInt16 = 0,
    attributes: UInt32 = 0
  ) {
    self.init()
    self.key = key
    self.value = value
    self.contentKey = contentKey ?? key
    self.contentValue = contentValue ?? value
    self.cost = cost
    self.wcost = wcost
    self.structureCost = structureCost
    self.lid = lid
    self.rid = rid
    self.attributes = attributes
  }

  /// C++ copy constructor.
  public convenience init(copying other: Candidate) {
    self.init()
    assign(from: other)
  }

  /// C++ copy constructor.
  public func copy() -> Candidate { Candidate(copying: self) }

  /// C++ copy assignment (`*this = other`).
  public func assign(from other: Candidate) {
    if other === self { return }
    key = other.key
    value = other.value
    contentKey = other.contentKey
    contentValue = other.contentValue
    consumedKeySize = other.consumedKeySize
    convertedSegmentCount = other.convertedSegmentCount
    prefix = other.prefix
    suffix = other.suffix
    description = other.description
    a11yDescription = other.a11yDescription
    displayValue = other.displayValue
    usageId = other.usageId
    usageTitle = other.usageTitle
    usageDescription = other.usageDescription
    cost = other.cost
    wcost = other.wcost
    structureCost = other.structureCost
    attributes = other.attributes
    lid = other.lid
    rid = other.rid
    category = other.category
    style = other.style
    command = other.command
    innerSegmentBoundary = other.innerSegmentBoundary
    log = other.log
  }

  public func innerSegments() -> InnerSegments {
    InnerSegments(
      key: key, value: value, contentKey: contentKey, contentValue: contentValue,
      innerSegmentBoundary: innerSegmentBoundary)
  }

  /// Clears the Candidate with default values. Note that the default
  /// constructor already does the same so you don't need to call clear
  /// explicitly.
  ///
  /// As in C++, `a11yDescription` and `category` are not cleared.
  public func clear() {
    key = ""
    value = ""
    contentValue = ""
    contentKey = ""
    consumedKeySize = 0
    convertedSegmentCount = 1
    prefix = ""
    suffix = ""
    description = ""
    displayValue = ""
    usageTitle = ""
    usageDescription = ""
    cost = 0
    structureCost = 0
    wcost = 0
    lid = 0
    rid = 0
    usageId = 0
    attributes = 0
    style = .defaultStyle
    command = .defaultCommand
    innerSegmentBoundary = []
    log = ""
  }

  /// Returns functional key.
  /// functional_key =
  /// key.substr(content_key.size(), key.size() - content_key.size());
  public var functionalKey: Substring {
    key.byteSubstring(from: min(key.utf8.count, contentKey.utf8.count))
  }

  /// Returns functional value.
  /// functional_value =
  /// value.substr(content_value.size(), value.size() - content_value.size());
  public var functionalValue: Substring {
    value.byteSubstring(from: min(value.utf8.count, contentValue.utf8.count))
  }

  /// `MOZC_CANDIDATE_LOG(candidate, message)`; only records in debug builds.
  public func dlog(_ message: String, file: String = #fileID, line: Int = #line) {
    #if DEBUG
      log += "\(file):\(line) \(message)\n"
    #endif
  }

  public func debugString() -> String {
    var os = "(key=\(key) ckey=\(contentKey) val=\(value) cval=\(contentValue) cost=\(cost)"
    os += " scost=\(structureCost) wcost=\(wcost) lid=\(lid) rid=\(rid) attributes="
    // std::bitset<16>(attributes)
    for bit in stride(from: 15, through: 0, by: -1) {
      os += (attributes >> UInt32(bit)) & 1 == 1 ? "1" : "0"
    }
    os += " consumed_key_size=\(consumedKeySize) converted_segment_count=\(convertedSegmentCount)"
    if !prefix.isEmpty {
      os += " prefix=\(prefix)"
    }
    if !suffix.isEmpty {
      os += " suffix=\(suffix)"
    }
    if !description.isEmpty {
      os += " description=\(description)"
    }
    if !displayValue.isEmpty {
      os += " display_value=\(displayValue)"
    }
    if !innerSegmentBoundary.isEmpty {
      os += " segbdd="
      for iter in innerSegments() {
        os +=
          "<\(iter.key.utf8.count),\(iter.value.utf8.count),\(iter.contentKey.utf8.count),\(iter.contentValue.utf8.count)>"
      }
    }
    os += ")\n"
    return os
  }
}

extension Candidate: InnerSegmentValueRewritable {
  public static var hasContentValue: Bool { true }
  public var rewritableContentValue: String {
    get { contentValue }
    set { contentValue = newValue }
  }
}
