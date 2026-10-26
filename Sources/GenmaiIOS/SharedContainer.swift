// Not in Mozc. The Genmai app and its keyboard extension are separate processes; they share the user profile
// (config1.db, the user dictionary, the learning data, keyboard.json) through the app group container.

import Foundation
import GenmaiBase

public enum SharedContainer {
  /// The app group of the Genmai app and the keyboard extension (both entitlements files).
  public static let appGroupIdentifier = "group.io.github.subdiox.genmai"

  /// `<app group container>/Library/Application Support/Genmai`, or nil when the process has no access to the
  /// group (unsigned builds, tests).
  public static var profileDirectory: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
      .appending(path: "Library/Application Support/Genmai", directoryHint: .isDirectory)
  }

  /// Makes the app group's profile the user profile directory of this process (call once at startup, before
  /// anything reads the config). Without the app group the default profile directory stays in use.
  public static func useSharedProfile() {
    guard let directory = profileDirectory else {
      GenmaiLog.warning("App group \(appGroupIdentifier) is not available; using the default profile directory")
      return
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      GenmaiLog.error("Cannot create \(directory.path): \(error)")
    }
    SystemUtil.setUserProfileDirectory(directory.path)
  }
}
