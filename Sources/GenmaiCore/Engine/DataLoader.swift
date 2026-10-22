// Port of mozc/src/engine/data_loader.{h,cc} (3.35.6354).
//
// DataLoader receives requests for loading language model data and loads the
// data from the top priority request. The language model data is
// asynchronously loaded in a background task. `startNewDataBuildTask` accepts
// the request and returns immediately. Once the model is loaded, the callback
// is called. Note that the callback is executed in a different task (not on
// the caller's thread).
//
// Deviations from C++:
// - The loader thread (base/thread.h TaskManager + BackgroundFuture) is a
//   detached Swift task (`DataLoaderTaskManager`; the reload loop is async).
//   `wait()` is `async`: it suspends until the task finishes instead of
//   blocking the calling thread. The task keeps the loader alive, so the
//   destructor does not wait.
// - absl::Notification is `DataLoaderNotification`; the 100 ms wait for high
//   priority data suspends the loader task instead of blocking a thread.
// - `ReloadedCallback` returns normally for absl::OkStatus() and throws
//   otherwise.
// - `EngineReloadRequest.magic_number` is a proto `string` in Swift, which
//   cannot hold the raw byte "\xEF" of the OSS magic number. The magic number
//   bytes are the Unicode scalars of the string when all of them are <= 0xFF
//   (Latin-1, e.g. "\u{EF}MOZC\r\n"), otherwise its UTF-8 bytes. See
//   `DataLoader.magicNumberBytes(_:)`.
// - The loader task runs with the user profile directory of the caller of
//   `startNewDataBuildTask` (SystemUtil's task-local override is not inherited
//   by detached tasks).
// - `GetRequestId` fingerprints the Swift protobuf serialization of the
//   request (only used as an identity within the process).

import Foundation
import GenmaiBase
import GenmaiProtocol
import Synchronization

/// absl::Notification for Swift concurrency.
final class DataLoaderNotification: Sendable {
  private struct State {
    var notified = false
    var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    var nextWaiterId = 0
  }

  private let state = Mutex(State())

  func notify() {
    let continuations = state.withLock { state in
      state.notified = true
      let continuations = Array(state.waiters.values)
      state.waiters.removeAll()
      return continuations
    }
    for continuation in continuations {
      continuation.resume()
    }
  }

  func hasBeenNotified() -> Bool {
    state.withLock { $0.notified }
  }

  /// Suspends until notified or cancelled.
  private func waitForNotification() async {
    let id = state.withLock { state in
      let id = state.nextWaiterId
      state.nextWaiterId += 1
      return id
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeNow = state.withLock { state in
          if state.notified || Task.isCancelled {
            return true
          }
          state.waiters[id] = continuation
          return false
        }
        if resumeNow {
          continuation.resume()
        }
      }
    } onCancel: {
      let continuation = state.withLock { $0.waiters.removeValue(forKey: id) }
      continuation?.resume()
    }
  }

  /// Returns true if notified within `timeout`.
  func waitForNotificationWithTimeout(_ timeout: Duration) async -> Bool {
    if hasBeenNotified() {
      return true
    }
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.waitForNotification() }
      group.addTask { try? await Task.sleep(for: timeout) }
      await group.next()
      group.cancelAll()
    }
    return hasBeenNotified()
  }
}

/// base/thread.h TaskManager for the asynchronous reload loop: runs the
/// scheduled tasks one at a time as detached tasks. Scheduling never blocks
/// (a new task awaits the previous one); `wait()` suspends.
final class DataLoaderTaskManager: Sendable {
  private struct State {
    // The last scheduled task; it finishes after every earlier one.
    var last: Task<Void, Never>?
    // The number of scheduled tasks that have not finished yet.
    var unfinished = 0
  }

  private let state = Mutex(State())

  func schedule(_ body: @escaping @Sendable () async -> Void) {
    state.withLock { state in
      let previous = state.last
      state.unfinished += 1
      state.last = Task.detached { [self] in
        await previous?.value
        await body()
        self.state.withLock { $0.unfinished -= 1 }
      }
    }
  }

  func isRunning() -> Bool {
    state.withLock { $0.unfinished > 0 }
  }

  /// Suspends until the tasks scheduled so far have finished.
  func wait() async {
    await state.withLock { $0.last }?.value
  }
}

public final class DataLoader: Sendable {

