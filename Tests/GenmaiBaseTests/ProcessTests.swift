// Tests for GenmaiProcess / MacProcess (ports of mozc/src/base/process.{h,cc}
// and base/mac/mac_process.{h,mm}, 3.35.6354). There is no C++ process_test;
// these check the POSIX behavior.

import Darwin
import Foundation
import Testing

@testable import GenmaiBase

@Suite struct ProcessTests {
  @Test func openBrowserRejectsOtherSchemes() {
    #expect(!GenmaiProcess.openBrowser("mailto:foo@example.com"))
    #expect(!GenmaiProcess.openBrowser("ftp://example.com"))
    #expect(!GenmaiProcess.openBrowser(""))
  }

  @Test func isProcessAlive() {
    #expect(GenmaiProcess.isProcessAlive(Int(getpid()), false))
    #expect(GenmaiProcess.isProcessAlive(0, true))
    #expect(!GenmaiProcess.isProcessAlive(0, false))
    // pid 1 (launchd) is owned by root: EPERM -> default result.
    #expect(GenmaiProcess.isProcessAlive(1, true))
    #expect(!GenmaiProcess.isProcessAlive(1, false))
  }

  @Test func isThreadAlive() {
    #expect(GenmaiProcess.isThreadAlive(123, true))
    #expect(!GenmaiProcess.isThreadAlive(123, false))
  }

  @Test func spawnAndWaitProcess() async {
    var pid = 0
    #expect(GenmaiProcess.spawnProcess("/bin/sleep", "0", &pid))
    #expect(pid != 0)
    // The child is a zombie until reaped; reap it so kill(pid, 0) fails.
    var status: Int32 = 0
    #expect(waitpid(pid_t(pid), &status, 0) == pid_t(pid))
    #expect(await GenmaiProcess.waitProcess(pid, 1000))
    #expect(!GenmaiProcess.isProcessAlive(pid, true))
  }

  @Test func spawnProcessMissingFile() {
    var pid = 0
    #expect(!GenmaiProcess.spawnProcess("/nonexistent/mozc_binary", "", &pid))
  }

  @Test func waitProcessEdgeCases() async {
    #expect(await GenmaiProcess.waitProcess(0, 100))
    #expect(!(await GenmaiProcess.waitProcess(Int(getpid()), 0)))
    // The current process does not terminate within 300 msec.
    #expect(!(await GenmaiProcess.waitProcess(Int(getpid()), 300)))
  }

  @Test func macProcessMissingApplication() {
    #expect(!MacProcess.openApplication("/nonexistent/Foo.app"))
  }
}
