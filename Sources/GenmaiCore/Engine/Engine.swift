// Port of mozc/src/engine/engine.{h,cc} (3.35.6354).
//
// Builds and manages a set of modules that are necessary for conversion
// engine.
//
// Deviations from C++:
// - `absl::StatusOr<std::unique_ptr<Engine>>` → `throws`.
// - The converter is held as the concrete `Converter` (shared_ptr in C++)
//   together with its `Modules` (C++ reaches them through
//   `converter_->modules()`, which is `any ConverterModules` in Swift).
// - `loader_response_` is written by the DataLoader callback in the loader's
//   task, so it is guarded by a lock (C++ relies on DataLoader::IsRunning()).
// - There is no CreateDesktopEngine / CreateMobileEngine in this Mozc
//   revision: desktop and mobile engines are the same Engine; the behavior
//   differs by commands::Request (see converter_main's --engine_type).
// - Nothing blocks a thread: `wait()` / `reloadAndWait()` are `async`;
//   `maybeReloadEngine` and `reloadModules` do not wait for the data loader /
//   the old converter (see there). `SetAlwaysWaitForTesting` is replaced by
//   `waitForDataLoader()`.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Synchronization

public final class Engine: EngineInterface, @unchecked Sendable {
  // @unchecked Sendable: like the C++ Engine, the engine is driven by one
  // (session) thread; the only state touched by another task (the loader
  // response) is guarded by a `Mutex`.

  // MARK: - Factories

  /// Creates an instance from a data manager.
  public static func createEngine(_ dataManager: DataManager) throws -> Engine {
    let modules = try Modules.create(dataManager)
    return try createEngine(modules)
  }

  /// Creates an instance with the given modules.
  public static func createEngine(_ modules: Modules) throws -> Engine {
    let engine = Engine()
    try engine.initialize(modules)
    return engine
  }

  /// Creates an engine with no initialization.
  public static func createEngine() -> Engine {
    Engine()
  }

  // MARK: - State

  private let loader = DataLoader()

  private var converter: Converter?
  private var modules: Modules?
  private let minimalConverter: any ConverterInterface
  private let loaderResponse = Mutex<DataLoader.Response?>(nil)
  private var pendingSupplementalModelRequest: Genmai_EngineReloadRequest?

  private init() {
    minimalConverter = createMinimalConverter()
  }

  // MARK: - Accessors

  public func getConverter() -> any ConverterInterface {
    converter ?? minimalConverter
  }

  /// The real converter (nil until initialized).
  public func getConverterImpl() -> Converter? { converter }

  public func createEngineConverter() -> any EngineConverterInterface {
    EngineConverter(getConverter())
  }

  public func getDataVersion() -> String {
    let kDefaultDataVersion = "0.0.0"
    guard let modules, converter != nil else {
      return kDefaultDataVersion
    }
    return modules.getDataManager().getDataVersion()
  }

  /// Returns a list of part-of-speech (e.g. "名詞", "動詞一段") to be used for
  /// the user dictionary GUI tool.
  /// Since the POS set may differ per LM, this function returns available POS
  /// items. In practice, the POS items are rarely changed.
  public func getPosList() -> [String] {
    if converter != nil, let modules {
      return modules.getUserDictionary().getPosList()
    }
    return []
  }

  /// For testing only.
  public func getModulesForTesting() -> Modules {
    precondition(converter != nil)
    return modules!
  }

  // MARK: - Reload / Sync / Wait

  // Functions for Reload, Sync, Wait return true if successfully operated or
  // did nothing.

  @discardableResult
  public func reload() -> Bool { converter?.reload() ?? false }

  @discardableResult
  public func sync() -> Bool { converter?.sync() ?? false }

  @discardableResult
  public func wait() async -> Bool { await converter?.wait() ?? false }

  @discardableResult
  public func reloadAndWait() async -> Bool { reload() ? await wait() : false }

  @discardableResult
  public func clearUserHistory() -> Bool {
    if let converter {
      converter.rewriter.clear()
    }
    return true
  }

