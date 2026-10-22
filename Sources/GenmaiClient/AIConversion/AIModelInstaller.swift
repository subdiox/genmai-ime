// Download and installation of the genmai model (not part of Mozc).
//
// The model is not bundled with the IME. The config dialog (GenmaiTool) and `genmai-cli install` download a
// pinned release from Hugging Face (fp32 safetensors, checked against its sha256), convert it to the compact
// runtime layout that GenmaiAI loads (bf16, Conv1D weights transposed to (out, in), metadata
// format=genmai-bf16-out-in; ~0.6 GB) and install it into the model directory together with config.json,
// tokenizer.json and `genmai_model.json` (which release is installed). The conversion is plain Swift (GenmaiTool
// does not link MLX); it produces the same bits as MLX's `astype(bfloat16)` (round to nearest even).

import CryptoKit
import Foundation
import Synchronization

/// Which model release is installed (`genmai_model.json` in the model directory).
public struct GenmaiModelInfo: Codable, Equatable, Sendable {
  public var version: String
  public var repository: String
  public var revision: String

  public init(version: String, repository: String, revision: String) {
    self.version = version
    self.repository = repository
    self.revision = revision
  }

  public static let fileName = "genmai_model.json"

  /// The info of the model in `directory`; nil when it was not installed from a release (e.g. by
  /// `genmai-cli prepare`, or by an older version of the IME).
  public static func load(from directory: URL) -> GenmaiModelInfo? {
    guard let data = try? Data(contentsOf: directory.appending(path: fileName)) else { return nil }
    return try? JSONDecoder().decode(GenmaiModelInfo.self, from: data)
  }

  public func save(to directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(self).write(to: directory.appending(path: Self.fileName), options: .atomic)
  }
}

/// A model release on Hugging Face, with the files to download and their checksums.
public struct GenmaiModelRelease: Equatable, Sendable {
  public struct File: Equatable, Sendable {
    public var name: String
    public var size: Int64
    public var sha256: String
  }

  public var info: GenmaiModelInfo
  public var files: [File]

  /// The release the IME uses.
  public static let current = GenmaiModelRelease(
    info: GenmaiModelInfo(version: "0.2.0", repository: "subdiox/genmai", revision: "v0.2.0"),
    files: [
      File(name: "config.json", size: 921, sha256: "40876bb2ca094f67e9580d3949260ec5f602a8bf5f523587e7448c91da6a1838"),
      File(name: "tokenizer.json", size: 394_106, sha256: "5f47a842d17ec6211bf243fc2f32b6ee12c9cbc00e68f9bbfdfd550b584c1838"),
      File(
        name: "model.safetensors", size: 1_238_046_208,
        sha256: "e1ac64258359389b0451bdc521593cba825635baa08b2650a1140678a01396f6"),
    ])

  public var downloadSize: Int64 { files.reduce(0) { $0 + $1.size } }

  public func url(of file: File) -> URL {
    URL(string: "https://huggingface.co/\(info.repository)/resolve/\(info.revision)/\(file.name)")!
  }
}

public enum AIModelInstallError: Error, Equatable, CustomStringConvertible {
  case download(String, status: Int)
  case checksum(String)
  case badModel(String)

  public var description: String {
    switch self {
    case .download(let file, let status): "downloading \(file) failed (HTTP \(status))"
    case .checksum(let file): "\(file) is damaged (checksum mismatch)"
    case .badModel(let message): "unsupported model file: \(message)"
    }
  }
}

public enum AIModelInstaller {
  public enum Phase: Equatable, Sendable {
    case downloading(received: Int64, total: Int64)
    case verifying
    case converting
  }

  /// Downloaded files are kept here until the installation succeeded (an interrupted installation reuses the
  /// files that were complete).
  public static var cacheDirectory: URL {
    URL.cachesDirectory.appending(path: "Genmai/download", directoryHint: .isDirectory)
  }

