// Download and installation of the genmai model (not part of Mozc).
//
// The model is not bundled with the IME. The config dialog (GenmaiApp) and `genmai-cli install` look up the newest
// release on Hugging Face (`GenmaiModelRelease.latest`: the highest vX.Y.Z tag whose config.json this IME can run)
// and download its weights in the runtime layout GenmaiAI loads (`AIModelVariant`: `model-8bit.safetensors`, the
// linear layers quantized to 8 bits, 0.34 GB, the default; or `model-bf16.safetensors`, 0.62 GB), with config.json
// and tokenizer.json, each checked against the checksum Hugging Face lists. They are installed into the model directory as
// model.safetensors / config.json / tokenizer.json with `genmai_model.json` (which release is installed).
// The release's fp32 `model.safetensors` (HF layout, for transformers) is not downloaded; `genmai-cli prepare`
// converts such a file from a local checkpoint (`GenmaiSafetensors.prepare`, plain Swift, the same bits as MLX's
// `astype(bfloat16)`).

import Foundation

/// The weights of a release: Conv1D weights (out, in), no lm_head, no `transformer.` prefix.
public enum AIModelVariant: String, Codable, CaseIterable, Sendable {
  /// The linear layers quantized to 8 bits (MLX affine, groups of 64); embeddings, norms and biases bf16.
  case q8 = "8bit"
  case bf16

  public static let `default` = AIModelVariant.q8

  /// The file in a release.
  public var weightsFileName: String {
    switch self {
    case .q8: "model-8bit.safetensors"
    case .bf16: "model-bf16.safetensors"
    }
  }

  /// The metadata `format` of the file.
  public var format: String {
    switch self {
    case .q8: GenmaiSafetensors.quantizedFormat
    case .bf16: GenmaiSafetensors.preparedFormat
    }
  }
}

/// Which model release is installed (`genmai_model.json` in the model directory).
public struct GenmaiModelInfo: Codable, Equatable, Sendable {
  public var version: String
  public var repository: String
  public var revision: String
  /// nil in files written before variants existed (bf16).
  public var variant: AIModelVariant?

  public init(version: String, repository: String, revision: String, variant: AIModelVariant? = nil) {
    self.version = version
    self.repository = repository
    self.revision = revision
    self.variant = variant
  }

  public var installedVariant: AIModelVariant { variant ?? .bf16 }

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

/// A model release on Hugging Face (a vX.Y.Z tag of the model repository), with its files (config, tokenizer and the
/// weights of each variant it has) and their checksums, as listed by the Hugging Face API.
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
  /// The files every release has besides the weights.
  public static let commonFileNames = ["config.json", "tokenizer.json"]

  /// The files to download for `variant` (config, tokenizer, weights); nil if the release lacks those weights.
  public func files(for variant: AIModelVariant) -> [File]? {
    let names = Self.commonFileNames + [variant.weightsFileName]
    let selected = names.compactMap { name in files.first { $0.name == name } }
    return selected.count == names.count ? selected : nil
  }

  public func downloadSize(for variant: AIModelVariant) -> Int64 {
    files(for: variant)?.reduce(0) { $0 + $1.size } ?? 0
  }