  @discardableResult
  public func clearUserPrediction() -> Bool {
    converter?.predictor.clearAllHistory() ?? false
  }

  @discardableResult
  public func addUserHistory(_ key: String, _ value: String) -> Bool {
    converter?.addUserHistory(key, value) ?? false
  }

  /// C++ calls ReloadAndWait() first. Waiting is not possible here (this is
  /// called on the CREATE_SESSION path), and not needed: the background tasks
  /// of the old modules keep them alive until they finish.
  public func reloadModules(_ modules: Modules) throws {
    reload()
    try initialize(modules)
  }

  // MARK: - Data loading

  /// Maybe reload a new data manager. Returns true if reloaded.
  public func maybeReloadEngine(_ response: inout Genmai_EngineReloadResponse) -> Bool {
    // C++ first waits for the loader when converter_ is null or
    // always_wait_for_testing_ is set. Waiting is not possible on this
    // synchronous path; callers that need the loaded data await
    // `waitForDataLoader()` first.

    let loaderResponse: DataLoader.Response? = self.loaderResponse.withLock {
      loader.isRunning() ? nil : $0
    }
    guard let loaderResponse else {
      return false
    }

    response = loaderResponse.response

    var reloaded = false
    if let newModules = loaderResponse.modules {
      do {
        try reloadModules(newModules)
        response.status = .reloaded
        reloaded = true
      } catch {
        GenmaiLog.error("Failed to reload modules: \(error)")
      }
    }
    self.loaderResponse.withLock { $0 = nil }

    return reloaded
  }

  /// Suspends until the data loader task finishes (replaces C++
  /// SetAlwaysWaitForTesting(true), which made MaybeReloadEngine wait).
  public func waitForDataLoader() async {
    await loader.wait()
  }

  @discardableResult
  public func sendEngineReloadRequest(_ request: Genmai_EngineReloadRequest) -> Bool {
    loader.startNewDataBuildTask(request) { [weak self] response in
      guard let self else { return }
      self.loaderResponse.withLock { $0 = response }
    }
  }

  @discardableResult
  public func sendSupplementalModelReloadRequest(_ request: Genmai_EngineReloadRequest) -> Bool {
    if converter != nil, let modules {
      modules.getSupplementalModelInterface().loadAsync(request)
    } else {
      pendingSupplementalModelRequest = request
    }
    return true
  }

  public func clearOldSupplementalModels() {
    if converter != nil, let modules {
      modules.getSupplementalModelInterface().clearOldModels()
    }
  }

  // MARK: - Initialization

  /// Initializes the engine object by the given modules.
  private func initialize(_ modules: Modules) throws {
    let immutableConverterFactory: Converter.ImmutableConverterFactory = { _ in
      ImmutableConverter(modules)
    }

    let predictorFactory: Converter.PredictorFactory = { _, converter, immutableConverter in
      Predictor(modules, converter, immutableConverter)
    }

    let rewriterFactory: Converter.RewriterFactory = { _ in
      RewriterImpl(modules)
    }

    let converter = Converter(
      modules, immutableConverterFactory, predictorFactory, rewriterFactory)

    self.converter = converter
    self.modules = modules
    if let pending = pendingSupplementalModelRequest {
      modules.getSupplementalModelInterface().loadAsync(pending)
      pendingSupplementalModelRequest = nil
    }
  }
}

extension ImmutableConverter {
  /// `ImmutableConverter(const engine::Modules&)`.
  public convenience init(_ modules: Modules) {
    self.init(
      dictionary: modules.getDictionary(),
      suffixDictionary: modules.getSuffixDictionary(),
      userDictionary: modules.getUserDictionary(),
      connector: modules.getConnector(),
      segmenter: modules.getSegmenter(),
      posMatcher: modules.getPosMatcher(),
      posGroup: modules.getPosGroup(),
      suggestionFilter: modules.getSuggestionFilter())
  }
}
