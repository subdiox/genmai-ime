// Download and installation of the genmai model (not part of Mozc).
//
// The model is not bundled with the IME. The config dialog (GenmaiTool) and `genmai-cli install` look up the newest
// release on Hugging Face (`GenmaiModelRelease.latest`: the highest vX.Y.Z tag whose config.json this IME can run),
// download it (fp32 safetensors; every file checked against the checksum Hugging Face lists), convert it to the compact
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

/// A model release on Hugging Face (a vX.Y.Z tag of the model repository), with the files to download and their
/// checksums, as listed by the Hugging Face API.
public struct GenmaiModelRelease: Equatable, Sendable {
  public struct File: Equatable, Sendable {
    public enum Checksum: Equatable, Sendable {
      /// LFS files: sha256 of the content.
      case sha256(String)
      /// Regular files: the git blob id (sha1 of "blob <size>\0" + content).
      case gitBlob(String)
    }

    public var name: String
    public var size: Int64
    public var checksum: Checksum

    public init(name: String, size: Int64, checksum: Checksum) {
      self.name = name
      self.size = size
      self.checksum = checksum
    }
  }

  public var info: GenmaiModelInfo
  public var files: [File]

  public init(info: GenmaiModelInfo, files: [File]) {
    self.info = info
    self.files = files
  }

  /// The Hugging Face repository of the genmai model.
  public static let repository = "subdiox/genmai"
  /// The files a release must have.
  public static let fileNames = ["config.json", "tokenizer.json", "model.safetensors"]

  public var downloadSize: Int64 { files.reduce(0) { $0 + $1.size } }

  public func url(of file: File) -> URL {
    URL(string: "https://huggingface.co/\(info.repository)/resolve/\(info.revision)/\(file.name)")!
  }

  // MARK: - Hugging Face API

  /// The newest release this IME can run: the release tags (vX.Y.Z) newest first, the first whose config.json
  /// `isCompatible`.
  public static func latest(repository: String = repository, session: URLSession = .shared) async throws
    -> GenmaiModelRelease
  {
    let refs = try await fetch(apiURL(repository, "refs"), name: "release list", session: session)
    let tags = try releaseTags(refs)
    guard !tags.isEmpty else { throw AIModelInstallError.noRelease(repository) }
    for (version, tag) in tags {
      let release = try await fetch(repository: repository, tag: tag, version: version, session: session)
      let config = try await Self.fetch(
        release.url(of: release.files[0]), name: "config.json of \(tag)", session: session)
      if isCompatible(config: config) {
        return release
      }
    }
    throw AIModelInstallError.noRelease(repository)
  }

  /// The release with tag `tag` (its file list).
  public static func fetch(
    repository: String = repository, tag: String, version: String? = nil, session: URLSession = .shared
  ) async throws -> GenmaiModelRelease {
    let tree = try await fetch(apiURL(repository, "tree/\(tag)"), name: "file list of \(tag)", session: session)
    let version = version ?? Self.version(ofTag: tag) ?? tag
    return GenmaiModelRelease(
      info: GenmaiModelInfo(version: version, repository: repository, revision: tag), files: try files(tree))
  }

  static func apiURL(_ repository: String, _ path: String) -> URL {
    URL(string: "https://huggingface.co/api/models/\(repository)/\(path)")!
  }

