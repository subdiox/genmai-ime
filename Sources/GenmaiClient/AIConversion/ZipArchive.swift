// Extracts zip archives (not part of Mozc): the model release's `model-coreml.zip`. Foundation has no zip API and an
// iOS app cannot run `ditto`, so the archive is read here: the central directory gives each file's name, method,
// sizes and local header; stored files are copied and deflated ones inflated with the Compression framework (its
// `zlib` algorithm is raw DEFLATE, as in zip). Zip64, encryption and other methods are not supported (the archives
// are written by Tools/coreml/genmai_coreml.py with Python's zipfile). The CRCs are not checked: the installer
// verifies the whole archive's SHA-256 first.

import Compression
import Foundation

public enum ZipArchive {
  public enum Failure: Error, Equatable, CustomStringConvertible {
    case notAZip
    case unsupported(String)
    case damaged(String)

    public var description: String {
      switch self {
      case .notAZip: "not a zip archive"
      case .unsupported(let what): "unsupported zip archive: \(what)"
      case .damaged(let what): "damaged zip archive: \(what)"
      }
    }
  }

  struct Entry {
    var name: String
    var method: UInt16
    var compressedSize: Int
    var size: Int
    var localHeaderOffset: Int
  }

  /// Extracts every file of `archive` into `directory` (created if needed). Paths stay inside `directory`.
  public static func extract(_ archive: URL, to directory: URL) throws {
    let data = try Data(contentsOf: archive, options: .alwaysMapped)
    let fm = FileManager.default
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    for entry in try entries(data) where !entry.name.hasSuffix("/") {
      let parts = entry.name.split(separator: "/", omittingEmptySubsequences: true)
      guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." }), !entry.name.hasPrefix("/") else {
        throw Failure.damaged("bad path \(entry.name)")
      }
      let destination = parts.reduce(directory) { $0.appending(path: String($1)) }
      try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try write(entry, of: data, to: destination)
    }
  }

  /// The entries of the central directory.
  static func entries(_ data: Data) throws -> [Entry] {
    // the end of central directory record: signature 0x06054b50, within the last 64 KiB + 22 bytes
    let minimum = 22
    guard data.count >= minimum else { throw Failure.notAZip }
    var end = data.count - minimum
    let earliest = max(0, data.count - minimum - 0xFFFF)
    while end >= earliest, u32(data, end) != 0x0605_4B50 { end -= 1 }
    guard end >= earliest else { throw Failure.notAZip }
    let count = Int(u16(data, end + 10))
    let directorySize = Int(u32(data, end + 12))
    let directoryOffset = Int(u32(data, end + 16))
    guard directoryOffset != 0xFFFF_FFFF, count != 0xFFFF else { throw Failure.unsupported("zip64") }
    guard directoryOffset + directorySize <= end else { throw Failure.damaged("central directory") }
    var entries: [Entry] = []
    var at = directoryOffset
    for _ in 0..<count {
      guard at + 46 <= end, u32(data, at) == 0x0201_4B50 else { throw Failure.damaged("central directory entry") }
      let flags = u16(data, at + 8)
      guard flags & 1 == 0 else { throw Failure.unsupported("encryption") }
      let nameLength = Int(u16(data, at + 28))
      let extraLength = Int(u16(data, at + 30))
      let commentLength = Int(u16(data, at + 32))
      guard at + 46 + nameLength <= end else { throw Failure.damaged("file name") }
      let name = String(
        decoding: data[(data.startIndex + at + 46)..<(data.startIndex + at + 46 + nameLength)], as: UTF8.self)
      entries.append(
        Entry(
          name: name, method: u16(data, at + 10), compressedSize: Int(u32(data, at + 20)),
          size: Int(u32(data, at + 24)),
          localHeaderOffset: Int(u32(data, at + 42))))
      at += 46 + nameLength + extraLength + commentLength
    }
    return entries
  }

  private static func write(_ entry: Entry, of data: Data, to destination: URL) throws {
    let header = entry.localHeaderOffset
    guard header + 30 <= data.count, u32(data, header) == 0x0403_4B50 else { throw Failure.damaged(entry.name) }
    let start = header + 30 + Int(u16(data, header + 26)) + Int(u16(data, header + 28))
    guard start + entry.compressedSize <= data.count else { throw Failure.damaged(entry.name) }
    let compressed = data[(data.startIndex + start)..<(data.startIndex + start + entry.compressedSize)]
    FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil)
    let handle = try FileHandle(forWritingTo: destination)
    defer { try? handle.close() }
    var written = 0
    switch entry.method {
    case 0:
      try handle.write(contentsOf: compressed)
      written = compressed.count
    case 8:
      let filter = try OutputFilter(.decompress, using: .zlib) { chunk in
        guard let chunk else { return }
        try handle.write(contentsOf: chunk)
        written += chunk.count
      }
      let step = 1 << 20
      var offset = compressed.startIndex
      while offset < compressed.endIndex {
        let next = min(offset + step, compressed.endIndex)
        try filter.write(compressed[offset..<next])
        offset = next
      }
      try filter.finalize()
    default:
      throw Failure.unsupported("compression method \(entry.method) of \(entry.name)")
    }
    guard written == entry.size else { throw Failure.damaged(entry.name) }
  }

  private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[data.startIndex + offset]) | UInt16(data[data.startIndex + offset + 1]) << 8
  }

  private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(u16(data, offset)) | UInt32(u16(data, offset + 2)) << 16
  }
}