  /// Downloads `release`, converts it and installs it into `directory`. Only the model's own files in
  /// `directory` are replaced (each one atomically); other files are left alone. Honors task cancellation.
  public static func install(
    _ release: GenmaiModelRelease = .current, to directory: URL, cacheDirectory: URL = AIModelInstaller.cacheDirectory,
    progress: @escaping @Sendable (Phase) -> Void = { _ in }
  ) async throws {
    let fm = FileManager.default
    let downloads = cacheDirectory.appending(path: release.info.revision, directoryHint: .isDirectory)
    try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
    let total = release.downloadSize
    var done: Int64 = 0
    for file in release.files {
      let local = downloads.appending(path: file.name)
      if !isComplete(local, file) {
        try? fm.removeItem(at: local)
        let base = done
        try await download(release.url(of: file), to: local, name: file.name) { received in
          progress(.downloading(received: base + received, total: total))
        }
      }
      done += file.size
      progress(.downloading(received: done, total: total))
    }
    progress(.verifying)
    for file in release.files {
      let local = downloads.appending(path: file.name)
      guard try await sha256(of: local) == file.sha256 else {
        try? fm.removeItem(at: local)
        throw AIModelInstallError.checksum(file.name)
      }
    }
    try Task.checkCancellation()
    progress(.converting)
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let staging = directory.appending(path: ".install-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fm.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: staging) }
    try await convertInBackground(source: downloads.appending(path: "model.safetensors"),
      destination: staging.appending(path: "model.safetensors"))
    for name in ["config.json", "tokenizer.json"] {
      try fm.copyItem(at: downloads.appending(path: name), to: staging.appending(path: name))
    }
    try release.info.save(to: staging)
    try Task.checkCancellation()
    // The weights last: a directory with the new weights always has the matching config and tokenizer.
    for name in ["config.json", "tokenizer.json", "model.safetensors", GenmaiModelInfo.fileName] {
      try replace(directory.appending(path: name), with: staging.appending(path: name))
    }
    // Written by earlier versions; the prompt format is now in config.json.
    try? fm.removeItem(at: directory.appending(path: "genmai_fmt.txt"))
    try? fm.removeItem(at: downloads)
  }

  /// Writes the runtime model file for the HF safetensors file `source` (see `GenmaiSafetensors.prepare`) and copies
  /// config.json and tokenizer.json next to it, without a `genmai_model.json` (`genmai-cli prepare`).
  public static func prepare(source: URL, destination: URL) async throws {
    let fm = FileManager.default
    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
    let tmp = destination.appending(path: ".model.tmp.safetensors")
    defer { try? fm.removeItem(at: tmp) }
    try await convertInBackground(source: source.appending(path: "model.safetensors"), destination: tmp)
    try replace(destination.appending(path: "model.safetensors"), with: tmp)
    for name in ["config.json", "tokenizer.json"] {
      let copy = destination.appending(path: ".\(name).tmp")
      try? fm.removeItem(at: copy)
      try fm.copyItem(at: source.appending(path: name), to: copy)
      try replace(destination.appending(path: name), with: copy)
    }
    try? fm.removeItem(at: destination.appending(path: GenmaiModelInfo.fileName))
    try? fm.removeItem(at: destination.appending(path: "genmai_fmt.txt"))
  }

  @concurrent
  private static func convertInBackground(source: URL, destination: URL) async throws {
    try GenmaiSafetensors.prepare(source: source, destination: destination)
  }

  private static func replace(_ target: URL, with source: URL) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: target.path) {
      _ = try fm.replaceItemAt(target, withItemAt: source)
    } else {
      try fm.moveItem(at: source, to: target)
    }
  }

  private static func isComplete(_ url: URL, _ file: GenmaiModelRelease.File) -> Bool {
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
    return size == file.size
  }

  private static func download(
    _ url: URL, to destination: URL, name: String, progress: @escaping @Sendable (Int64) -> Void
  ) async throws {
    let downloader = Downloader(destination: destination, name: name, progress: progress)
    let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let task = session.downloadTask(with: url)
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        downloader.continuation.withLock { $0 = continuation }
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
  }

  /// The session delegate of one download: reports the bytes received and moves the finished file into place.
  /// (The task delegate of `URLSession.download(from:delegate:)` gets no progress callbacks.)
  private final class Downloader: NSObject, URLSessionDownloadDelegate, Sendable {
    let destination: URL
    let name: String
    let progress: @Sendable (Int64) -> Void
    let continuation = Mutex<CheckedContinuation<Void, any Error>?>(nil)
    /// Set when the file arrived but could not be used (HTTP error, move failed).
    let failure = Mutex<(any Error)?>(nil)

    init(destination: URL, name: String, progress: @escaping @Sendable (Int64) -> Void) {
      self.destination = destination
      self.name = name
      self.progress = progress
    }

    func urlSession(
      _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
      totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
      progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
      // The file is deleted when this returns.
      let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
      do {
        guard status == 200 else { throw AIModelInstallError.download(name, status: status) }
        try FileManager.default.moveItem(at: location, to: destination)
      } catch {
        failure.withLock { $0 = error }
      }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
      let result = error ?? failure.withLock { $0 }
      guard let continuation = continuation.withLock({ c in defer { c = nil }; return c }) else { return }
      if let result {
        continuation.resume(throwing: (result as? URLError)?.code == .cancelled ? CancellationError() : result)
      } else {
        continuation.resume()
      }
    }
  }

  @concurrent
  static func sha256(of url: URL) async throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
      try Task.checkCancellation()
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

/// Conversion of the HF GPT-2 weights to the runtime layout of GenmaiAI.
public enum GenmaiSafetensors {
  /// Metadata `format` of the converted file (`GenmaiModel.preparedFormat` in GenmaiAI).
  public static let preparedFormat = "genmai-bf16-out-in"

