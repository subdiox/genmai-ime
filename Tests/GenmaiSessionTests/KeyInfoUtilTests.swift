// Port of mozc/src/session/key_info_util_test.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

private func pushKey(_ keyString: String, _ keys: inout [KeyInformation]) {
  var key = Genmai_Commands_KeyEvent()
  if !KeyParser.parseKey(keyString, &key) {
    return
  }
  var keyInfo: KeyInformation = 0
  if !KeyEventUtil.getKeyInformation(key, &keyInfo) {
    return
  }
  keys.append(keyInfo)
}

private func parseKey(_ s: String) -> Genmai_Commands_KeyEvent {
  var key = Genmai_Commands_KeyEvent()
  _ = KeyParser.parseKey(s, &key)
  return key
}

@Suite struct KeyInfoUtilTests {
  @Test func extractSortedDirectModeKeys() {
    withScopedSessionEnvironment {
      var config = Genmai_Config_Config()
      ConfigHandler.getDefaultConfig(&config)

      let kCustomKeymapTable =
        "status\tkey\tcommand\n"
        + "DirectInput\tHenkan\tIMEOn\n"
        + "DirectInput\tCtrl j\tIMEOn\n"
        + "DirectInput\tCtrl k\tIMEOff\n"
        + "DirectInput\tCtrl l\tLaunchWordRegisterDialog\n"
        + "Precomposition\tCtrl m\tIMEOn\n"
      config.sessionKeymap = .custom
      config.customKeymapTable = Data(kCustomKeymapTable.utf8)

      let actual = KeyInfoUtil.extractSortedDirectModeKeys(config)

      var expected: [KeyInformation] = []
      pushKey("HENKAN", &expected)
      pushKey("Ctrl j", &expected)
      pushKey("Ctrl k", &expected)
      pushKey("Ctrl l", &expected)
      expected.sort()

      #expect(actual == expected)
    }
  }

  @Test func containsKey() {
    var directModeKeys: [KeyInformation] = []
    pushKey("HENKAN", &directModeKeys)
    pushKey("Ctrl j", &directModeKeys)
    pushKey("Ctrl k", &directModeKeys)
    pushKey("Ctrl l", &directModeKeys)
    directModeKeys.sort()

    #expect(KeyInfoUtil.containsKey(directModeKeys, parseKey("HENKAN")))
    #expect(!KeyInfoUtil.containsKey(directModeKeys, parseKey("EISU")))
    #expect(KeyInfoUtil.containsKey(directModeKeys, parseKey("ctrl j")))
    #expect(KeyInfoUtil.containsKey(directModeKeys, parseKey("ctrl k")))
    #expect(KeyInfoUtil.containsKey(directModeKeys, parseKey("ctrl l")))
    #expect(!KeyInfoUtil.containsKey(directModeKeys, parseKey("ctrl m")))
  }
}