  /// The variants whose weights the release has.
  public var variants: [AIModelVariant] { AIModelVariant.allCases.filter { files(for: $0) != nil } }

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
        release.url(of: release.files[0]), name: "config.json of \(tag)", session: session)  // files[0]: config.json
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

  /// The model files of a `/api/models/<repo>/tree/<rev>` response: config.json, tokenizer.json, then the weights
  /// of the variants present (at least one), in `AIModelVariant` order.
  static func files(_ tree: Data) throws -> [File] {
    guard let entries = try JSONSerialization.jsonObject(with: tree) as? [[String: Any]] else {
      throw AIModelInstallError.badResponse("tree")
    }
    func entry(_ name: String) -> [String: Any]? {
      entries.first { $0["path"] as? String == name && $0["type"] as? String == "file" }
    }
    let weights = AIModelVariant.allCases.map(\.weightsFileName).filter { entry($0) != nil }
    guard !weights.isEmpty else { throw AIModelInstallError.badResponse("no weights in the release") }
    return try (commonFileNames + weights).map { name in
      guard let e = entry(name), let size = (e["size"] as? NSNumber)?.int64Value else {
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
    case installing
  }

  /// Downloaded files are kept here until the installation succeeded (an interrupted installation reuses the
  /// files that were complete).
  public static var cacheDirectory: URL {
    URL.cachesDirectory.appending(path: "Genmai/download", directoryHint: .isDirectory)
  }

  /// Downloads `variant` of `release` and installs it into `directory`. Only the model's own files in
  /// `directory` are replaced (each one atomically); other files are left alone. Honors task cancellation.
  public static func install(
    _ release: GenmaiModelRelease, variant: AIModelVariant, to directory: URL,
    cacheDirectory: URL = AIModelInstaller.cacheDirectory, progress: @escaping @Sendable (Phase) -> Void = { _ in }
  ) async throws {
    guard let files = release.files(for: variant) else {
      throw AIModelInstallError.badResponse("\(release.info.revision) has no \(variant.rawValue) weights")
    }
    let fm = FileManager.default
    let downloads = cacheDirectory.appending(path: release.info.revision, directoryHint: .isDirectory)
    try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
    let total = release.downloadSize(for: variant)
    var done: Int64 = 0
    for file in files {
      let local = downloads.appending(path: file.name)
      if !isComplete(local, file) {
        try? fm.removeItem(at: local)
        let base = done
        try await FileDownload.download(
          release.url(of: file), to: local, failure: { AIModelInstallError.download(file.name, status: $0) }
        ) { received in
          progress(.downloading(received: base + received, total: total))
        }
      }
      done += file.size
      progress(.downloading(received: done, total: total))
    }
    progress(.verifying)
    for file in files {
      let local = downloads.appending(path: file.name)
      guard try await checksum(of: local, file.checksum) else {
        try? fm.removeItem(at: local)
        throw AIModelInstallError.checksum(file.name)
      }
    }
    guard GenmaiModelRelease.isCompatible(config: try Data(contentsOf: downloads.appending(path: "config.json"))) else {
      throw AIModelInstallError.badModel("config.json of \(release.info.revision) is not a model this IME can run")
    }
    let weights = downloads.appending(path: variant.weightsFileName)
    guard try GenmaiSafetensors.format(of: weights) == variant.format else {
      throw AIModelInstallError.badModel("\(variant.weightsFileName) is not in the runtime layout")
    }
    try Task.checkCancellation()
    progress(.installing)
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let staging = directory.appending(path: ".install-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fm.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: staging) }
    try fm.moveItem(at: weights, to: staging.appending(path: "model.safetensors"))
    for name in ["config.json", "tokenizer.json"] {
      try fm.moveItem(at: downloads.appending(path: name), to: staging.appending(path: name))
    }
    var info = release.info
    info.variant = variant
    try info.save(to: staging)
    try Task.checkCancellation()
    // The weights last: a directory with the new weights always has the matching config and tokenizer.
    for name in ["config.json", "tokenizer.json", "model.safetensors", GenmaiModelInfo.fileName] {
      try replace(directory.appending(path: name), with: staging.appending(path: name))
    }
    try? fm.removeItem(at: downloads)
  }

  /// The files an installation writes (and `uninstall` removes).
  static let installedFiles = ["config.json", "tokenizer.json", "model.safetensors", GenmaiModelInfo.fileName]

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

  /// Whether the file at `url` has `checksum`.
  static func checksum(of url: URL, _ checksum: GenmaiModelRelease.File.Checksum) async throws -> Bool {
    switch checksum {
    case .sha256(let expected):
      return try await FileDownload.sha256(of: url) == expected.lowercased()
    case .gitBlob(let expected):
      return try await FileDownload.gitBlobSHA1(of: url) == expected.lowercased()
    }
  }
}

/// Conversion of the HF GPT-2 weights to the runtime layout of GenmaiAI.
public enum GenmaiSafetensors {
  /// Metadata `format` of the converted file (`GenmaiModel.preparedFormat` in GenmaiAI).
  public static let preparedFormat = "genmai-bf16-out-in"
  /// Metadata `format` of 8-bit weights (`GenmaiModel.quantizedFormat`, written by `genmai-cli quantize`).
  public static let quantizedFormat = "genmai-quantized-out-in"

  /// The metadata `format` of the safetensors file at `url` (nil if it has none).
  public static func format(of url: URL) throws -> String? {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    guard let lengthData = try handle.read(upToCount: 8), lengthData.count == 8 else {
      throw AIModelInstallError.badModel("file too short")
    }
    let length = lengthData.withUnsafeBytes { Int($0.loadUnaligned(as: UInt64.self).littleEndian) }
    guard length < 1 << 24, let headerData = try handle.read(upToCount: length), headerData.count == length,
      let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any]
    else {
      throw AIModelInstallError.badModel("bad header")
    }
    return (header["__metadata__"] as? [String: Any])?["format"] as? String
  }

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
