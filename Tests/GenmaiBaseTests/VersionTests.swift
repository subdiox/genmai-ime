// Port of mozc/src/base/version_test.cc (3.35.6354).

import Testing
@testable import GenmaiBase

@Suite struct VersionTest {
  @Test func basicTest() {
    #expect(Version.getGenmaiVersion() == VersionDef.kGenmaiVersion)
  }

  @Test func versionNumberTest() {
    let major = Version.getGenmaiVersionMajor()
    let minor = Version.getGenmaiVersionMinor()
    let buildNumber = Version.getGenmaiVersionBuildNumber()
    let revision = Version.getGenmaiVersionRevision()
    #expect(Version.getGenmaiVersion() == "\(major).\(minor).\(buildNumber).\(revision)")
  }

  @Test func compareVersion() {
    #expect(!Version.compareVersion("0.0.0.0", "0.0.0.0"))
    #expect(!Version.compareVersion("1.2.3.4", "1.2.3.4"))
    #expect(Version.compareVersion("0.0.0.0", "0.0.0.1"))
    #expect(Version.compareVersion("0.0.1.2", "0.1.2.3"))
    #expect(Version.compareVersion("1.2.3.4", "5.2.3.4"))
    #expect(Version.compareVersion("1.2.3.4", "1.5.3.4"))
    #expect(Version.compareVersion("1.2.3.4", "1.2.5.4"))
    #expect(Version.compareVersion("1.2.3.4", "1.2.3.5"))
    #expect(!Version.compareVersion("5.2.3.4", "1.2.3.4"))
    #expect(!Version.compareVersion("1.5.3.4", "1.2.3.4"))
    #expect(!Version.compareVersion("1.2.5.4", "1.2.3.4"))
    #expect(!Version.compareVersion("1.2.3.5", "1.2.3.4"))
    #expect(Version.compareVersion("1.2.3.4", "15.2.3.4"))
    #expect(Version.compareVersion("1.2.3.4", "1.25.3.4"))
    #expect(Version.compareVersion("1.2.3.4", "1.2.35.4"))
    #expect(Version.compareVersion("1.2.3.4", "1.2.3.45"))
    #expect(!Version.compareVersion("15.2.3.4", "1.2.3.4"))
    #expect(!Version.compareVersion("1.25.3.4", "1.2.3.4"))
    #expect(!Version.compareVersion("1.2.35.4", "1.2.3.4"))
    #expect(!Version.compareVersion("1.2.3.45", "1.2.3.4"))
    // Always return false if "Unknown" is passed.
    #expect(!Version.compareVersion("Unknown", "Unknown"))
    #expect(!Version.compareVersion("0.0.0.0", "(Unknown)"))
    #expect(!Version.compareVersion("Unknown", "0.0.0.0"))
    #expect(!Version.compareVersion("0.0.0.0", "Unknown"))
    #expect(!Version.compareVersion("(Unknown)", "(Unknown)"))
    #expect(!Version.compareVersion("(Unknown)", "0.0.0.0"))
  }
}
