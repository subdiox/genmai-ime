// Port of mozc/src/composer/special_key.{h,cc} (3.35.6354).
//
// C++ namespace mozc::composer::internal.

import GenmaiBase

private struct Block {
  var openPos: Int
  var closePos: Int
}

// Use [U+F000, U+F8FF] to represent special keys (e.g. {!}, {abc}).
// The range of Unicode PUA is [U+E000, U+F8FF], and we use them from U+F000.
// * The range of [U+E000, U+F000) is used for user defined PUA characters.
// * The users can still use [U+F000, U+F8FF] for their user dictionary.
//   but, they should not use them for composing rules.
private let kSpecialKeyBegin: Char32 = 0xF000
private let kSpecialKeyEnd: Char32 = 0xF8FF

// U+000F and U+000E are used as fallback for special keys that are not
// registered in the table. "{abc}" is converted to "\u000Fabc\u000E".
private let kSpecialKeyOpen = "\u{000F}"  // Shift-In of ASCII (1 byte)
private let kSpecialKeyClose = "\u{000E}"  // Shift-Out of ASCII (1 byte)

private func isSpecialKey(_ c: Char32) -> Bool {
  kSpecialKeyBegin <= c && c <= kSpecialKeyEnd
}

private func findBlock(_ input: some StringProtocol, _ open: String, _ close: String) -> Block? {
  guard let openPos = ComposerBytes.find(input, open) else {
    return nil
  }
  guard let closePos = ComposerBytes.find(input, close, from: openPos) else {
    return nil
  }
  return Block(openPos: openPos, closePos: closePos)
}

private func parseBlock(_ inputString: some StringProtocol, _ callback: (Substring) -> String) -> String {
  var input = Substring(inputString)
  var output = ""
  while !input.isEmpty {
    guard let block = findBlock(input, "{", "}") else {
      output += input
      break
    }

    output += input.byteSubstring(from: 0, length: block.openPos)

    // The both sizes of "{" and "}" is 1.
    let key = input.byteSubstring(from: block.openPos + 1, length: block.closePos - block.openPos - 1)
    if key == "{" {
      // "{{}" is treated as "{".
      output += "{"
    } else {
      output += callback(key)
    }
    input = input.byteSubstring(from: block.closePos + 1)
  }
  return output
}

/// composer::internal::SpecialKeyMap.
public struct SpecialKeyMap: Sendable {
  private var map: [String: String] = [:]

  public init() {}

  /// Parses special key strings escaped with the pair of "{" and "}"" and
  /// registers them to be used by Parse(). Also returns the parsed string.
  public mutating func register(_ input: some StringProtocol) -> String {
    var map = self.map
    let result = parseBlock(input) { key in
      if let existing = map[String(key)] {
        return existing  // existing entry
      }
      var keycode = kSpecialKeyBegin + Char32(map.count)
      if keycode > kSpecialKeyEnd {
        // 2304 (0x900 = [Begin, End]) is the max size of special keys.
        keycode = kSpecialKeyEnd
        GenmaiLog.warning("The size of special keys exceeded: \(key)")
      }
      // New special key is replaced with a Unicode PUA and registered.
      let specialKey = Util.codepointToUtf8(keycode)
      map[String(key)] = specialKey
      return specialKey
    }
    self.map = map
    return result
  }

  /// Parses special key strings escaped with the pair of "{" and "}" and returns
  /// the parsed string.
  public func parse(_ input: some StringProtocol) -> String {
    parseBlock(input) { key in
      if let existing = map[String(key)] {
        return existing  // existing entry
      }
      // Unregistered key is replaced with the fallback format.
      return kSpecialKeyOpen + key + kSpecialKeyClose
    }
  }
}

/// Trims a special key from input and returns the rest.
/// If the input doesn't have any special keys at the beginning, it returns the
/// entire string.
public func trimLeadingSpecialKey(_ input: Substring) -> Substring {
  // Check if the first character is a Unicode PUA converted from a special key.
  if let (firstChar, rest) = Util.splitFirstChar32(input), isSpecialKey(firstChar) {
    return input.byteSubstring(from: input.utf8.count - rest.utf8.count)
  }

  // Check if the input starts from open and close of a special key.
  if !input.hasBytePrefix(kSpecialKeyOpen) {
    return input
  }
  guard let closePos = ComposerBytes.find(input, kSpecialKeyClose, from: 1) else {
    return input
  }
  return input.byteSubstring(from: closePos + 1)
}

public func trimLeadingSpecialKey(_ input: String) -> Substring {
  trimLeadingSpecialKey(input[...])
}

/// Deletes invisible special keys wrapped with ("\x0F", "\x0E") and returns the
/// trimmed visible string.
public func deleteSpecialKeys(_ inputString: some StringProtocol) -> String {
  var input = Substring(inputString)
  var output = ""
  while !input.isEmpty {
    guard let block = findBlock(input, kSpecialKeyOpen, kSpecialKeyClose) else {
      output += input
      break
    }

    output += input.byteSubstring(from: 0, length: block.openPos)
    // The size of kSpecialKeyClose is 1.
    input = input.byteSubstring(from: block.closePos + 1)
  }

  // Delete Unicode PUA characters converted from special keys.
  if !output.unicodeScalars.contains(where: { isSpecialKey($0.value) }) {
    return output
  }
  var result = String.UnicodeScalarView()
  for scalar in output.unicodeScalars where !isSpecialKey(scalar.value) {
    result.append(scalar)
  }
  return String(result)
}
