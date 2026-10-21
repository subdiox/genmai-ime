// Port of mozc/src/base/process_mutex_test.cc (3.35.6354).
//
// ForkProcessMutexTest is not ported: fork() in the (multi-threaded) Swift
// test runner is unsafe.

import Testing
@testable import GenmaiBase

private let kName = "process_mutex_test"

@Suite struct ProcessMutexTest {
  // Runs `body` with a temporary user profile and checks the lock file was
  // removed afterwards (the C++ fixture's TearDown).
  private func withFixture(_ body: () -> Void) {
    SystemUtil.withTempUserProfile { _ in
      body()
      let mutex = ProcessMutex(kName)
      #expect(!FileUtil.fileExistsOK(mutex.lockFilename),
              "Lock file unexpectedly remains: \(mutex.lockFilename)")
    }
  }

  @Test func basicTest() {
    withFixture {
      let m1 = ProcessMutex(kName)
      #expect(m1.lock())
      #expect(m1.locked)

      let m2 = ProcessMutex(kName)
      #expect(!m2.lock())
      #expect(!m2.locked)

      let m3 = ProcessMutex(kName)
      #expect(!m3.lock())
      #expect(!m3.locked)

      #expect(m1.unlock())
      #expect(!m1.locked)

      #expect(m2.lock())
      #expect(m2.locked)

      #expect(!m3.lock())
      #expect(!m3.locked)
      // m2 is unlocked by deinit.
      m2.unlock()
    }
  }

  @Test func recursiveLockTest() {
    withFixture {
      let mutex = ProcessMutex(kName)
      #expect(mutex.lock())
      #expect(mutex.locked)
      #expect(!mutex.lock(), "Recursive lock should fail.")
      #expect(mutex.locked)
      #expect(mutex.unlock())
      #expect(!mutex.locked)
    }
  }

  // Not in the C++ test.
  @Test func lockAndWrite() throws {
    try SystemUtil.withTempUserProfile { (_: String) throws in
      let mutex = ProcessMutex(kName)
      #expect(mutex.lockAndWrite("hello"))
      #expect(try FileUtil.getContents(mutex.lockFilename) == "hello")
      #expect(mutex.unlock())
      #expect(!FileUtil.fileExistsOK(mutex.lockFilename))
    }
  }
}