  /// The result of a reload, handed over from the loader task to the
  /// callback.
  public final class Response: Sendable {
    public let response: Genmai_EngineReloadResponse
    public let modules: Modules?

    public init(response: Genmai_EngineReloadResponse = Genmai_EngineReloadResponse(), modules: Modules? = nil) {
      self.response = response
      self.modules = modules
    }
  }

  public typealias ReloadedCallback = @Sendable (Response) throws -> Void

  private struct RequestData: CustomStringConvertible {
    var id: UInt64 = 0  // Fingerprint of request.
    var sequenceId: UInt32 = 0  // Sequential id.
    var request = Genmai_EngineReloadRequest()

    var description: String {
      "id=\(id) priority = \(request.priority) sequence_id=\(sequenceId) file_path=\(request.filePath)"
    }
  }

  private struct State {
    var unregistered: Set<UInt64> = []
    var requests: [RequestData] = []

    // Id of the request for the current data.
    // 0 means that no data has been updated yet.
    var currentRequestId: UInt64 = 0

    // Sequential counter assigned to RequestData.
    // When the priority is the same, the larger sequence_id is preferred,
    // meaning that the model registered later is preferred.
    var sequenceIdCounter: UInt32 = 0
  }

  // The internal data are accessed by the main thread and loader's task so
  // need to protect them via mutex.
  private let state = Mutex(State())

  // Notify when a new high priority data is registered.
  private let highPriorityDataRegistered = DataLoaderNotification()

  private let load = DataLoaderTaskManager()

  // The loader task keeps the loader alive until it finishes, so the C++
  // destructor's Wait() is not needed.
  public init() {}

  /// Converts `EngineReloadRequest.magic_number` to the magic number bytes
  /// (see the header comment).
  public static func magicNumberBytes(_ magic: String) -> [UInt8] {
    let scalars = magic.unicodeScalars
    if scalars.allSatisfy({ $0.value <= 0xFF }) {
      return scalars.map { UInt8($0.value) }
    }
    return Array(magic.utf8)
  }

  private static func convertStatus(_ error: any Error) -> Genmai_EngineReloadResponse.Status {
    guard let status = error as? StatusError else {
      return .unknownError
    }
    switch status.code {
    case .ok:
      return .reloadReady
    case .failedPrecondition:
      return .engineVersionMismatch
    case .notFound:
      return .dataMissing
    case .dataLoss:
      return .dataBroken
    case .permissionDenied:
      return .mmapFailure
    default:
      break
    }
    return .unknownError
  }

  private func getRequestId(_ request: Genmai_EngineReloadRequest) -> UInt64 {
    let bytes: [UInt8] = (try? request.serializedBytes()) ?? []
    return bytes.withUnsafeBytes { cityFingerprint(bytes: $0) }
  }

  /// Returns the RequestData to be processed. Return nil when no request
  /// should be processed.
  private func getPendingRequestData() -> RequestData? {
    state.withLock { state in
      guard let top = state.requests.first else {
        return nil
      }
      if top.id == state.currentRequestId {
        return nil
      }
      return top
    }
  }

  /// Accepts engine reload request and immediately returns whether the
  /// `request` is accepted or not.
  private func registerRequest(_ request: Genmai_EngineReloadRequest) -> Bool {
    let id = getRequestId(request)

    return state.withLock { state in
      if id == state.currentRequestId {
        return false
      }

      // The request is invalid since it has already been unregistered.
      if state.unregistered.contains(id) {
        return false
      }

      state.sequenceIdCounter &+= 1

      if let index = state.requests.firstIndex(where: { $0.id == id }) {
        state.requests[index].sequenceId = state.sequenceIdCounter
      } else {
        state.requests.append(
          RequestData(id: id, sequenceId: state.sequenceIdCounter, request: request))
        GenmaiLog.info("New request is registered: \(state.requests.last!)")
      }

      // Sorts the requests so requests[0] stores the request with the highest
      // priority. (The order is total: sequence ids are unique.)
      state.requests.sort { lhs, rhs in
        lhs.request.priority < rhs.request.priority
          || (lhs.request.priority == rhs.request.priority && lhs.sequenceId > rhs.sequenceId)
      }

      // Needs the reloading process only when requests[0] is different from
      // current_request_id_.
      return state.currentRequestId != state.requests[0].id
    }
  }

