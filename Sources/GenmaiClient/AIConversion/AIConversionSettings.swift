// AI conversion settings (not part of Mozc).
//
// Stored as a small JSON file in the user profile directory (`ai_conversion.json`, next to config1.db), so the
// Mozc Config proto and config1.db stay byte-compatible with Mozc. GenmaiTool's config dialog writes the file
// before it sends SET_CONFIG; the IME re-reads it when it receives the reload notification.

import Foundation
import GenmaiBase

public struct AIConversionSettings: Codable, Equatable, Sendable {
  /// AI conversion is off by default: the IME then behaves exactly like Mozc.
  public var enabled: Bool
  /// How long the conversion key waits for the AI result before falling back to Mozc's candidates.
  public var timeoutMilliseconds: Int
  /// Maximum number of AI candidates (the AI top-1 plus alternatives) added to a segment's candidate list.
  public var candidateCount: Int
  /// The model directory; nil = `defaultModelDirectory`.
  public var modelDirectory: String?
  /// Appends one line per AI conversion event to `<profile>/ai_debug.log` (`AIConversionDebugLog`). Off by
  /// default: the log contains the typed text and its left context.
  public var debugLog: Bool

  public static let defaultTimeoutMilliseconds = 300
  public static let defaultCandidateCount = 5
  public static let timeoutRange = 50...5000
  public static let candidateCountRange = 1...10

  public init(
    enabled: Bool = false, timeoutMilliseconds: Int = AIConversionSettings.defaultTimeoutMilliseconds,
    candidateCount: Int = AIConversionSettings.defaultCandidateCount, modelDirectory: String? = nil,
    debugLog: Bool = false
  ) {
    self.enabled = enabled
    self.timeoutMilliseconds = timeoutMilliseconds
    self.candidateCount = candidateCount
    self.modelDirectory = modelDirectory
    self.debugLog = debugLog
  }

  enum CodingKeys: String, CodingKey {
    case enabled
    case timeoutMilliseconds = "timeout_ms"
    case candidateCount = "candidates"
    case modelDirectory = "model_directory"
    case debugLog = "debug_log"
  }

  public init(from decoder: any Decoder) throws {
    // Every field is optional so that files written by older / newer versions still load.
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
    timeoutMilliseconds = try c.decodeIfPresent(Int.self, forKey: .timeoutMilliseconds) ?? timeoutMilliseconds
    candidateCount = try c.decodeIfPresent(Int.self, forKey: .candidateCount) ?? candidateCount
    modelDirectory = try c.decodeIfPresent(String.self, forKey: .modelDirectory)
    if modelDirectory?.isEmpty == true {
      modelDirectory = nil
    }
    debugLog = try c.decodeIfPresent(Bool.self, forKey: .debugLog) ?? debugLog
  }

  /// The values clamped to their valid ranges.
  public var sanitized: AIConversionSettings {
    var s = self
    s.timeoutMilliseconds = min(max(s.timeoutMilliseconds, Self.timeoutRange.lowerBound), Self.timeoutRange.upperBound)
    s.candidateCount = min(max(s.candidateCount, Self.candidateCountRange.lowerBound), Self.candidateCountRange.upperBound)
    return s
  }

  public var timeout: Duration { .milliseconds(sanitized.timeoutMilliseconds) }

  // MARK: - Model location

  /// `~/Library/Application Support/Genmai/model`, written by Tools/prepare_genmai_model.sh
  /// (the same path as GenmaiAI's `GenmaiConverter.defaultModelDirectory`).
  public static var defaultModelDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "Genmai/model", directoryHint: .isDirectory)
  }

  public var resolvedModelDirectory: URL {
    if let modelDirectory {
      return URL(filePath: (modelDirectory as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }
    return Self.defaultModelDirectory
  }

  // MARK: - Persistence

  public static let fileName = "ai_conversion.json"

  /// `<user profile>/ai_conversion.json`.
  public static var fileURL: URL {
    URL(filePath: SystemUtil.getUserProfileDirectory(), directoryHint: .isDirectory).appending(path: fileName)
  }

  /// Loads the settings; defaults if the file is missing or unreadable.
  public static func load(from url: URL = AIConversionSettings.fileURL) -> AIConversionSettings {
    guard let data = try? Data(contentsOf: url) else {
      return AIConversionSettings()
    }
    do {
      return try JSONDecoder().decode(AIConversionSettings.self, from: data).sanitized
    } catch {
      GenmaiLog.warning("Ignoring unreadable \(url.path): \(error)")
      return AIConversionSettings()
    }
  }

  /// Writes the settings atomically.
  public func save(to url: URL = AIConversionSettings.fileURL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(sanitized).write(to: url, options: .atomic)
  }
}

/// Whether the model files are present (checked without loading the model, so GenmaiTool does not need MLX).
public enum AIModelStatus: Equatable, Sendable {
  case found(URL)
  case missing(URL, missingFiles: [String])

  /// The files Tools/prepare_genmai_model.sh writes.
  public static let requiredFiles = ["config.json", "tokenizer.json", "model.safetensors"]

  public static func check(_ directory: URL) -> AIModelStatus {
    let missing = requiredFiles.filter {
      !FileManager.default.fileExists(atPath: directory.appending(path: $0).path)
    }
    return missing.isEmpty ? .found(directory) : .missing(directory, missingFiles: missing)
  }

  public var isFound: Bool {
    if case .found = self { return true }
    return false
  }
}
