// Port of mozc/src/rewriter/rewriter_interface.h (3.35.6354).
//
// Deviations from C++:
// - `RewriterInterface` is a protocol; the nested C++ enums / struct and the
//   static helpers live in the `Rewriter` namespace enum
//   (`Rewriter.CapabilityType`, `Rewriter.ResizeSegmentsRequest`,
//   `Rewriter.disableLegacyRewriter(...)`), because Swift protocols cannot
//   have nested types.
// - Virtual methods with a default body are protocol requirements with a
//   default in an extension. NOTE (protocol default dispatch pitfall, see
//   CLAUDE.md): a class hierarchy of rewriters must implement every
//   requirement it customizes in the base class and `override` it in
//   subclasses; otherwise the extension default is called through
//   `any RewriterInterface`.
// - `Segments*` is the reference type `Segments`.

import GenmaiProtocol

public enum Rewriter {
  public struct CapabilityType: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let notAvailable: CapabilityType = []
    public static let conversion = CapabilityType(rawValue: 1)
    public static let prediction = CapabilityType(rawValue: 2)
    public static let suggestion = CapabilityType(rawValue: 4)
    public static let all: CapabilityType = [.conversion, .prediction, .suggestion]
  }

  public struct ResizeSegmentsRequest: Sendable, Equatable {
    /// The new size of each segment in Unicode character (e.g. 3 for "あいう").
    /// The type and size (i.e. uint8_t and 8) comes from the implementation of
    /// UserBoundaryHistoryRewriter that stores the segment sizes in this
    /// format.
    public typealias SegmentSizes = [UInt8]  // std::array<uint8_t, 8>

    /// Position of the segment to be resized.
    public var segmentIndex: Int = 0
    /// Always 8 elements.
    public var segmentSizes: SegmentSizes = [0, 0, 0, 0, 0, 0, 0, 0]

    public init(segmentIndex: Int = 0, segmentSizes: SegmentSizes = [0, 0, 0, 0, 0, 0, 0, 0]) {
      self.segmentIndex = segmentIndex
      self.segmentSizes = segmentSizes
    }
  }

  /// We plan to deprecate the following rewriters in the future, as
  /// equivalent functionalities have already been implemented. To
  /// experimentally disable them, we will use the
  /// disable_legacy_rewriter_mode mendel flag to suppress their behavior.
  public enum LegacyRewriterType {
    public static let disableUserSegmentHistory: Int32 = 1
    public static let disableUserBoundaryHistory: Int32 = 2
    public static let disableCollocation: Int32 = 4
  }

  /// Returns true if (disable_legacy_rewriter_mode() & mode) and
  /// mixed_conversion is true.
  public static func disableLaegacyRewriterInMixedConversion(
    _ request: ConversionRequest, _ mode: Int32
  ) -> Bool {
    request.request().mixedConversion
      && (request.request().decoderExperimentParams.disableLegacyRewriterMode & mode) != 0
  }

  /// Returns true if (disable_legacy_rewriter_in_all_conversion_mode() & mode)
  /// is true.
  public static func disableLegacyRewriter(_ request: ConversionRequest, _ mode: Int32) -> Bool {
    (request.request().decoderExperimentParams.disableLegacyRewriterInAllConversionMode & mode)
      != 0
  }
}

public protocol RewriterInterface: AnyObject {
  /// Returns capability of this rewriter.
  /// If (capability() & CONVERSION), this rewriter
  /// is called after StartConversion().
  func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType

  func checkResizeSegmentsRequest(_ request: ConversionRequest, _ segments: Segments)
    -> Rewriter.ResizeSegmentsRequest?

  func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool

  /// This method is mainly called when user puts SPACE key
  /// and changes the focused candidate.
  /// In this method, Converter will find bracketing matching.
  /// e.g., when user selects "「",  corresponding closing bracket "」"
  /// is chosen in the preedit.
  func focus(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool

  /// Hook(s) for all mutable operations
  func finish(_ request: ConversionRequest, _ segments: Segments)

  /// Reverts the last Finish operation.
  func revert(_ segments: Segments)

  /// Delete the user history based entry corresponding to the specified
  /// candidate.
  /// Returns true when at least one deletion operation succeeded
  /// |segment_index| is the index for all segments, not the index of
  /// conversion_segments.
  func clearHistoryEntry(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool

  /// Synchronizes internal data to local file system.  This method is called
  /// when the server received SYNC_DATA command from the client.  Currently,
  /// this event happens, e.g., when user moves to another text area.
  @discardableResult func sync() -> Bool

  /// Reloads internal data from local file system.  This method is called
  /// when the server received RELOAD command from the client.  Currently,
  /// this event happens when user edited the user dictionary by dictionary
  /// tool.
  @discardableResult func reload() -> Bool

  /// Clears internal data on local storage.  This method is called when the
  /// server received CLEAR_USER_HISTORY command from the client.  Currently,
  /// this event happens when user explicitly requested "clear user history"
  /// on settings UI.
  func clear()
}

extension RewriterInterface {
  public func capability(_ request: ConversionRequest) -> Rewriter.CapabilityType { .conversion }
  public func checkResizeSegmentsRequest(_ request: ConversionRequest, _ segments: Segments)
    -> Rewriter.ResizeSegmentsRequest?
  { nil }
  public func focus(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int) -> Bool {
    true
  }
  public func finish(_ request: ConversionRequest, _ segments: Segments) {}
  public func revert(_ segments: Segments) {}
  public func clearHistoryEntry(_ segments: Segments, _ segmentIndex: Int, _ candidateIndex: Int)
    -> Bool
  { false }
  public func sync() -> Bool { true }
  public func reload() -> Bool { true }
  public func clear() {}
}
