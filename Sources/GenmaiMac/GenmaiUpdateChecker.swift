// The automatic update check of the IME (not part of Mozc).
//
// While the input method runs, it looks up the newest release once a day (`GenmaiUpdateSettings.isCheckDue`; the
// time of the last check is shared with the settings, so a check there counts too) if "Check for updates
// automatically" is on. A release newer than the running version that the user did not skip is announced with a
// notification once per version; clicking it opens the update dialog of the Genmai app. Nothing is downloaded
// without the user.

import AppKit
import GenmaiClient
import UserNotifications

@MainActor
public final class GenmaiUpdateChecker: NSObject, UNUserNotificationCenterDelegate {
  /// The first check waits so that it does not compete with loading the engine.
  static let initialDelay: Duration = .seconds(60)
  /// How often the IME looks whether a check is due.
  static let pollInterval: Duration = .seconds(60 * 60)

  private let launcher: MacAppLauncher
  private var task: Task<Void, Never>?
  /// The version last announced by this process.
  private var notifiedVersion: String?

  public init(launcher: MacAppLauncher = MacAppLauncher()) {
    self.launcher = launcher
  }

  public func start() {
    guard task == nil else { return }
    UNUserNotificationCenter.current().delegate = self
    task = Task { [weak self] in
      try? await Task.sleep(for: Self.initialDelay)
      while !Task.isCancelled {
        await self?.checkIfDue()
        try? await Task.sleep(for: Self.pollInterval)
      }
    }
  }

  func checkIfDue() async {
    let settings = GenmaiUpdateSettings.load()
    guard settings.isCheckDue() else { return }
    let release: GenmaiAppRelease?
    do {
      release = try await GenmaiAppRelease.latest()
    } catch {
      NSLog("Genmai: update check failed: %@", "\(error)")
      return
    }
    try? GenmaiUpdateSettings.update { $0.lastCheck = Date() }
    guard let release, settings.shouldOffer(release), release.version != notifiedVersion else { return }
    notifiedVersion = release.version
    await notify(release)
  }

  private func notify(_ release: GenmaiAppRelease) async {
    let center = UNUserNotificationCenter.current()
    guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
      NSLog("Genmai: notifications are not allowed; update %@ is available", release.version)
      return
    }
    let content = UNMutableNotificationContent()
    let japanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
    content.title = japanese ? "Genmai \(release.version) が利用可能です" : "Genmai \(release.version) is available"
    content.body = japanese ? "クリックしてアップデートします。" : "Click to update."
    do {
      try await center.add(
        UNNotificationRequest(identifier: "update-\(release.version)", content: content, trigger: nil))
    } catch {
      NSLog("Genmai: cannot post the update notification: %@", "\(error)")
    }
  }

  public nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    await MainActor.run {
      _ = launcher.openApp(mode: AppScreen.updateDialog.rawValue, extraArg: "", environment: [:])
    }
  }

  /// Shown even while the IME is "active" (it is always in the background).
  public nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }
}
