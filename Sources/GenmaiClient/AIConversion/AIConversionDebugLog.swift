// The AI conversion debug log (not part of Mozc).
//
// Opt-in (`"debug_log": true` in ai_conversion.json, off by default). One line per AI conversion event is appended
// to `<profile>/ai_debug.log`, to diagnose what the user saw in the real IME: the reading, the end of the left
// context, where the AI result came from, its latency, the AI n-best and the first candidate after merging.
// **The log contains the typed text and its context** (privacy): it is written only while the flag is on.
// The file is renamed to ai_debug.log.1 when it exceeds `maxBytes`.

import Foundation
import GenmaiBase
import Synchronization

public final class AIConversionDebugLog: Sendable {
  public static let fileName = "ai_debug.log"
  /// Size at which the log is rotated (one previous file is kept).
  static let maxBytes: UInt64 = 8 << 20
  /// Characters of the left context written per line.
  static let contextExcerpt = 40

  public enum Source: String, Sendable {
    /// Conversion key, the AI result had already finished.
    case ready
    /// Conversion key, the AI result was in flight and awaited.
    case awaited
    /// Conversion key, the AI result was not ready in time: Mozc's conversion was shown.
    case timeout
    /// Conversion key, the AI conversion failed.
    case error
    /// Suggestion window while typing (fast speculative result).
    case suggestion
    /// Suggestion window while typing (exact result after a typing pause).
    case refine
  }

  public struct Event: Sendable {
    public var source: Source
    public var reading: String
    public var context: String
    /// The model time of the result (or the wait at the conversion key), if known.
    public var latency: Duration?
    public var texts: [String]
    /// What the user saw first: the preedit after the conversion key, the first suggestion while typing.
    public var shown: String
    public var note: String

    public init(
      source: Source, reading: String, context: String, latency: Duration?, texts: [String], shown: String,
      note: String = ""
    ) {
      self.source = source
      self.reading = reading
      self.context = context
      self.latency = latency
      self.texts = texts
      self.shown = shown
      self.note = note
    }
  }

  /// The log file while enabled.
  private let file = Mutex<URL?>(nil)

  public init() {}

  public var isEnabled: Bool { file.withLock { $0 != nil } }

  /// `url`: nil = off; default `<profile>/ai_debug.log`.
  public func configure(enabled: Bool, url: URL? = nil) {
    let target =
      enabled
      ? url
        ?? URL(filePath: SystemUtil.getUserProfileDirectory(), directoryHint: .isDirectory).appending(
          path: Self.fileName) : nil
    file.withLock { $0 = target }
  }

  static func milliseconds(_ d: Duration) -> Double {
    Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
  }

  static func line(_ e: Event, at date: Date) -> String {
    func clean(_ s: String) -> String {
      s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "⏎")
    }
    let time = date.formatted(
      Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current))
    let latency = e.latency.map { String(format: "%.0fms", milliseconds($0)) } ?? "-"
    var fields = [
      time, e.source.rawValue, "reading=\(clean(e.reading))",
      "context=…\(clean(String(e.context.suffix(contextExcerpt))))", "latency=\(latency)",
      "ai=[\(e.texts.map(clean).joined(separator: " | "))]", "shown=\(clean(e.shown))",
    ]
    if !e.note.isEmpty {
      fields.append(clean(e.note))
    }
    return fields.joined(separator: "\t") + "\n"
  }

  /// Appends `event` (no-op while disabled). Synchronous: one small append, called on the main actor.
  public func write(_ event: Event) {
    file.withLock { url in
      guard let url else { return }
      let data = Data(Self.line(event, at: Date()).utf8)
      let fm = FileManager.default
      if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size > Self.maxBytes {
        let old = url.appendingPathExtension("1")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: url, to: old)
      }
      if !fm.fileExists(atPath: url.path) {
        fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
      }
      guard let handle = try? FileHandle(forWritingTo: url) else { return }
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    }
  }
}
