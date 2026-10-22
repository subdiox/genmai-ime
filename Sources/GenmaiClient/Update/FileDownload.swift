// Downloads with progress and checksums, shared by the model installer and the app updater (not part of Mozc).

import CryptoKit
import Foundation
import Synchronization

enum FileDownload {
  /// Downloads `url` to `destination` (which must not exist). `failure` makes the error for an HTTP status other
  /// than 200. Honors task cancellation.
  static func download(
    _ url: URL, to destination: URL, failure: @escaping @Sendable (Int) -> any Error,
    progress: @escaping @Sendable (Int64) -> Void
  ) async throws {
    let downloader = Downloader(destination: destination, failure: failure, progress: progress)
    let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let task = session.downloadTask(with: url)
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        downloader.continuation.withLock { $0 = continuation }
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
  }

  /// The session delegate of one download: reports the bytes received and moves the finished file into place.
  /// (The task delegate of `URLSession.download(from:delegate:)` gets no progress callbacks.)
  private final class Downloader: NSObject, URLSessionDownloadDelegate, Sendable {
    let destination: URL
    let failure: @Sendable (Int) -> any Error
    let progress: @Sendable (Int64) -> Void
    let continuation = Mutex<CheckedContinuation<Void, any Error>?>(nil)
    /// Set when the file arrived but could not be used (HTTP error, move failed).
    let error = Mutex<(any Error)?>(nil)

    init(destination: URL, failure: @escaping @Sendable (Int) -> any Error, progress: @escaping @Sendable (Int64) -> Void) {
      self.destination = destination
      self.failure = failure
      self.progress = progress
    }

    func urlSession(
      _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
      totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
      progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
      // The file is deleted when this returns.
      let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
      do {
        guard status == 200 else { throw failure(status) }
        try FileManager.default.moveItem(at: location, to: destination)
      } catch {
        self.error.withLock { $0 = error }
      }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
      let result = error ?? self.error.withLock { $0 }
      guard let continuation = continuation.withLock({ c in defer { c = nil }; return c }) else { return }
      if let result {
        continuation.resume(throwing: (result as? URLError)?.code == .cancelled ? CancellationError() : result)
      } else {
        continuation.resume()
      }
    }
  }

  /// The SHA-256 of the file at `url` (lowercase hex).
  @concurrent
  static func sha256(of url: URL) async throws -> String {
    var h = SHA256()
    return try hash(url, &h)
  }

  /// The git blob id of the file at `url`: SHA-1 of "blob <size>\0" + content (lowercase hex).
  @concurrent
  static func gitBlobSHA1(of url: URL) async throws -> String {
    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    var h = Insecure.SHA1()
    h.update(data: Data("blob \(size)\0".utf8))
    return try hash(url, &h)
  }

  private static func hash<H: HashFunction>(_ url: URL, _ h: inout H) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
      try Task.checkCancellation()
      h.update(data: chunk)
    }
    return h.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
