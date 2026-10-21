// Port of mozc/src/engine/data_loader_test.cc (3.35.6354).
//
// Deviations from C++:
// - The callbacks run in the loader task, so the values they record are kept
//   in a Mutex-protected `CallbackRecorder`.
// - kNeverCalled records an issue instead of ABSL_UNREACHABLE().
// - Every test runs with a temporary user profile (TestWithTempUserProfile).
//   DataLoader.wait() is async (suspends while the loader task runs).

import Foundation
import GenmaiBase
import GenmaiProtocol
import Synchronization
import Testing

@testable import GenmaiCore

private let kMockMagicNumber = "MOCK"
private let kOssMagicNumber = "\u{EF}MOZC\r\n"

private let kNeverCalled: DataLoader.ReloadedCallback = { _ in
  Issue.record("the callback must not be called")
}

/// Thread-safe storage for values recorded by loader callbacks.
private final class CallbackRecorder: Sendable {
  private struct State {
    var called = 0
    var priorities: [Int32] = []
    var filePaths: [String] = []
  }

  private let state = Mutex(State())

  func record(_ response: DataLoader.Response) {
    state.withLock {
      $0.called += 1
      $0.priorities.append(response.response.request.priority)
      $0.filePaths.append(response.response.request.filePath)
    }
  }

  var called: Int { state.withLock { $0.called } }
  var priorities: [Int32] { state.withLock { $0.priorities } }
  var filePaths: [String] { state.withLock { $0.filePaths } }
}

@Suite(.serialized, .enabled(if: EngineTestSupport.hasData, "genmai.data / mock_genmai.data is missing"))
struct DataLoaderTests {
  let mockDataPath = EngineTestSupport.mockDataPath
  let mockRequest = EngineTestSupport.request(EngineTestSupport.mockDataPath, kMockMagicNumber, 50)
  let ossRequest = EngineTestSupport.request(EngineTestSupport.ossDataPath, kOssMagicNumber, 50)

