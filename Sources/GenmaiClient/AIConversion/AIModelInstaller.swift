// Download and installation of the genmai model (not part of Mozc).
//
// The model is not bundled with the IME. There are two models, each in its own Hugging Face repository
// (`AIModelSize`: medium = subdiox/genmai-310M, the default; small = subdiox/genmai-90M). The config dialog
// (GenmaiApp) and `genmai-cli install` look up the newest release of the chosen model (`GenmaiModelRelease.latest`:
// the highest vX.Y.Z tag whose config.json this IME can run and that has the Core ML model) and download
// config.json, tokenizer.json and `model-coreml.zip` (`genmai_coreml.json` + `genmai.mlpackage`, or
// `genmai_0.mlpackage`, ... for a model split into chunks), each checked against the checksum Hugging Face lists.
// The archive is extracted (ditto), the packages are compiled, and they are installed as `genmai*.mlmodelc` with
// `genmai_coreml.json`, config.json, tokenizer.json and `genmai_model.json` (which model and release is installed).
// The release's fp32 `model.safetensors` (HF layout, for transformers) is not downloaded.

import CoreML
import Foundation
import GenmaiBase

/// The genmai models; each has its own Hugging Face repository with its own releases.
public enum AIModelSize: String, Codable, CaseIterable, Sendable {
  /// genmai-90M: 12 layers, 768 dim (Core ML model 82 MB).
  case small
  /// genmai-310M: 24 layers, 1024 dim (Core ML model 283 MB).
  case medium

  public static let `default` = AIModelSize.medium

  public var repository: String {
    switch self {
    case .small: "subdiox/genmai-90M"
    case .medium: "subdiox/genmai-310M"
    }
  }

  /// "genmai-90M".
  public var modelName: String { String(repository.split(separator: "/").last ?? "") }

  /// The memory AI conversion adds to the input method with this model, in MB: the process footprint while
  /// converting, peak (Core ML on the Neural Engine, M4 Pro: genmai-90M 46–90 MB, genmai-310M 77–143 MB).
  public var memoryMegabytes: Int {
    switch self {
    case .small: 90
    case .medium: 150
    }
  }

  /// The model of a repository.
  public init?(repository: String) {
    guard let size = Self.allCases.first(where: { $0.repository == repository }) else { return nil }
    self = size
  }
}

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

  /// The model of the release; nil for a repository this version does not know.
  public var size: AIModelSize? { AIModelSize(repository: repository) }

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

