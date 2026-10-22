// Port of mozc/src/base/system_util_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

@Suite struct SystemUtilTest {
  @Test func getUserProfileDirectory() {
    // The C++ test has no macOS check ("TODO(komatsu): write a test.").
    // Check the macOS default path and the task-local override instead.
    #expect(SystemUtil.getUserProfileDirectory().hasSuffix("/Library/Application Support/Genmai"))
    SystemUtil.withUserProfileDirectory("/tmp/mozc_profile_test") {
      #expect(SystemUtil.getUserProfileDirectory() == "/tmp/mozc_profile_test")
    }
  }

  @Test func getTotalPhysicalMemoryTest() {
    #expect(SystemUtil.getTotalPhysicalMemory() > 0)
  }

  // Not in the C++ test.
  @Test func paths() {
    #expect(SystemUtil.getServerPath() == "/Library/Input Methods/Genmai.app/Contents/Resources/GenmaiConverter.app")
    #expect(SystemUtil.getOSVersionString().hasPrefix("MacOSX "))
    #expect(!SystemUtil.getUserNameAsString().isEmpty)
  }
}
