// Port of mozc/src/config/config_handler.{h,cc} (3.35.6354).
//
// Handler of mozc configuration. macOS / OSS behavior only (Android and
// Windows specific branches are dropped).
//
// Deviations from C++:
// - `GetSharedConfig()` returns a `Config` value. Swift protobuf messages are
//   copy-on-write values, so this is as cheap as the C++ shared_ptr and keeps
//   the same thread-safety guarantee (the caller's copy never changes).
// - The C++ handler is a process-wide singleton. That singleton is kept, but
//   because Swift Testing runs tests in parallel, a task-local handler can be
//   installed with `ConfigHandler.withScopedHandlerForTesting(_:)`; it takes
//   precedence over the global one inside the scope (same pattern as
//   `Clock.withClock`).
// - The DEBUG-only text dump (`config1.db.txt`) is not written.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Synchronization

/// config::kConfigVersion
public let kConfigVersion = 1

private let kFileNamePrefix = "user://config"

private func addCharacterFormRule(
  _ group: String, _ preeditForm: Genmai_Config_Config.CharacterForm,
  _ conversionForm: Genmai_Config_Config.CharacterForm, _ config: inout Genmai_Config_Config
) {
  var rule = Genmai_Config_Config.CharacterFormRule()
  rule.group = group
  rule.preeditCharacterForm = preeditForm
  rule.conversionCharacterForm = conversionForm
  config.characterFormRules.append(rule)
}

private func getPlatformSpecificDefaultEmojiSetting() -> Bool {
  // Disable Unicode emoji conversion by default on specific platforms
  // (Android only).
  true
}

private func createDefaultConfig() -> Genmai_Config_Config {
  var config = Genmai_Config_Config()
  config.sessionKeymap = ConfigHandler.getDefaultKeyMap()

  let kFullWidth = Genmai_Config_Config.CharacterForm.fullWidth
  let kLastForm = Genmai_Config_Config.CharacterForm.lastForm
  // "ア"
  addCharacterFormRule("ア", kFullWidth, kFullWidth, &config)
  addCharacterFormRule("A", kFullWidth, kLastForm, &config)
  addCharacterFormRule("0", kFullWidth, kLastForm, &config)
  addCharacterFormRule("(){}[]", kFullWidth, kLastForm, &config)
  addCharacterFormRule(".,", kFullWidth, kLastForm, &config)
  // "。、",
  addCharacterFormRule("。、", kFullWidth, kFullWidth, &config)
  // "・「」"
  addCharacterFormRule("・「」", kFullWidth, kFullWidth, &config)
  addCharacterFormRule("\"'", kFullWidth, kLastForm, &config)
  addCharacterFormRule(":;", kFullWidth, kLastForm, &config)
  addCharacterFormRule("#%&@$^_|`\\", kFullWidth, kLastForm, &config)
  addCharacterFormRule("~", kFullWidth, kLastForm, &config)
  addCharacterFormRule("<>=+-/*", kFullWidth, kLastForm, &config)
  addCharacterFormRule("?!", kFullWidth, kLastForm, &config)

  if getPlatformSpecificDefaultEmojiSetting() {
    config.useEmojiConversion = true
  }

  return config
}

private func setMetaData(_ config: inout Genmai_Config_Config) {
  config.generalConfig.configVersion = UInt32(kConfigVersion)
  config.generalConfig.lastModifiedTime = UInt64(bitPattern: Clock.getUnixSeconds())
  config.generalConfig.lastModifiedProductVersion = Version.getGenmaiVersion()
  config.generalConfig.platform = SystemUtil.getOSVersionString()
}

private func normalizeConfig(_ config: inout Genmai_Config_Config) {
  #if !DEBUG
    // Delete the optional field from the config.
    config.clearVerboseLevel()
    // Fall back if the default value is not the expected value.
    if config.verboseLevel != 0 {
      config.verboseLevel = 0
    }
  #endif

  // mozc::internal::SetConfigVLogLevel(config->verbose_level()) is a no-op
  // here (VLOG is not ported).

  // Initialize platform specific configuration.
  if config.sessionKeymap == .none {
    config.sessionKeymap = ConfigHandler.getDefaultKeyMap()
  }

  if getPlatformSpecificDefaultEmojiSetting() && !config.hasUseEmojiConversion {
    config.useEmojiConversion = true
  }
}

private func serialize(_ config: Genmai_Config_Config) -> [UInt8] {
  (try? config.serializedBytes() as [UInt8]) ?? []
}

private func fingerprint(_ bytes: [UInt8]) -> UInt64 {
  cityFingerprint(bytes: bytes)
}

/// The state of a config handler (ConfigHandlerImpl in C++).
///
/// The C++ `absl::Mutex` is a `Mutex<State>`; it is not recursive and no
/// method re-enters the handler while holding it (`setConfigFileName` releases
/// it before `reload()`, as in C++).
public final class ConfigHandlerImpl: Sendable {
  private struct State {
    var filename: String
    var configHash: UInt64 = 0  // hash of final config.
    var contentHash: UInt64 = 0  // hash w/o metadata.
    var config = Genmai_Config_Config()
  }

