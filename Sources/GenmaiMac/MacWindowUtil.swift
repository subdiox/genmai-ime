// Port of the window helpers of mozc/src/base/mac/mac_util.{h,mm} used by the input controller
// (GetFrontmostWindowNameAndOwner, IsSuppressSuggestionWindow) (3.35.6354).
//
// GenmaiBase/Mac/MacUtil.swift does not have them (they need CoreGraphics' window list), so they live here.

import AppKit
import CoreGraphics

public enum MacWindowUtil {
  /// Returns the name and the owner of the frontmost normal-level window.
  @MainActor
  public static func getFrontmostWindowNameAndOwner() -> (name: String, owner: String)? {
    guard
      let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else {
      return nil
    }
    for windowData in windowList {
      if let sharing = windowData[kCGWindowSharingState as String] as? Int,
        sharing == CGWindowSharingType.none.rawValue
      {
        // Skips not shared window.
        continue
      }
      guard let windowName = windowData[kCGWindowName as String] as? String,
        let ownerName = windowData[kCGWindowOwnerName as String] as? String,
        let windowLayer = windowData[kCGWindowLayer as String] as? Int
      else {
        continue
      }
      // Ignores the windows which aren't normal window level.
      if windowLayer != Int(CGWindowLevelForKey(.normalWindow)) {
        continue
      }
      // Hack to ignore the window (name == "" and owner == "Google Chrome")
      // Chrome browser seems to create a window which has no name in front of the
      // actual frontmost Chrome window.
      if windowName.isEmpty && ownerName == "Google Chrome" {
        continue
      }
      return (windowName, ownerName)
    }
    return nil
  }

  public static func isSuppressSuggestionWindow(_ name: String, _ owner: String) -> Bool {
    // Currently we don't support "Firefox", because in Firefox "activateServer:"
    // of IMKStateSetting Protocol is not called when the user changes the
    // browsing tab.
    (owner == "Google Chrome" || owner == "Safari")
      && (name == "Google" || name.hasSuffix(" - Google 検索") || name.hasSuffix(" - Google Search"))
  }
}
