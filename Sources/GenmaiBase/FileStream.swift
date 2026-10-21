// Port of mozc/src/base/file_stream.{h,cc} (3.35.6354).
//
// The C++ classes derive from std::ifstream / std::ofstream. The Swift
// versions provide the subset of the stream API Mozc uses: std::getline-style
// line reading, bulk reads, and writes. InputFileStream can also be backed by
// in-memory bytes (std::istringstream), which ConfigFileStream uses.
// On macOS there is no difference between text and binary mode.

#if canImport(Darwin)
import Darwin
#endif

public final class InputFileStream {
  private var data: [UInt8]
  private var pos = 0
  /// failbit (the file could not be opened, or a read hit EOF).
  public private(set) var fail: Bool
  /// eofbit.
  public private(set) var eof = false

  /// Opens the specified file (failing state if it cannot be read).
  public init(_ filename: String) {
    if let bytes = try? FileUtil.getContentBytes(filename) {
      data = bytes
      fail = false
    } else {
      data = []
      fail = true
    }
  }

  /// In-memory stream (std::istringstream).
  public init(bytes: [UInt8]) {
    data = bytes
    fail = false
  }

  public convenience init(string: String) {
    self.init(bytes: Array(string.utf8))
  }

  /// !fail && !eof.
  public var good: Bool { !fail && !eof }

  /// std::getline(stream, line, delim). Returns nil (and sets fail) when no
  /// character could be extracted. The delimiter is consumed but not stored.
  public func getlineBytes(_ delim: UInt8 = UInt8(ascii: "\n")) -> ArraySlice<UInt8>? {
    if fail { return nil }
    if pos >= data.count {
      eof = true
      fail = true
      return nil
    }
    let start = pos
    while pos < data.count {
      if data[pos] == delim {
        let line = data[start..<pos]
        pos += 1
        return line
      }
      pos += 1
    }
    eof = true
    return data[start..<pos]
  }

  /// std::getline returning a String (invalid UTF-8 is replaced).
  public func getline(_ delim: UInt8 = UInt8(ascii: "\n")) -> String? {
    guard let bytes = getlineBytes(delim) else { return nil }
    return String(decoding: bytes, as: UTF8.self)
  }

  /// istream::read. Returns up to `count` bytes; sets eof/fail if fewer were
  /// available.
  public func read(_ count: Int) -> ArraySlice<UInt8> {
    if fail { return [] }
    let n = min(count, data.count - pos)
    let result = data[pos..<pos + n]
    pos += n
    if n < count {
      eof = true
      fail = true
    }
    return result
  }

  /// istream::peek. Returns nil (traits_type::eof()) at the end and sets eof.
  public func peek() -> UInt8? {
    if fail { return nil }
    if pos >= data.count {
      eof = true
      return nil
    }
    return data[pos]
  }

  /// istream::get. Returns nil at the end and sets eof and fail.
  public func get() -> UInt8? {
    if fail { return nil }
    if pos >= data.count {
      eof = true
      fail = true
      return nil
    }
    pos += 1
    return data[pos - 1]
  }

  /// Reads everything that remains (`ss << ifs.rdbuf()`).
  public func readAll() -> [UInt8] {
    if fail { return [] }
    let result = Array(data[pos...])
    pos = data.count
    return result
  }

  /// Reads everything that remains as a String.
  public func readAllString() -> String {
    String(decoding: readAll(), as: UTF8.self)
  }

  /// Iterates the remaining lines (std::getline loop).
  public func lines() -> [String] {
    var result: [String] = []
    while let line = getline() {
      result.append(line)
    }
    return result
  }
}

public final class OutputFileStream {
  public enum Mode: Sendable {
    /// std::ios::out (| std::ios::trunc): truncates the file.
    case truncate
    /// std::ios::app.
    case append
  }

  private var fp: UnsafeMutablePointer<FILE>?
  public private(set) var fail: Bool

  public init(_ filename: String, _ mode: Mode = .truncate) {
    fp = fopen(filename, mode == .append ? "ab" : "wb")
    fail = fp == nil
  }

  deinit {
    if let fp { fclose(fp) }
  }

  public var good: Bool { !fail }

  public func write(_ bytes: some Collection<UInt8>) {
    guard let fp, !fail else {
      fail = true
      return
    }
    let array = Array(bytes)
    if array.isEmpty { return }
    if fwrite(array, 1, array.count, fp) != array.count {
      fail = true
    }
  }

  /// `ofs << str`.
  public func write(_ string: String) {
    write(Array(string.utf8))
  }

  /// `ofs << str << std::endl`.
  public func writeLine(_ string: String) {
    write(string)
    write("\n")
    flush()
  }

  public func flush() {
    if let fp { fflush(fp) }
  }

  public func close() {
    if let fp {
      if fclose(fp) != 0 { fail = true }
    }
    fp = nil
  }
}
