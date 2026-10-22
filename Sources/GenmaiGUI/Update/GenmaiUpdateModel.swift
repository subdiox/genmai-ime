// Updates of Genmai itself (not part of Mozc): the state behind the "Updates" section of the config dialog (tab
// "Misc") and the update dialog (tool mode update_dialog, opened from the IME's update notification).

import AppKit
import Foundation
import GenmaiClient
import Observation
import Synchronization

@MainActor
@Observable
public final class GenmaiUpdateModel {
  public enum Latest: Equatable, Sendable {
    case unknown
    case checking
    /// No newer release; the newest published version (the running one if nothing is published).
    case upToDate(String)
    case available(GenmaiAppRelease)
    case failed(String)
  }

  public enum Install: Equatable, Sendable {
    case idle
    case downloading(received: Int64, total: Int64)
    /// The package was opened with Installer.
    case opened
    case failed(String)
  }

  public private(set) var latest = Latest.unknown
  public private(set) var install = Install.idle
  public private(set) var settings: GenmaiUpdateSettings
  public let currentVersion: String

  /// Looks up the newest release (replaced by tests).
  var fetcher: @Sendable () async throws -> GenmaiAppRelease? = { try await GenmaiAppRelease.latest() }
  /// Downloads and checks the package of a release (replaced by tests).
  var downloader:
    @Sendable (GenmaiAppRelease, @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL = {
      release, progress in
      try await GenmaiUpdater.download(release, progress: progress)
    }
  /// Opens the package with Installer (replaced by tests).
  var openInstaller: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }

  private let settingsURL: URL
  private var installTask: Task<Void, Never>?

  public init(
    settingsURL: URL = GenmaiUpdateSettings.fileURL, currentVersion: String = GenmaiAppRelease.currentVersion
  ) {
    self.settingsURL = settingsURL
    self.currentVersion = currentVersion
    settings = GenmaiUpdateSettings.load(from: settingsURL)
  }

  public var automaticCheck: Bool {
    get { settings.automaticCheck }
    set { change { $0.automaticCheck = newValue } }
  }

  /// The release on offer, if any.
  public var availableRelease: GenmaiAppRelease? {
    if case .available(let release) = latest { release } else { nil }
  }

  /// Checks when shown, if automatic checks are on and nothing was looked up yet.
  public func checkIfAutomatic() async {
    guard settings.automaticCheck, latest == .unknown else { return }
    await check()
  }

  public func check() async {
    guard latest != .checking else { return }
    latest = .checking
    do {
      let release = try await fetcher()
      change { $0.lastCheck = Date() }
      if let release, release.isNewer(than: currentVersion) {
        latest = .available(release)
      } else {
        latest = .upToDate(release?.version ?? currentVersion)
      }
    } catch {
      latest = .failed("\(error)")
    }
  }

  /// Downloads the available release and opens it with Installer.
  public func installUpdate() {
    guard installTask == nil, let release = availableRelease else { return }
    install = .downloading(received: 0, total: release.package.size)
    let downloader = downloader
    // Progress arrives for every network chunk: forward it only when the shown permille changes.
    let lastShown = Mutex<Int64>(-1)
    let report: @Sendable (Int64, Int64) -> Void = { [weak self] received, total in
      let permille = received * 1000 / max(total, 1)
      guard lastShown.withLock({ last in defer { last = permille }; return last != permille }) else { return }
      Task { @MainActor [weak self] in
        if case .downloading = self?.install { self?.install = .downloading(received: received, total: total) }
      }
    }
    installTask = Task { [weak self] in
      let result: Install
      do {
        let package = try await downloader(release, report)
        result = self?.openInstaller(package) == false ? .failed("cannot open \(package.lastPathComponent)") : .opened
      } catch is CancellationError {
        result = .idle
      } catch {
        result = .failed("\(error)")
      }
      self?.install = result
      self?.installTask = nil
    }
  }

  public func cancelInstall() {
    installTask?.cancel()
  }

  /// Not offered again by the automatic check.
  public func skip(_ release: GenmaiAppRelease) {
    change { $0.skippedVersion = release.version }
  }

  /// Applies `edit` to the stored settings (the IME writes the same file) and saves them.
  private func change(_ edit: (inout GenmaiUpdateSettings) -> Void) {
    var updated = GenmaiUpdateSettings.load(from: settingsURL)
    edit(&updated)
    settings = updated
    do {
      try updated.save(to: settingsURL)
    } catch {
      NSLog("Genmai: cannot save %@: %@", settingsURL.path, "\(error)")
    }
  }
}