  /// Reads the HF safetensors file `source` (F32, F16 or BF16) and writes `destination`: every tensor in bf16
  /// (round to nearest even), keys without the `transformer.` prefix, `lm_head.weight` (tied to `wte`) dropped,
  /// the Conv1D weights (`c_attn`, `c_proj`, `c_fc`; HF stores them as (in, out)) transposed to (out, in).
  public static func prepare(source: URL, destination: URL) throws {
    let data = try Data(contentsOf: source, options: .alwaysMapped)
    guard data.count >= 8 else { throw AIModelInstallError.badModel("file too short") }
    let headerLength = data.withUnsafeBytes { Int($0.loadUnaligned(as: UInt64.self).littleEndian) }
    guard 8 + headerLength <= data.count,
      let header = try JSONSerialization.jsonObject(with: data[8..<(8 + headerLength)]) as? [String: Any]
    else {
      throw AIModelInstallError.badModel("bad header")
    }
    let base = 8 + headerLength

    struct Tensor {
      var name: String
      var dtype: String
      var shape: [Int]
      var begin: Int
      var end: Int
      var transpose: Bool
      var count: Int { shape.reduce(1, *) }
    }
    var tensors: [Tensor] = []
    for (key, value) in header where key != "__metadata__" {
      guard let entry = value as? [String: Any], let dtype = entry["dtype"] as? String,
        let shape = entry["shape"] as? [Int], let offsets = entry["data_offsets"] as? [Int], offsets.count == 2
      else {
        throw AIModelInstallError.badModel("bad entry \(key)")
      }
      let name = key.hasPrefix("transformer.") ? String(key.dropFirst("transformer.".count)) : key
      if name == "lm_head.weight" { continue }
      let transpose =
        name.hasSuffix("c_attn.weight") || name.hasSuffix("c_proj.weight") || name.hasSuffix("c_fc.weight")
      guard ["F32", "F16", "BF16"].contains(dtype), !transpose || shape.count == 2 else {
        throw AIModelInstallError.badModel("\(key): \(dtype) \(shape)")
      }
      let t = Tensor(name: name, dtype: dtype, shape: transpose ? [shape[1], shape[0]] : shape,
        begin: base + offsets[0], end: base + offsets[1], transpose: transpose)
      guard t.end <= data.count, t.end - t.begin == t.count * (dtype == "F32" ? 4 : 2) else {
        throw AIModelInstallError.badModel("\(key): bad data offsets")
      }
      tensors.append(t)
    }
    tensors.sort { $0.name < $1.name }

    var outHeader: [String: Any] = ["__metadata__": ["format": preparedFormat]]
    var offset = 0
    for t in tensors {
      outHeader[t.name] = ["dtype": "BF16", "shape": t.shape, "data_offsets": [offset, offset + t.count * 2]]
      offset += t.count * 2
    }
    var headerData = try JSONSerialization.data(withJSONObject: outHeader, options: [.sortedKeys, .withoutEscapingSlashes])
    headerData.append(contentsOf: [UInt8](repeating: 0x20, count: (8 - headerData.count % 8) % 8))

    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let out = try FileHandle(forWritingTo: destination)
    defer { try? out.close() }
    var length = UInt64(headerData.count).littleEndian
    try out.write(contentsOf: Data(bytes: &length, count: 8))
    try out.write(contentsOf: headerData)
    try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      for t in tensors {
        let input = UnsafeRawBufferPointer(rebasing: raw[t.begin..<t.end])
        var bf16 = [UInt16](repeating: 0, count: t.count)
        let rows = t.transpose ? t.shape[1] : 1  // the source's row count ("in")
        let columns = t.transpose ? t.shape[0] : t.count
        bf16.withUnsafeMutableBufferPointer { dst in
          for i in 0..<t.count {
            let value: UInt16
            switch t.dtype {
            case "F32":
              value = bfloat16(input.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self).littleEndian)
            case "F16":
              let half = Float16(bitPattern: input.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self).littleEndian)
              value = bfloat16(Float(half).bitPattern)
            default:
              value = input.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self).littleEndian
            }
            // source (r, c) of (rows, columns) → destination (c, r)
            let j = t.transpose ? (i % columns) * rows + i / columns : i
            dst[j] = value.littleEndian
          }
        }
        try bf16.withUnsafeBytes { try out.write(contentsOf: Data($0)) }
      }
    }
  }

  /// float32 bits → bfloat16 bits, rounding to nearest even (as MLX and PyTorch do); NaN stays NaN.
  static func bfloat16(_ bits: UInt32) -> UInt16 {
    if bits & 0x7FFF_FFFF > 0x7F80_0000 {
      return UInt16(truncatingIfNeeded: bits >> 16) | 0x0040
    }
    let rounding = 0x7FFF + ((bits >> 16) & 1)
    return UInt16(truncatingIfNeeded: (bits &+ rounding) >> 16)
  }
}