/// A model release on Hugging Face (a vX.Y.Z tag of a model repository), with the files the IME installs (config,
/// tokenizer, the Core ML model) and their checksums, as listed by the Hugging Face API.
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

  /// The Core ML model of a release: an archive of its shapes (`genmai_coreml.json`) and its packages
  /// (`genmai*.mlpackage`). A Core ML model in a format this IME cannot run must be released under another name.
  public static let coreMLArchiveName = "model-coreml.zip"
  /// The Core ML package format this IME runs (`GenmaiCoreMLConfig.supportedFormat` in GenmaiAI).
  public static let coreMLFormat = "genmai-coreml-1"
  /// The files to download, in this order.
  public static let fileNames = ["config.json", "tokenizer.json", coreMLArchiveName]

  public var downloadSize: Int64 { files.reduce(0) { $0 + $1.size } }

  public func url(of file: File) -> URL {
    URL(validLiteral: "https://huggingface.co").appending(
      path: "\(info.repository)/resolve/\(info.revision)/\(file.name)")
  }

  // MARK: - Hugging Face API

  /// The newest release this IME can run: the release tags (vX.Y.Z) newest first, the first whose config.json
  /// `isCompatible` and that has `fileNames`.
  public static func latest(repository: String, session: URLSession = .shared) async throws
    -> GenmaiModelRelease
  {
    let refs = try await fetch(apiURL(repository, "refs"), name: "release list", session: session)
    let tags = try releaseTags(refs)
    guard !tags.isEmpty else { throw AIModelInstallError.noRelease(repository) }
    for (version, tag) in tags {
      guard let release = try? await fetch(repository: repository, tag: tag, version: version, session: session) else {
        continue  // e.g. a release without the Core ML model
      }
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
    repository: String, tag: String, version: String? = nil, session: URLSession = .shared
  ) async throws -> GenmaiModelRelease {
    let tree = try await fetch(apiURL(repository, "tree/\(tag)"), name: "file list of \(tag)", session: session)
    let version = version ?? Self.version(ofTag: tag) ?? tag
    return GenmaiModelRelease(
      info: GenmaiModelInfo(version: version, repository: repository, revision: tag), files: try files(tree))
  }

  static func apiURL(_ repository: String, _ path: String) -> URL {
    URL(validLiteral: "https://huggingface.co/api/models").appending(path: "\(repository)/\(path)")
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

  /// The files to install from a `/api/models/<repo>/tree/<rev>` response (`fileNames`).
  static func files(_ tree: Data) throws -> [File] {
    let entries = try fileEntries(tree)
    return try fileNames.map { name in
      guard let e = entries[name] else { throw AIModelInstallError.badResponse("\(name) is missing in the release") }
      return try file(name, e)
    }
  }

  /// The files (not directories) of a tree response by path.
  private static func fileEntries(_ tree: Data) throws -> [String: [String: Any]] {
    guard let entries = try JSONSerialization.jsonObject(with: tree) as? [[String: Any]] else {
      throw AIModelInstallError.badResponse("tree")
    }
    var files: [String: [String: Any]] = [:]
    for e in entries where e["type"] as? String == "file" {
      if let path = e["path"] as? String { files[path] = e }
    }
    return files
  }

  private static func file(_ name: String, _ e: [String: Any]) throws -> File {
    guard let size = (e["size"] as? NSNumber)?.int64Value else {
      throw AIModelInstallError.badResponse("no size for \(name)")
    }
    if let lfs = e["lfs"] as? [String: Any], let sha = lfs["oid"] as? String {
      return File(name: name, size: (lfs["size"] as? NSNumber)?.int64Value ?? size, checksum: .sha256(sha))
    }
    guard let oid = e["oid"] as? String else { throw AIModelInstallError.badResponse("no checksum for \(name)") }
    return File(name: name, size: size, checksum: .gitBlob(oid))
  }

  /// Whether this IME runs a Core ML package with this `genmai_coreml.json`.
  public static func isSupportedCoreML(config: Data) -> Bool {
    guard let json = try? JSONSerialization.jsonObject(with: config) as? [String: Any] else { return false }
    return json["format"] as? String == coreMLFormat
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
    /// Loading the installed model once for the Neural Engine (its first load compiles it).
    case preparing
  }

  /// Downloaded files are kept here until the installation succeeded (an interrupted installation reuses the
  /// files that were complete).
  public static var cacheDirectory: URL {
    URL.cachesDirectory.appending(path: "Genmai/download", directoryHint: .isDirectory)
  }

  /// Downloads `release` and installs it into `directory`. Only the model's own files in `directory` are replaced
  /// (each one atomically); other files are left alone. Honors task cancellation.
  public static func install(
    _ release: GenmaiModelRelease, to directory: URL,
    cacheDirectory: URL = AIModelInstaller.cacheDirectory, progress: @escaping @Sendable (Phase) -> Void = { _ in }
  ) async throws {
    let files = release.files
    let fm = FileManager.default
    let downloads = cacheDirectory.appending(
      path: "\(release.info.repository.replacing("/", with: "_"))@\(release.info.revision)",
      directoryHint: .isDirectory)
    try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
    let total = release.downloadSize
    var done: Int64 = 0
    for file in files {
      let local = downloads.appending(path: file.name)
      if !isComplete(local, file) {
        try? fm.removeItem(at: local)
        let base = done
        try await FileDownload.download(
          release.url(of: file), to: local, failure: { AIModelInstallError.download(file.name, status: $0) },
          progress: { received in progress(.downloading(received: base + received, total: total)) })
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
    try Task.checkCancellation()
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let staging = directory.appending(path: ".install-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fm.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: staging) }
    let extracted = downloads.appending(path: "coreml", directoryHint: .isDirectory)
    try? fm.removeItem(at: extracted)
    try await unzip(downloads.appending(path: GenmaiModelRelease.coreMLArchiveName), to: extracted)
    let config = extracted.appending(path: coreMLConfigFileName)
    guard let data = try? Data(contentsOf: config), GenmaiModelRelease.isSupportedCoreML(config: data) else {
      throw AIModelInstallError.badModel("\(GenmaiModelRelease.coreMLArchiveName) is not a model this IME runs")
    }
    let packages = coreMLModelFiles(in: extracted).filter { $0.hasSuffix(".mlpackage") }
    guard !packages.isEmpty else {
      throw AIModelInstallError.badModel("no Core ML package in \(GenmaiModelRelease.coreMLArchiveName)")
    }
    progress(.installing)
    // compiling takes seconds; the Neural Engine compiles each once more on the first load (cached by the system)
    var compiledNames: [String] = []
    for package in packages {
      let name = String(package.dropLast(".mlpackage".count)) + ".mlmodelc"
      let compiled = try await MLModel.compileModel(at: extracted.appending(path: package))
      defer { try? fm.removeItem(at: compiled) }
      try fm.moveItem(at: compiled, to: staging.appending(path: name))
      compiledNames.append(name)
    }
    try fm.moveItem(at: config, to: staging.appending(path: coreMLConfigFileName))
    for name in ["config.json", "tokenizer.json"] {
      try fm.moveItem(at: downloads.appending(path: name), to: staging.appending(path: name))
    }
    try release.info.save(to: staging)
    try Task.checkCancellation()
    // config and tokenizer first, genmai_coreml.json after the compiled models, genmai_model.json last: a directory
    // whose genmai_coreml.json is there always has the matching model, config and tokenizer
    for name in ["config.json", "tokenizer.json"] + compiledNames + [coreMLConfigFileName, GenmaiModelInfo.fileName] {
      try replace(directory.appending(path: name), with: staging.appending(path: name))
    }
    for name in coreMLModelFiles(in: directory) where !compiledNames.contains(name) {
      try? fm.removeItem(at: directory.appending(path: name))
    }
    // The first load compiles the model for the Neural Engine (~20 s for genmai-310M). The system caches that per
    // path, so it is done here, at the model's final path: the input method then loads it at once. Not fatal: the
    // input method would compile it itself.
    progress(.preparing)
    for name in compiledNames {
      for function in ["prefill", "decode"] {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        configuration.functionName = function
        _ = try? await MLModel.load(contentsOf: directory.appending(path: name), configuration: configuration)
      }
    }
    try? fm.removeItem(at: downloads)
  }

  /// The Core ML model's shapes in the model directory (`GenmaiCoreMLModel.configFileName` in GenmaiAI).
  public static let coreMLConfigFileName = "genmai_coreml.json"

  /// Extracts the zip archive `archive` into `directory` with ditto (Foundation has no zip API).
  static func unzip(_ archive: URL, to directory: URL) async throws {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archive.path(percentEncoded: false), directory.path(percentEncoded: false)]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    let status: Int32 = await withCheckedContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(returning: -1)
      }
    }
    guard status == 0 else {
      let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      throw AIModelInstallError.badModel("cannot extract \(archive.lastPathComponent): \(message)")
    }
  }

  /// The Core ML models in `directory` (`genmai*.mlmodelc` / `genmai*.mlpackage`).
  public static func coreMLModelFiles(in directory: URL) -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.filter { $0.hasPrefix("genmai") && ($0.hasSuffix(".mlmodelc") || $0.hasSuffix(".mlpackage")) }
      .sorted()
  }

  /// The files an installation writes (and `uninstall` removes), besides the Core ML models.
  static let installedFiles = [
    "config.json", "tokenizer.json", coreMLConfigFileName, GenmaiModelInfo.fileName,
  ]

  /// Removes the model from `directory`: only the model's own files; the directory itself only if nothing else
  /// is left in it. Also drops downloads kept from an interrupted installation.
  public static func uninstall(from directory: URL, cacheDirectory: URL = AIModelInstaller.cacheDirectory) throws {
    let fm = FileManager.default
    for name in installedFiles + coreMLModelFiles(in: directory) {
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
