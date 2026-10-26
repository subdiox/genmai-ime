// Updates of Genmai itself (not part of Mozc): the state behind the "Updates" section of the config dialog (tab
// "Misc") and the update dialog (app screen update_dialog, opened from the IME's update notification).

#if os(macOS)
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
      /// The package was opened with Installer (Genmai is installed for all users).
      case opened
      /// The package was installed for this user (no Installer window; Genmai is installed per user).
      case installed

      var isBusy: Bool {
        if case .downloading = self { return true }
        return false
      }
      case failed(String)
    }

    public private(set) var latest = Latest.unknown
    public private(set) var install = Install.idle
    public private(set) var settings: GenmaiUpdateSettings
    public let currentVersion: String

    /// Looks up the newest release (replaced by tests).
    var fetcher: @Sendable () async throws -> GenmaiAppRelease? = { try await GenmaiAppRelease.latest() }
    /// Downloads and checks the package of a release (replaced by tests).
    var downloader: @Sendable (GenmaiAppRelease, @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL = {
      release, progress in
      try await GenmaiUpdater.download(release, progress: progress)
    }
    /// Installs the package where Genmai is installed (replaced by tests).
    var installPackage: @Sendable (URL) async -> Install = { await GenmaiPackageInstaller.install($0) }

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
        guard
          lastShown.withLock({ last in
            defer { last = permille }
            return last != permille
          })
        else { return }
        Task { @MainActor [weak self] in
          if case .downloading = self?.install { self?.install = .downloading(received: received, total: total) }
        }
      }
      installTask = Task { [weak self] in
        let result: Install
        do {
          let package = try await downloader(release, report)
          guard let installPackage = self?.installPackage else { return }
          result = await installPackage(package)
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

  /// Installs a downloaded package into the same place as the running Genmai, so that an update never leaves a second
  /// copy: a per-user installation (~/Library/Input Methods) is updated with `installer -target
  /// CurrentUserHomeDirectory`, which needs no administrator rights and shows no window; an installation for all users
  /// (/Library/Input Methods) opens the package in Installer, which asks for administrator rights itself.
  enum GenmaiPackageInstaller {
    /// The input method bundle this app belongs to (Genmai.app/Contents/Resources/Genmai.app → Genmai.app).
    static var inputMethodBundle: URL {
      Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func isPerUser(_ bundle: URL = inputMethodBundle) -> Bool {
      bundle.standardizedFileURL.path(percentEncoded: false)
        .hasPrefix(URL.homeDirectory.standardizedFileURL.path(percentEncoded: false))
    }

    @MainActor
    static func install(_ package: URL) async -> GenmaiUpdateModel.Install {
      guard isPerUser() else {
        return NSWorkspace.shared.open(package) ? .opened : .failed("cannot open \(package.lastPathComponent)")
      }
      let process = Process()
      process.executableURL = URL(filePath: "/usr/sbin/installer")
      process.arguments = ["-pkg", package.path(percentEncoded: false), "-target", "CurrentUserHomeDirectory"]
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
      if status == 0 {
        return .installed
      }
      let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      return .failed(message.isEmpty ? "installer exited with \(status)" : message)
    }
  }
#endif
