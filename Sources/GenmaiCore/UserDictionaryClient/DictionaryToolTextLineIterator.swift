// Port of the file text line iterators in mozc/src/gui/dictionary_tool/dictionary_tool.cc
// (3.35.6354): UTF16TextLineIterator, MultiByteTextLineIterator and
// CreateTextLineIterator. They are the non-UI part of the dictionary tool's
// import path, so they live next to the importer for the SwiftUI tool.
//
// Differences from C++:
// - The Qt progress dialog is replaced by `position` / `size` (bytes) so the
//   UI can show progress itself.
// - UTF-16 is decoded without QTextStream: a BOM selects the byte order,
//   otherwise little-endian (Qt's host order on Apple silicon / x86) is used;
//   unpaired surrogates and a trailing odd byte become U+FFFD, as
//   QString::toStdString() does for unpaired surrogates.
// - MultiByteTextLineIterator: at end of file C++ `ifs->get(ch)` fails and
//   leaves `ch` unchanged (or uninitialized), which re-appends the previous
//   byte to a final line without a trailing newline. The Swift port stops at
//   EOF instead.

import GenmaiBase

/// Use QTextStream to read UTF16 text -- we can't use ifstream,
/// since ifstream cannot handle Wide character.
public final class UTF16TextLineIterator: TextLineIteratorInterface {
  private let units: [UInt16]
  private var pos = 0
  private let opened: Bool
  public let size: Int

  public init(_ filename: String) {
    if let bytes = try? FileUtil.getContentBytes(filename) {
      opened = true
      size = bytes.count
      units = UTF16TextLineIterator.decodeUnits(bytes)
    } else {
      GenmaiLog.error("Cannot open: \(filename)")
      opened = false
      size = 0
      units = []
    }
  }

  private static func decodeUnits(_ bytes: [UInt8]) -> [UInt16] {
    var bigEndian = false
    var start = 0
    if bytes.count >= 2 {
      if bytes[0] == 0xFF && bytes[1] == 0xFE {
        start = 2
      } else if bytes[0] == 0xFE && bytes[1] == 0xFF {
        bigEndian = true
        start = 2
      }
    }
    var result: [UInt16] = []
    result.reserveCapacity((bytes.count - start) / 2 + 1)
    var i = start
    while i + 1 < bytes.count {
      let a = UInt16(bytes[i])
      let b = UInt16(bytes[i + 1])
      result.append(bigEndian ? (a << 8 | b) : (b << 8 | a))
      i += 2
    }
    if i < bytes.count {
      result.append(0xFFFD)
    }
    return result
  }

  /// Approximate byte position (for progress display).
  public var position: Int { min(size, pos * 2) }

  public var isAvailable: Bool { opened }

  public func next() -> [UInt8]? {
    if pos >= units.count {
      return nil
    }

    // Can't use ReadLine as ReadLine doesn't support CR only text.
    var outputLine: [UInt16] = []
    while pos < units.count {
      let ch = units[pos]
      pos += 1
      if outputLine.isEmpty && ch == 0x0A {
        // no harm to skip empty line
        continue
      }
      if ch == 0x0A || ch == 0x0D {
        break
      } else {
        outputLine.append(ch)
      }
    }

    return Array(String(decoding: outputLine, as: UTF16.self).utf8)
  }

  public func reset() { pos = 0 }
}

public final class MultiByteTextLineIterator: TextLineIteratorInterface {
  public typealias EncodingType = UserDictionaryImporter.EncodingType

  private let encodingType: EncodingType
  private let data: [UInt8]
  private var pos = 0
  // std::ios state bits.
  private var fail: Bool
  private var eof = false
  private var firstLine = true
  public let size: Int

  public init(_ encodingType: EncodingType, _ filename: String) {
    self.encodingType = encodingType
    if let bytes = try? FileUtil.getContentBytes(filename) {
      data = bytes
      fail = false
    } else {
      data = []
      fail = true
    }
    size = data.count
  }

  private var good: Bool { !fail && !eof }

  /// Byte position (for progress display).
  public var position: Int { pos }

  public var isAvailable: Bool {
    // This means that neither failbit nor badbit is set.
    // TODO(yukawa): Consider to remove |ifs_->eof()|. Furthermore, we should
    // replace IsAvailable() with something easier to understand, e.g.,
    // Done() or HasNext().
    good || eof
  }

  public func next() -> [UInt8]? {
    if !good {
      return nil
    }

    // Can't use getline as getline doesn't support CR only text.
    var outputLine: [UInt8] = []
    while good {
      if pos >= data.count {
        eof = true
        fail = true
        break
      }
      let ch = data[pos]
      pos += 1
      if outputLine.isEmpty && ch == UInt8(ascii: "\n") {
        continue
      }
      if ch == UInt8(ascii: "\n") || ch == UInt8(ascii: "\r") {
        break
      } else {
        outputLine.append(ch)
      }
    }

    var line = outputLine

    // We can't use QTextCodec as QTextCodec is not enabled by default.
    // We won't enable it as it increases the binary size.
    if encodingType == .shiftJIS {
      line = EncodingUtil.sjisToUtf8Bytes(line)
    }

    // strip UTF8 BOM
    if firstLine && encodingType == .utf8 {
      line = Array(Util.stripUtf8Bom(line))
    }

    // Util::ChopReturns.
    while let last = line.last, last == UInt8(ascii: "\r") || last == UInt8(ascii: "\n") {
      line.removeLast()
    }

    firstLine = false
    return line
  }

  public func reset() {
    // Clear state bit (eofbit, failbit, badbit).
    fail = false
    eof = false
    pos = 0
    firstLine = true
  }
}

extension UserDictionaryImporter {
  /// CreateTextLineIterator in dictionary_tool.cc. Returns nil for an
  /// unsupported encoding.
  public static func createTextLineIterator(_ encodingType: EncodingType, _ filename: String)
    -> (any TextLineIteratorInterface)?
  {
    var encodingType = encodingType
    if encodingType == .encodingAutoDetect {
      encodingType = guessFileEncodingType(filename)
    }

    if encodingType == .numEncodings {
      GenmaiLog.error("GuessFileEncodingType() returns UNKNOWN encoding.")
      // set default encoding
      encodingType = .utf16
    }

    GenmaiLog.info("Setting Encoding to: \(encodingType.rawValue)")

    switch encodingType {
    case .utf8, .shiftJIS:
      return MultiByteTextLineIterator(encodingType, filename)
    case .utf16:
      return UTF16TextLineIterator(filename)
    default:
      return nil
    }
  }
}
