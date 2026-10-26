// Settings of the iOS keyboard (not part of Mozc), like `AIConversionSettings`: a small JSON file in the user
// profile directory (`keyboard.json`), written by the Genmai app and read by the keyboard extension when it
// appears.

import Foundation
import GenmaiBase

public struct KeyboardSettings: Codable, Equatable, Sendable {
  public var kanaLayout: KanaLayout
  /// 12 keys: flicks only, repeated taps do not toggle (the *_FLICKONLY tables).
  public var flickOnly: Bool
  /// 12 keys: the alphabet keyboard is QWERTY (12KEYS_QWERTY).
  public var qwertyAlphabet: Bool
  /// Haptic feedback on key presses.
  public var haptics: Bool

  public init(
    kanaLayout: KanaLayout = .twelveKeys, flickOnly: Bool = false, qwertyAlphabet: Bool = false,
    haptics: Bool = true
  ) {
    self.kanaLayout = kanaLayout
    self.flickOnly = flickOnly
    self.qwertyAlphabet = qwertyAlphabet
    self.haptics = haptics
  }

  enum CodingKeys: String, CodingKey {
    case kanaLayout = "kana_layout"
    case flickOnly = "flick_only"
    case qwertyAlphabet = "qwerty_alphabet"
    case haptics
  }

  public init(from decoder: any Decoder) throws {
    // Every field is optional so that files written by older / newer versions still load.
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    kanaLayout = (try? c.decodeIfPresent(KanaLayout.self, forKey: .kanaLayout)) ?? kanaLayout
    flickOnly = try c.decodeIfPresent(Bool.self, forKey: .flickOnly) ?? flickOnly
    qwertyAlphabet = try c.decodeIfPresent(Bool.self, forKey: .qwertyAlphabet) ?? qwertyAlphabet
    haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? haptics
  }

  /// The layout name for `IosEngine.setMobileRequest`.
  public var engineLayoutName: String {
    kanaLayout.engineLayoutName(flickOnly: flickOnly, qwertyAlphabet: qwertyAlphabet)
  }

  /// Whether the alphabet and number keys are QWERTY.
  public var usesQwertyForAlphabet: Bool { kanaLayout == .qwerty || qwertyAlphabet }

  // MARK: - Persistence

  public static let fileName = "keyboard.json"

  /// `<user profile>/keyboard.json`.
  public static var fileURL: URL {
    URL(filePath: SystemUtil.getUserProfileDirectory(), directoryHint: .isDirectory).appending(path: fileName)
  }

  /// Loads the settings; defaults if the file is missing or unreadable.
  public static func load(from url: URL = KeyboardSettings.fileURL) -> KeyboardSettings {
    guard let data = try? Data(contentsOf: url) else {
      return KeyboardSettings()
    }
    do {
      return try JSONDecoder().decode(KeyboardSettings.self, from: data)
    } catch {
      GenmaiLog.warning("Ignoring unreadable \(url.path): \(error)")
      return KeyboardSettings()
    }
  }

  /// Writes the settings atomically.
  public func save(to url: URL = KeyboardSettings.fileURL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