  private let state: Mutex<State>
  let defaultConfig: Genmai_Config_Config

  public init() {
    // <user_profile>/config1.db
    state = Mutex(State(filename: "\(kFileNamePrefix)\(kConfigVersion).db"))
    defaultConfig = ConfigHandler.sharedDefaultConfig
    reload()
  }

  func getSharedConfig() -> Genmai_Config_Config {
    state.withLock { $0.config }
  }

  func setConfig(_ input: Genmai_Config_Config) {
    state.withLock { state in
      let configHash = fingerprint(serialize(input))

      // If the wire format of config is identical to the one of the previously
      // stored config, skip updating.
      if state.configHash == configHash {
        return
      }

      var outputConfig = input

      // Fix config because `config` may be broken.
      normalizeConfig(&outputConfig)

      // If the wire format of the config w/o metadata is identical to the one of
      // the previous config, skip updating.
      outputConfig.generalConfig.clearLastModifiedTime()
      let contentHash = fingerprint(serialize(outputConfig))
      if state.contentHash == contentHash {
        return
      }
      state.contentHash = contentHash

      // Set metadata and update `config_hash_`.
      setMetaData(&outputConfig)
      let serialized = serialize(outputConfig)
      state.configHash = fingerprint(serialized)

      ConfigFileStream.atomicUpdate(state.filename, serialized)

      state.config = outputConfig
    }
  }

  /// Reload from file.
  func reload() {
    state.withLock { state in
      let filename = state.filename

      var inputConfig = Genmai_Config_Config()
      if let stream = ConfigFileStream.openReadBinary(filename) {
        do {
          inputConfig = try Genmai_Config_Config(serializedBytes: stream.readAll())
        } catch {
          GenmaiLog.error("\(filename) is broken")
          inputConfig = Genmai_Config_Config()  // revert to default setting
        }
      } else {
        GenmaiLog.error("\(filename) is not found")
      }

      // we set default config when file is broken
      normalizeConfig(&inputConfig)

      state.config = inputConfig
    }
  }

  func setConfigFileName(_ filename: String) {
    state.withLock { $0.filename = filename }
    reload()
  }

  func getConfigFileName() -> String {
    state.withLock { $0.filename }
  }
}

/// This is pure static class.  All public static methods are thread-safe.
public enum ConfigHandler {
  private static let globalImpl = ConfigHandlerImpl()

  // The default config does not depend on the handler state, so it is created
  // once and shared (accessing it does not load the user's config file).
  static let sharedDefaultConfig = createDefaultConfig()

  @TaskLocal static var taskLocalImpl: ConfigHandlerImpl?

  private static var impl: ConfigHandlerImpl {
    taskLocalImpl ?? globalImpl
  }

  /// TESTONLY: runs `body` with a fresh handler (which loads
  /// `user://config1.db` of the current user profile) installed for the
  /// current task only.
  public static func withScopedHandlerForTesting<R>(
    _ handler: ConfigHandlerImpl = ConfigHandlerImpl(), _ body: () throws -> R
  ) rethrows -> R {
    try $taskLocalImpl.withValue(handler, operation: body)
  }

  nonisolated(nonsending) public static func withScopedHandlerForTesting<R>(
    _ handler: ConfigHandlerImpl = ConfigHandlerImpl(),
    _ body: nonisolated(nonsending) () async throws -> R
  ) async rethrows -> R {
    try await $taskLocalImpl.withValue(handler, operation: body)
  }

  /// Returns current config (a copy).
  public static func getCopiedConfig() -> Genmai_Config_Config { impl.getSharedConfig() }

  /// Returns current config. The returned value never changes even if the
  /// config is updated later.
  public static func getSharedConfig() -> Genmai_Config_Config { impl.getSharedConfig() }

  /// Sets config.
  public static func setConfig(_ config: Genmai_Config_Config) { impl.setConfig(config) }

  /// Gets default config value.
  public static func getDefaultConfig(_ config: inout Genmai_Config_Config) {
    config = defaultConfig()
  }

  public static func defaultConfig() -> Genmai_Config_Config { sharedDefaultConfig }

  public static func getSharedDefaultConfig() -> Genmai_Config_Config { sharedDefaultConfig }

  /// Reloads config from storage.
  public static func reload() { impl.reload() }

  /// Sets config file. (for unit testing)
  public static func setConfigFileNameForTesting(_ filename: String) {
    impl.setConfigFileName(filename)
  }

  /// Get config file name.
  public static func getConfigFileNameForTesting() -> String {
    impl.getConfigFileName()
  }

  /// Get default keymap for each platform.
  public static func getDefaultKeyMap() -> Genmai_Config_Config.SessionKeymap {
    // port::IsMacos()
    .kotoeri
  }
}