  /// Unregisters the request.
  private func reportLoadFailure(_ request: RequestData) {
    state.withLock { state in
      GenmaiLog.error("Failed to load data: \(request)")
      let id = request.id
      let countBefore = state.requests.count
      state.requests.removeAll { $0.id == id }
      if state.requests.count != countBefore {
        state.unregistered.insert(id)
      }
    }
  }

  /// Registers the request.
  private func reportLoadSuccess(_ request: RequestData) {
    state.withLock { state in
      GenmaiLog.info("New data is loaded: \(request)")
      state.currentRequestId = request.id
    }
  }

  /// Builds new response from `requestData`.
  private func buildResponse(_ requestData: RequestData) -> Response {
    var result = Genmai_EngineReloadResponse()
    result.status = .dataMissing

    let request = requestData.request
    result.request = request

    // Initializes DataManager
    let dataManager: DataManager
    do {
      dataManager =
        request.hasMagicNumber
        ? try DataManager.createFromFile(
          request.filePath, magic: DataLoader.magicNumberBytes(request.magicNumber))
        : try DataManager.createFromFile(request.filePath)
    } catch {
      GenmaiLog.error("Failed to load data [\(error)] \(requestData)")
      result.status = DataLoader.convertStatus(error)
      assert(result.status != .reloadReady)
      return Response(response: result)
    }

    let modules: Modules
    do {
      modules = try Modules.create(dataManager)
    } catch {
      GenmaiLog.error("Failed to load modules [\(error)] \(requestData)")
      result.status = .dataBroken
      return Response(response: result)
    }

    result.status = .reloadReady
    return Response(response: result, modules: modules)
  }

  /// Executed in the loader's task.
  private func startReloadLoop(_ callback: ReloadedCallback) async {
    while true {
      // No pending request.
      guard let requestData = getPendingRequestData() else {
        break
      }

      // When the high priority data is not registered, waits at most kTimeout
      // until a new high priority data is registered. Retry the loop when a
      // new high priority data is registered while waiting.
      let kTimeout: Duration = .milliseconds(100)
      if !highPriorityDataRegistered.hasBeenNotified(),
        await highPriorityDataRegistered.waitForNotificationWithTimeout(kTimeout)
      {
        continue
      }

      GenmaiLog.info("Building a new module: \(requestData)")
      let response = buildResponse(requestData)
      if response.response.status != .reloadReady {
        reportLoadFailure(requestData)
        continue
      }

      // Passes the modules to the engine via callback.
      do {
        try callback(response)
      } catch {
        reportLoadFailure(requestData)
        continue
      }

      reportLoadSuccess(requestData)
    }
  }

  /// Starts a new data build and reload task. Returns true if the `request`
  /// is accepted. This method returns immediately. The actual data-loading
  /// task is executed asynchronously. When the new module is loaded
  /// successfully, `callback` is called to pass the ownership of the new
  /// modules from the loader to the caller. Note that `callback` is also
  /// executed asynchronously in a different task. `callback` is not called
  /// when the data-loading failed.
  ///
  /// This method is called only by the main engine thread.
  @discardableResult
  public func startNewDataBuildTask(
    _ request: Genmai_EngineReloadRequest, _ callback: @escaping ReloadedCallback
  ) -> Bool {
    if !registerRequest(request) {
      return false
    }

    // Receives high priority data.
    let kHighPriority: Int32 = 10
    if !highPriorityDataRegistered.hasBeenNotified() && request.priority <= kHighPriority {
      highPriorityDataRegistered.notify()
    }

    if !isRunning() {
      // Restarts StartReloadLoop from scratch when the task is not running.
      // The loader task is detached, so the caller's user profile directory
      // (which may be a task-local override in tests) is carried over
      // explicitly: Modules creates the user dictionary and the user history
      // storage there.
      let userProfileDirectory = SystemUtil.getUserProfileDirectory()
      load.schedule { [self] in
        await SystemUtil.withUserProfileDirectory(userProfileDirectory) {
          await startReloadLoop(callback)
        }
      }
    }

    return true
  }

  /// Waits for the loading task (suspends; no thread is blocked).
  public func wait() async { await load.wait() }

  /// Returns true if the loading task is running.
  public func isRunning() -> Bool { load.isRunning() }

  /// Disables specific handling for high priority data.
  public func notifyHighPriorityDataRegisteredForTesting() {
    highPriorityDataRegistered.notify()
  }
}
