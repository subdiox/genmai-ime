// Updates of Genmai itself (not part of Mozc).
//
// Releases are published on GitHub (subdiox/genmai-ime) as vX.Y.Z tags with the installer package (Genmai-X.Y.Z.pkg,
// Tools/make_release.sh) attached. `GenmaiAppRelease.latest` asks the GitHub API for the releases and returns the one
// with the highest version that has a package; `GenmaiUpdater.download` fetches the package into the caches and
// checks its size and the SHA-256 GitHub lists. The package is then opened with Installer (by the GUI). A package
// downloaded this way has no quarantine attribute, so Gatekeeper does not stop the unsigned package.
//
// The IME checks once a day if `GenmaiUpdateSettings.automaticCheck` is on (GenmaiMac `GenmaiUpdateChecker`) and
// posts a notification; the settings (tab "Misc") and the update dialog check on request.

import Foundation
import GenmaiBase

public struct GenmaiAppRelease: Equatable, Sendable {
  public static let repository = "subdiox/genmai-ime"

  public struct Package: Equatable, Sendable {
    public var name: String
    public var url: URL
    public var size: Int64
    /// Lowercase hex; nil if GitHub did not list a digest.
    public var sha256: String?

    public init(name: String, url: URL, size: Int64, sha256: String?) {
      self.name = name
      self.url = url
      self.size = size
      self.sha256 = sha256
    }
  }

  public var version: String
  public var tag: String
  /// The release page.
  public var pageURL: URL
  /// The release notes (Markdown).
  public var notes: String
  public var package: Package

  public init(version: String, tag: String, pageURL: URL, notes: String, package: Package) {
    self.version = version
    self.tag = tag
    self.pageURL = pageURL
    self.notes = notes
    self.package = package
  }

  /// The version of the running Genmai.
  public static var currentVersion: String { Version.getProductVersion() }

  public func isNewer(than version: String) -> Bool {
    GenmaiModelRelease.compareVersions(self.version, version) == .orderedDescending
  }

  /// The newest published release (not a draft or pre-release) with an installer package; nil if there is none.
  public static func latest(repository: String = repository, session: URLSession = .shared) async throws
    -> GenmaiAppRelease?
  {
    var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30")!)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw GenmaiUpdateError.download("release list", status: status) }
    return try releases(data).first
  }

  /// The releases of a `/repos/<repo>/releases` response that have a package, newest first.
  static func releases(_ data: Data) throws -> [GenmaiAppRelease] {
    guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw GenmaiUpdateError.badResponse("not a release list")
    }
    let releases = list.compactMap { item -> GenmaiAppRelease? in
      guard item["draft"] as? Bool != true, item["prerelease"] as? Bool != true,
        let tag = item["tag_name"] as? String, let version = GenmaiModelRelease.version(ofTag: tag),
        let page = (item["html_url"] as? String).flatMap(URL.init(string:)),
        let assets = item["assets"] as? [[String: Any]]
      else { return nil }
      let package = assets.lazy.compactMap { asset -> Package? in
        guard let name = asset["name"] as? String, name.hasSuffix(".pkg"),
          let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)),
          let size = (asset["size"] as? NSNumber)?.int64Value
        else { return nil }
        let digest = (asset["digest"] as? String).flatMap { d in
          d.hasPrefix("sha256:") ? String(d.dropFirst("sha256:".count)).lowercased() : nil
        }
        return Package(name: name, url: url, size: size, sha256: digest)
      }.first
      guard let package else { return nil }
      return GenmaiAppRelease(
        version: version, tag: tag, pageURL: page, notes: item["body"] as? String ?? "", package: package)
    }
    return releases.sorted { GenmaiModelRelease.compareVersions($0.version, $1.version) == .orderedDescending }
  }
}

public enum GenmaiUpdateError: Error, Equatable, CustomStringConvertible {
  case download(String, status: Int)
  case badResponse(String)
  case damaged(String)

  public var description: String {
    switch self {
    case .download(let name, let status): "downloading the \(name) failed (HTTP \(status))"
    case .badResponse(let message): "unexpected answer from GitHub: \(message)"
    case .damaged(let name): "\(name) is damaged (size or checksum mismatch)"
    }
  }
}

