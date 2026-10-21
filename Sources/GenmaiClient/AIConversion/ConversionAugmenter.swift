// The source of AI conversion results (not part of Mozc). GenmaiAIClient's `GenmaiAugmenter` implements it with
// the genmai model; tests use fakes. Everything Mozc-specific (when to ask, how long to wait, how the result is
// merged into Mozc's segments) lives in `AIConversionHook` / `AIConversionAligner`, so an augmenter only maps a
// reading and a left context to whole-sentence conversions.

import Foundation

public enum AIConversionStatus: Equatable, Sendable {
  /// Disabled in the settings (nothing is loaded).
  case disabled
  /// The model is being loaded / warmed up.
  case loading
  case ready
  /// Loading failed (e.g. the model files are missing).
  case failed(String)
}

/// All methods but `convert` are called from the main actor (inside `SessionHandler.evalCommand`) and must
/// return quickly; the model work runs elsewhere (`convert` is awaited from a detached task, before the
/// conversion key is evaluated).
public protocol ConversionAugmenter: AnyObject, Sendable {
  /// Applies the settings: starts loading the model when enabled, releases it when disabled.
  func configure(_ settings: AIConversionSettings)

  var status: AIConversionStatus { get }

  /// The composition changed to `reading` (hiragana, possibly incomplete): pre-convert what is final in the
  /// background. Fire and forget; a newer call supersedes an older one.
  func prepare(reading: String, context: String)

  /// Whole-sentence conversions of `reading` after `context` (left context), best first, at most `maxResults`.
  /// Must honor task cancellation. A result it computes (or awaits) must afterwards be returned by
  /// `readyResult` for the same reading and context.
  func convert(reading: String, context: String, maxResults: Int) async throws -> [String]

  /// The finished conversion of exactly `reading` after `context`, if there is one (from `prepare`'s
  /// speculation or an earlier `convert`), without waiting: called on the conversion key.
  func readyResult(reading: String, context: String, maxResults: Int) -> [String]?

  /// If background work for exactly `reading` after `context` is in flight (the speculative conversion started by
  /// `prepare`, or the exact conversion that refines its result after a typing pause), a task that finishes when
  /// that work is over: true if it stored a result whose top-1 differs from what `readyResult` returned before
  /// (or there was none), false otherwise (cancelled, failed, unchanged). nil: nothing in flight. Starts no work.
  /// Used to refresh the suggestion window when the AI result arrives after the keystroke was answered.
  func resultUpdate(reading: String, context: String) -> Task<Bool, Never>?

  /// Diagnostics of the ready result for `reading` / `context` (debug log), if any.
  func resultInfo(reading: String, context: String) -> AIResultInfo?
}

/// Diagnostics of a finished AI result.
public struct AIResultInfo: Equatable, Sendable {
  /// Model time of the conversion that produced the result.
  public var latency: Duration?
  /// The exact conversion (refined after a typing pause), not the fast draft-and-verify speculation.
  public var exact: Bool

  public init(latency: Duration?, exact: Bool) {
    self.latency = latency
    self.exact = exact
  }
}

extension ConversionAugmenter {
  public var isReady: Bool { status == .ready }
}
