// Port of mozc/src/base/password_manager_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct PasswordManagerTest {
  @Test(.enabled(if: !MacUtil.getSerialNumber().isEmpty, "needs the Mac serial number"))
  func passwordManagerTest() {
    SystemUtil.withTempUserProfile { _ in
      #expect(PasswordManager.initPassword())
      let password1 = PasswordManager.getPassword()
      var password2 = PasswordManager.getPassword()
      #expect(password1 != nil)
      #expect(password1 == password2)

      #expect(PasswordManager.removePassword())
      #expect(PasswordManager.initPassword())
      password2 = PasswordManager.getPassword()
      #expect(password2 != nil)
      #expect(password1 != password2)

      #expect(PasswordManager.removePassword())
      #expect(PasswordManager.initPassword())
      let password3 = PasswordManager.getPassword()
      let password4 = PasswordManager.getPassword()
      #expect(password3 != nil)
      #expect(password3 == password4)
    }
  }
}
