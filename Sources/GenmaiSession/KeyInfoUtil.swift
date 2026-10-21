// Port of mozc/src/session/key_info_util.{h,cc} (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol

public enum KeyInfoUtil {
  private static func extractSortedDirectModeKeysFromStream(_ ifs: InputFileStream)
    -> [KeyInformation]
  {
    let kModeDirect = "Direct"
    let kModeDirectInput = "DirectInput"

    var result: [KeyInformation] = []

    forEachKeyMapLine(ifs) { line in
      if line.isEmpty || line.utf8.first == UInt8(ascii: "#") {
        // empty or comment
        return
      }
      let rules = splitTabSkipEmpty(line)
      if rules.count != 3 {
        GenmaiLog.error("Invalid format: \(line)")
        return
      }
      if !(rules[0] == kModeDirect || rules[0] == kModeDirectInput) {
        return
      }
      var keyEvent = Genmai_Commands_KeyEvent()
      if KeyParser.parseKey(rules[1], &keyEvent) {
        var info: KeyInformation = 0
        if KeyEventUtil.getKeyInformation(keyEvent, &info) {
          result.append(info)
        }
      }
    }

    result.sort()
    return result
  }

  private static func extractSortedDirectModeKeysFromFile(_ filename: String?) -> [KeyInformation] {
    guard let filename, let ifs = ConfigFileStream.legacyOpen(filename) else {
      GenmaiLog.error("could not open file: \(filename ?? "(null)")")
      return []
    }
    return extractSortedDirectModeKeysFromStream(ifs)
  }

  /// Returns a sorted list of KeyInformation that is assigned in DIRECT mode.
  public static func extractSortedDirectModeKeys(_ config: Genmai_Config_Config) -> [KeyInformation] {
    let keymap = config.sessionKeymap
    if keymap == .custom {
      let customKeymapTable = config.customKeymapTable
      if customKeymapTable.isEmpty {
        GenmaiLog.warning("custom_keymap_table is empty. use default setting")
        let defaultKeymapFile = KeyMapManager.getKeyMapFileName(ConfigHandler.getDefaultKeyMap())
        return extractSortedDirectModeKeysFromFile(defaultKeymapFile)
      }
      return extractSortedDirectModeKeysFromStream(InputFileStream(bytes: Array(customKeymapTable)))
    }
    let keymapFile = KeyMapManager.getKeyMapFileName(keymap)
    return extractSortedDirectModeKeysFromFile(keymapFile)
  }

  /// Returns true if |sorted_keys| contains |key_event|. |sorted_keys| must be
  /// sorted.
  public static func containsKey(_ sortedKeys: [KeyInformation], _ keyEvent: Genmai_Commands_KeyEvent)
    -> Bool
  {
    var keyInfo: KeyInformation = 0
    if !KeyEventUtil.getKeyInformation(keyEvent, &keyInfo) {
      return false
    }
    // std::binary_search
    var lo = 0
    var hi = sortedKeys.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if sortedKeys[mid] < keyInfo {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    return lo < sortedKeys.count && sortedKeys[lo] == keyInfo
  }
}