  @Test func asyncBuild() async throws {
    try await SystemUtil.withTempUserProfile { _ in
      var request = Genmai_EngineReloadRequest()
      request.filePath = mockDataPath
      request.magicNumber = kMockMagicNumber

      let dataManager = try DataManager.createFromFile(
        mockDataPath, magic: Array(kMockMagicNumber.utf8))
      let expectedVersion = dataManager.getDataVersion()
      let expectedFilename = try #require(dataManager.getFilename())

      let recorder = CallbackRecorder()
      let checks = CallbackRecorder()

      let loader = DataLoader()
      loader.notifyHighPriorityDataRegisteredForTesting()

      #expect(
        loader.startNewDataBuildTask(request) { response in
          let responseDataManager = try #require(response.modules).getDataManager()
          if responseDataManager.getDataVersion() == expectedVersion
            && responseDataManager.getFilename() == expectedFilename
          {
            checks.record(response)
          }
          recorder.record(response)
        })

      // Sends the same request again. The callback is never called for the
      // duplicate (guaranteed by kNeverCalled). Whether the call returns true
      // depends on whether the first load has already finished by this point,
      // so its return value is timing-dependent and intentionally not asserted.
      loader.startNewDataBuildTask(request, kNeverCalled)

      await loader.wait()

      // Sends the same request. It is NOT accepted, as the loader finishes the
      // loading process.
      #expect(!loader.startNewDataBuildTask(request, kNeverCalled))

      #expect(recorder.called == 1)
      #expect(checks.called == 1)
    }
  }

  @Test func asyncBuildRepeatedly() async {
    await SystemUtil.withTempUserProfile { _ in
      let kMaxPriority: Int32 = 1000

      var expected = kMaxPriority
      let loader = DataLoader()
      loader.notifyHighPriorityDataRegisteredForTesting()
      let recorder = CallbackRecorder()

      // Sending multiple requests with random priority.
      for _ in 0..<20 {
        let priority = Int32.random(in: 0..<kMaxPriority)
        var request = mockRequest
        request.priority = priority

        expected = min(expected, priority)

        loader.startNewDataBuildTask(request) { response in
          // Keeps the modules loaded lastly.
          recorder.record(response)
        }
      }

      await loader.wait()

      // The request with highest priority should be loaded.
      #expect(recorder.called > 0)
      #expect(recorder.priorities.last == expected)
    }
  }

  @Test func asyncBuildWithSamePriorityRepeatedly() async {
    await SystemUtil.withTempUserProfile { _ in
      var expected = ""
      let loader = DataLoader()
      loader.notifyHighPriorityDataRegisteredForTesting()
      let recorder = CallbackRecorder()

      // when the priority is the same, last request is loaded.
      for trial in 0..<2 {
        var request = trial == 0 ? mockRequest : ossRequest
        request.priority = 100
        expected = request.filePath

        loader.startNewDataBuildTask(request) { response in
          recorder.record(response)
        }
      }

      await loader.wait()
      #expect(recorder.filePaths.last == expected)
    }
  }

  @Test func failureCaseDataBroken() async {
    await SystemUtil.withTempUserProfile { _ in
      // Test the case where input file is invalid.
      var request = Genmai_EngineReloadRequest()
      request.filePath = DataManagerTestSupport.sourcePath("engine", "data_loader_test.cc")
      request.magicNumber = kMockMagicNumber

      let loader = DataLoader()
      loader.notifyHighPriorityDataRegisteredForTesting()
      #expect(loader.startNewDataBuildTask(request, kNeverCalled))

      await loader.wait()
      #expect(!loader.startNewDataBuildTask(request, kNeverCalled))
    }
  }

  @Test func failureCaseFileDoesNotExist() async {
    await SystemUtil.withTempUserProfile { _ in
      // Test the case where input file doesn't exist.
      var request = Genmai_EngineReloadRequest()
      request.filePath = "file_does_not_exist"
      request.magicNumber = kMockMagicNumber

      let loader = DataLoader()
      loader.notifyHighPriorityDataRegisteredForTesting()
      #expect(loader.startNewDataBuildTask(request, kNeverCalled))

      await loader.wait()
      #expect(!loader.startNewDataBuildTask(request, kNeverCalled))
    }
  }

  @Test func lowPriorityRequestTest() async {
    await SystemUtil.withTempUserProfile { _ in
      // Starts a new build of a higher request at first.
      let loader = DataLoader()
      loader.notifyHighPriorityDataRegisteredForTesting()

      let recorder = CallbackRecorder()
      #expect(
        loader.startNewDataBuildTask(mockRequest) { response in
          recorder.record(response)
        })

      // Tries another build of a lower request. It waits for the previous
      // task. The new task is not started because of the priority.
      var lowPriorityRequest = mockRequest
      lowPriorityRequest.priority = 100
      #expect(lowPriorityRequest.priority > mockRequest.priority)

      #expect(loader.startNewDataBuildTask(lowPriorityRequest, kNeverCalled))
      await loader.wait()
      #expect(recorder.called == 1)
      #expect(recorder.priorities == [mockRequest.priority])
    }
  }

  @Test func waitHighPriorityDataTest() async {
    await SystemUtil.withTempUserProfile { _ in
      func makeRequest(_ priority: Int32) -> Genmai_EngineReloadRequest {
        var request = mockRequest
        request.priority = priority
        return request
      }

      let loader = DataLoader()
      let recorder = CallbackRecorder()
      let callback: DataLoader.ReloadedCallback = { response in recorder.record(response) }

      // These request are not processed, as they are low priority data.
      #expect(loader.startNewDataBuildTask(makeRequest(50), callback))
      #expect(loader.startNewDataBuildTask(makeRequest(100), callback))
      #expect(loader.startNewDataBuildTask(makeRequest(200), callback))

      // New high priority data is registered.
      #expect(loader.startNewDataBuildTask(makeRequest(10), callback))

      await loader.wait()

      #expect(recorder.called == 1)  // only 10.
      #expect(recorder.priorities == [10])
    }
  }

  @Test func waitHighPriorityDataTimeoutTest() async {
    await SystemUtil.withTempUserProfile { _ in
      func makeRequest(_ priority: Int32) -> Genmai_EngineReloadRequest {
        var request = mockRequest
        request.priority = priority
        return request
      }

      let loader = DataLoader()
      let recorder = CallbackRecorder()
      let callback: DataLoader.ReloadedCallback = { response in recorder.record(response) }

      #expect(loader.startNewDataBuildTask(makeRequest(50), callback))
      #expect(loader.startNewDataBuildTask(makeRequest(100), callback))
      #expect(loader.startNewDataBuildTask(makeRequest(200), callback))

      // No high priority data is registered, so the loader waits for the
      // internal timeout and then loads the current top-priority request
      // (priority = 50).
      await loader.wait()
      #expect(recorder.called == 1)  // only 50.

      // Then priority = 10 is loaded.
      #expect(loader.startNewDataBuildTask(makeRequest(10), callback))

      await loader.wait()

      #expect(recorder.called == 2)  // 50 and 10
      #expect(recorder.priorities == [50, 10])
    }
  }

  // MARK: - Swift only

  @Test func magicNumberBytes() async {
    #expect(DataLoader.magicNumberBytes("MOCK") == Array("MOCK".utf8))
    #expect(DataLoader.magicNumberBytes(kOssMagicNumber) == [0xEF, 0x4D, 0x4F, 0x5A, 0x43, 0x0D, 0x0A])
    #expect(DataLoader.magicNumberBytes("日本") == Array("日本".utf8))
  }

  @Test func waitDoesNotBlock() async {
    let loader = DataLoader()
    loader.notifyHighPriorityDataRegisteredForTesting()
    let recorder = CallbackRecorder()
    await SystemUtil.withTempUserProfile { _ in
      #expect(loader.startNewDataBuildTask(mockRequest) { recorder.record($0) })
      await loader.wait()
    }
    #expect(!loader.isRunning())
    #expect(recorder.called == 1)
  }
}