/// `<user profile>/update.json`.
public struct GenmaiUpdateSettings: Codable, Equatable, Sendable {
  /// Check for updates once a day and notify.
  public var automaticCheck = true
  public var lastCheck: Date?
  /// The release the user chose to skip: not notified again.
  public var skippedVersion: String?

  public static let checkInterval: TimeInterval = 24 * 60 * 60

  enum CodingKeys: String, CodingKey {
    case automaticCheck = "automatic_check"
    case lastCheck = "last_check"
    case skippedVersion = "skipped_version"
  }

  public init(automaticCheck: Bool = true, lastCheck: Date? = nil, skippedVersion: String? = nil) {
    self.automaticCheck = automaticCheck
    self.lastCheck = lastCheck
    self.skippedVersion = skippedVersion
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    automaticCheck = try c.decodeIfPresent(Bool.self, forKey: .automaticCheck) ?? true
    lastCheck = try c.decodeIfPresent(Date.self, forKey: .lastCheck)
    skippedVersion = try c.decodeIfPresent(String.self, forKey: .skippedVersion)
  }

  /// Whether an automatic check is due at `now`.
  public func isCheckDue(at now: Date = Date()) -> Bool {
    guard automaticCheck else { return false }
    guard let lastCheck else { return true }
    return now.timeIntervalSince(lastCheck) >= Self.checkInterval || now < lastCheck
  }

  /// Whether to tell the user about `release` (newer than the running version and not skipped).
  public func shouldOffer(_ release: GenmaiAppRelease, currentVersion: String = GenmaiAppRelease.currentVersion)
    -> Bool
  {
    release.isNewer(than: currentVersion) && release.version != skippedVersion
  }

  public static let fileName = "update.json"

  public static var fileURL: URL {
    URL(filePath: SystemUtil.getUserProfileDirectory(), directoryHint: .isDirectory).appending(path: fileName)
  }

  public static func load(from url: URL = GenmaiUpdateSettings.fileURL) -> GenmaiUpdateSettings {
    guard let data = try? Data(contentsOf: url) else { return GenmaiUpdateSettings() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(GenmaiUpdateSettings.self, from: data)) ?? GenmaiUpdateSettings()
  }

  public func save(to url: URL = GenmaiUpdateSettings.fileURL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(self).write(to: url, options: .atomic)
  }

  /// Loads the settings, applies `change` and saves them (the IME and the settings write the same file).
  public static func update(at url: URL = GenmaiUpdateSettings.fileURL, _ change: (inout GenmaiUpdateSettings) -> Void)
    throws
  {
    var settings = load(from: url)
    change(&settings)
    try settings.save(to: url)
  }
}

public enum GenmaiUpdater {
  public static var cacheDirectory: URL {
    URL.cachesDirectory.appending(path: "Genmai/update", directoryHint: .isDirectory)
  }

  /// Downloads the package of `release` into `cacheDirectory` (earlier downloads are removed) and checks its size
  /// and checksum. Returns the package file. Honors task cancellation.
  public static func download(
    _ release: GenmaiAppRelease, cacheDirectory: URL = GenmaiUpdater.cacheDirectory,
    progress: @escaping @Sendable (_ received: Int64, _ total: Int64) -> Void = { _, _ in }
  ) async throws -> URL {
    let fm = FileManager.default
    try? fm.removeItem(at: cacheDirectory)
    try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    let package = release.package
    let local = cacheDirectory.appending(path: package.name)
    try await FileDownload.download(
      package.url, to: local, failure: { GenmaiUpdateError.download(package.name, status: $0) }
    ) { received in
      progress(received, package.size)
    }
    let size = (try fm.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? -1
    var intact = size == package.size
    if intact, let sha256 = package.sha256 {
      intact = try await FileDownload.sha256(of: local) == sha256
    }
    guard intact else {
      try? fm.removeItem(at: local)
      throw GenmaiUpdateError.damaged(package.name)
    }
    return local
  }
}