  private static func fetch(_ url: URL, name: String, session: URLSession) async throws -> Data {
    let (data, response) = try await session.data(from: url)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw AIModelInstallError.download(name, status: status) }
    return data
  }

  /// "v1.2.3" / "1.2.3" → "1.2.3"; nil for other tags.
  static func version(ofTag tag: String) -> String? {
    let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let parts = v.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && Int($0) != nil }) else {
      return nil
    }
    return v
  }

  /// Orders versions "1.10.0" > "1.9.2".
  public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }
    let y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
      let p = i < x.count ? x[i] : 0
      let q = i < y.count ? y[i] : 0
      if p != q { return p < q ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
  }

  /// The release tags of a `/api/models/<repo>/refs` response, newest first: (version, tag).
  static func releaseTags(_ refs: Data) throws -> [(version: String, tag: String)] {
    guard let json = try JSONSerialization.jsonObject(with: refs) as? [String: Any],
      let tags = json["tags"] as? [[String: Any]]
    else {
      throw AIModelInstallError.badResponse("refs")
    }
    let releases = tags.compactMap { t -> (version: String, tag: String)? in
      guard let name = t["name"] as? String, let v = version(ofTag: name) else { return nil }
      return (v, name)
    }
    return releases.sorted { compareVersions($0.version, $1.version) == .orderedDescending }
  }

  /// The model files of a `/api/models/<repo>/tree/<rev>` response, in `fileNames` order.
  static func files(_ tree: Data) throws -> [File] {
    guard let entries = try JSONSerialization.jsonObject(with: tree) as? [[String: Any]] else {
      throw AIModelInstallError.badResponse("tree")
    }
    return try fileNames.map { name in
      guard let e = entries.first(where: { $0["path"] as? String == name && $0["type"] as? String == "file" }),
        let size = (e["size"] as? NSNumber)?.int64Value
      else {
        throw AIModelInstallError.badResponse("\(name) is missing in the release")
      }
      if let lfs = e["lfs"] as? [String: Any], let sha = lfs["oid"] as? String {
        return File(name: name, size: (lfs["size"] as? NSNumber)?.int64Value ?? size, checksum: .sha256(sha))
      }
      guard let oid = e["oid"] as? String else { throw AIModelInstallError.badResponse("no checksum for \(name)") }
      return File(name: name, size: size, checksum: .gitBlob(oid))
    }
  }

  /// Whether this IME can run a model with this config.json: GPT-2 (the decoder in GenmaiAI) with the zenzlc
  /// prompt format (`genmai_prompt_format`; releases before it was recorded used zenzlc).
  public static func isCompatible(config: Data) -> Bool {
    guard let json = try? JSONSerialization.jsonObject(with: config) as? [String: Any],
      json["model_type"] as? String == "gpt2",
      ["n_layer", "n_embd", "n_head", "vocab_size", "n_positions"].allSatisfy({ json[$0] is NSNumber })
    else {
      return false
    }
    let format = json["genmai_prompt_format"] as? String ?? "zenzlc"
    return format == "zenzlc"
  }
}

public enum AIModelInstallError: Error, Equatable, CustomStringConvertible {
  case download(String, status: Int)
  case checksum(String)
  case badModel(String)
  case badResponse(String)
  case noRelease(String)

  public var description: String {
    switch self {
    case .download(let file, let status): "downloading \(file) failed (HTTP \(status))"
    case .checksum(let file): "\(file) is damaged (checksum mismatch)"
    case .badModel(let message): "unsupported model file: \(message)"
    case .badResponse(let message): "unexpected answer from Hugging Face: \(message)"
    case .noRelease(let repository): "no model release for this version of genmai in \(repository)"
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
    _ release: GenmaiModelRelease, to directory: URL, cacheDirectory: URL = AIModelInstaller.cacheDirectory,
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
      guard try await checksum(of: local, file.checksum) else {
        try? fm.removeItem(at: local)
        throw AIModelInstallError.checksum(file.name)
      }
    }
    guard GenmaiModelRelease.isCompatible(config: try Data(contentsOf: downloads.appending(path: "config.json"))) else {
      throw AIModelInstallError.badModel("config.json of \(release.info.revision) is not a model this IME can run")
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

  /// The files an installation writes (and `uninstall` removes), including the format file of 0.1.0 installs.
  static let installedFiles = ["config.json", "tokenizer.json", "model.safetensors", GenmaiModelInfo.fileName, "genmai_fmt.txt"]

  /// Removes the model from `directory`: only the model's own files; the directory itself only if nothing else
  /// is left in it. Also drops downloads kept from an interrupted installation.
  public static func uninstall(from directory: URL, cacheDirectory: URL = AIModelInstaller.cacheDirectory) throws {
    let fm = FileManager.default
    for name in installedFiles {
      let url = directory.appending(path: name)
      if fm.fileExists(atPath: url.path) {
        try fm.removeItem(at: url)
      }
    }
    if let rest = try? fm.contentsOfDirectory(atPath: directory.path), rest.allSatisfy({ $0 == ".DS_Store" }) {
      try? fm.removeItem(at: directory)
    }
    try? fm.removeItem(at: cacheDirectory)
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

  /// Whether the file at `url` has `checksum`.
  @concurrent
  static func checksum(of url: URL, _ checksum: GenmaiModelRelease.File.Checksum) async throws -> Bool {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    func hash<H: HashFunction>(_ h: inout H) throws -> String {
      while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
        try Task.checkCancellation()
        h.update(data: chunk)
      }
      return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
    switch checksum {
    case .sha256(let expected):
      var h = SHA256()
      return try hash(&h) == expected.lowercased()
    case .gitBlob(let expected):
      let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
      var h = Insecure.SHA1()
      h.update(data: Data("blob \(size)\0".utf8))
      return try hash(&h) == expected.lowercased()
    }
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
