// Port of mozc/src/engine/engine_interface.h (3.35.6354).
//
// Builds and manages a set of modules that are necessary for conversion,
// prediction and rewrite. For example, a typical implementation of this
// interface would hold the dictionary shared among converters and predictors
// as well as Kana-Kanji converter/predictor, etc.
//
// Deviations from C++:
// - The C++ virtual defaults are protocol-extension defaults. NOTE (protocol
//   default dispatch pitfall, see CLAUDE.md): a class hierarchy conforming to
//   this protocol must implement every requirement in its base class and
//   `override` it in subclasses. `Engine` implements all of them.
// - `EngineReloadResponse*` out-parameter is `inout`.
// - `Wait()` and `ReloadAndWait()` are `async`.

import GenmaiProtocol

public protocol EngineInterface: AnyObject {
  /// Creates new session converter.
  /// This method is called per input context.
  func createEngineConverter() -> any EngineConverterInterface

  /// Gets the version of underlying data set.
  func getDataVersion() -> String

  /// Reloads internal data, e.g., user dictionary, etc.
  /// This function may read data from local files.
  /// Returns true if successfully reloaded or did nothing.
  @discardableResult func reload() -> Bool

  /// Synchronizes internal data, e.g., user dictionary, etc.
  /// This function may write data into local files.
  /// Returns true if successfully synced or did nothing.
  @discardableResult func sync() -> Bool

  /// Waits for reloader (suspends; no thread is blocked).
  /// Returns true if successfully waited or did nothing.
  @discardableResult func wait() async -> Bool

  /// Reloads internal data and wait for reloader.
  /// Returns true if successfully reloaded and waited, or did nothing.
  @discardableResult func reloadAndWait() async -> Bool

  /// Clears user history data.
  @discardableResult func clearUserHistory() -> Bool

  /// Clears user prediction data.
  @discardableResult func clearUserPrediction() -> Bool

  /// Adds key/value to user history data. `key` can be empty.
  @discardableResult func addUserHistory(_ key: String, _ value: String) -> Bool

  /// Gets the user POS list.
  func getPosList() -> [String]

  /// Maybe reload a new data manager. Returns true if reloaded.
  func maybeReloadEngine(_ response: inout Genmai_EngineReloadResponse) -> Bool

  /// Clears old supplemental models to avoid memory leaks.
  func clearOldSupplementalModels()

  @discardableResult func sendEngineReloadRequest(_ request: Genmai_EngineReloadRequest) -> Bool

  @discardableResult func sendSupplementalModelReloadRequest(
    _ request: Genmai_EngineReloadRequest) -> Bool
}

extension EngineInterface {
  @discardableResult public func reload() -> Bool { true }
  @discardableResult public func sync() -> Bool { true }
  @discardableResult public func wait() async -> Bool { true }
  @discardableResult public func reloadAndWait() async -> Bool { true }
  @discardableResult public func clearUserHistory() -> Bool { true }
  @discardableResult public func clearUserPrediction() -> Bool { true }
  @discardableResult public func addUserHistory(_ key: String, _ value: String) -> Bool { true }
  public func getPosList() -> [String] { [] }
  public func maybeReloadEngine(_ response: inout Genmai_EngineReloadResponse) -> Bool { false }
  public func clearOldSupplementalModels() {}
  @discardableResult public func sendEngineReloadRequest(_ request: Genmai_EngineReloadRequest)
    -> Bool
  { false }
  @discardableResult public func sendSupplementalModelReloadRequest(
    _ request: Genmai_EngineReloadRequest
  ) -> Bool { false }
}
