// Port of mozc/src/config/config_handler_test.cc (3.35.6354).
//
// Each test runs with a temporary user profile and its own task-local
// ConfigHandler (see ConfigTestSupport.swift), so restoring the config file
// name in a destructor (as the C++ fixture does) is unnecessary. The global
// clock mock is replaced with the task-local `Clock.withClock`.

import Foundation
import GenmaiBase
import GenmaiProtocol
import Synchronization
import Testing

@testable import GenmaiCore

private typealias Config = Genmai_Config_Config

@Suite(.scopedConfigEnvironment) struct ConfigHandlerTest {
  @Test func setConfig() throws {
    var input = Config()
    var output = Config()

    let tempDir = makeTempDirectoryOrDie()
    let configFile = FileUtil.joinPath(tempDir.path, "mozc_config_test_tmp")
    try FileUtil.unlinkIfExists(configFile)
    ConfigHandler.setConfigFileNameForTesting(configFile)
    #expect(ConfigHandler.getConfigFileNameForTesting() == configFile)
    ConfigHandler.reload()

    ConfigHandler.getDefaultConfig(&input)
    input.incognitoMode = true
    #if DEBUG
      input.verboseLevel = 2
    #endif
    ConfigHandler.setConfig(input)
    output = ConfigHandler.getCopiedConfig()
    var output2 = ConfigHandler.getCopiedConfig()
    input.clearGeneralConfig()
    output.clearGeneralConfig()
    output2.clearGeneralConfig()
    #expect(output.textFormatString() == input.textFormatString())
    #expect(output2.textFormatString() == input.textFormatString())

    ConfigHandler.getDefaultConfig(&input)
    input.incognitoMode = false
    #if DEBUG
      input.verboseLevel = 0
    #endif
    ConfigHandler.setConfig(input)
    output = ConfigHandler.getCopiedConfig()
    output2 = ConfigHandler.getCopiedConfig()

    input.clearGeneralConfig()
    output.clearGeneralConfig()
    output2.clearGeneralConfig()
    #expect(output.textFormatString() == input.textFormatString())
    #expect(output2.textFormatString() == input.textFormatString())
    withExtendedLifetime(tempDir) {}
  }

  @Test func setMetadata() {
    func makeConfigWithClock(_ seconds: Int64, _ incognito: Bool) -> Config {
      var input = ConfigHandler.defaultConfig()
      input.incognitoMode = incognito
      let clock = ClockMock(Date(unixSeconds: seconds))
      Clock.withClock(clock) {
        ConfigHandler.setConfig(input)
      }
      return ConfigHandler.getCopiedConfig()
    }

    do {
      let input1 = makeConfigWithClock(1000, false)
      let input2 = makeConfigWithClock(1000, false)
      let input3 = makeConfigWithClock(1001, false)

      // Don't update the config as long as the content is the same.
      #expect(input1.textFormatString() == input2.textFormatString())
      #expect(input2.textFormatString() == input3.textFormatString())
    }

    do {
      let input1 = makeConfigWithClock(1000, true)
      let input2 = makeConfigWithClock(1000, false)
      let input3 = makeConfigWithClock(1001, true)

      #expect(input1.generalConfig.lastModifiedTime == 1000)
      #expect(input2.generalConfig.lastModifiedTime == 1000)
      #expect(input3.generalConfig.lastModifiedTime == 1001)
    }
  }

  @Test func setConfigIdentityCheck() throws {
    var input = Config()

    let tempDir = makeTempDirectoryOrDie()
    let configFile = FileUtil.joinPath(tempDir.path, "mozc_config_test_tmp")
    try FileUtil.unlinkIfExists(configFile)
    ConfigHandler.setConfigFileNameForTesting(configFile)
    #expect(ConfigHandler.getConfigFileNameForTesting() == configFile)
    ConfigHandler.reload()

    ConfigHandler.getDefaultConfig(&input)
    input.incognitoMode = true
    #if DEBUG
      input.verboseLevel = 2
    #endif

    let clock1 = ClockMock(Date(unixSeconds: 1000))
    let output1 = Clock.withClock(clock1) { () -> Config in
      ConfigHandler.setConfig(input)
      return ConfigHandler.getSharedConfig()
    }

    let clock2 = ClockMock(Date(unixSeconds: 1001))
    let output2 = Clock.withClock(clock2) { () -> Config in
      ConfigHandler.setConfig(input)
      return ConfigHandler.getSharedConfig()
    }

    // As SetConfig() is called twice with the same config,
    // GetSharedConfig() must return the identical (including metadata!) config.
    // This also means no actual storage write access happened.
    #expect(output1.textFormatString() == output2.textFormatString())
    withExtendedLifetime(tempDir) {}
  }

  @Test func configFileNameConfig() throws {
    let configFile = "config\(kConfigVersion).db"
    let filename = FileUtil.joinPath(SystemUtil.getUserProfileDirectory(), configFile)
    try FileUtil.unlinkIfExists(filename)
    let input = Config()
    ConfigHandler.setConfig(input)
    #expect(FileUtil.fileExistsOK(filename))
  }

  @Test func setConfigFileName() {
    var genmaiConfig = Config()
    let defaultIncognitoMode = genmaiConfig.incognitoMode
    genmaiConfig.incognitoMode = !defaultIncognitoMode
    ConfigHandler.setConfig(genmaiConfig)
    ConfigHandler.setConfigFileNameForTesting("memory://set_config_file_name_test.db")
    // After SetConfigFileName called, settings are set as default.
    #expect(ConfigHandler.getSharedConfig().incognitoMode == defaultIncognitoMode)
  }

  @Test func loadTestConfig() throws {
    // TODO(yukawa): Generate test data automatically so that we can keep
    //     the compatibility among variety of config files.
    // TODO(yukawa): Enumerate test data in the directory automatically.
    let kDataFiles = [
      "linux_config1.db",
      "mac_config1.db",
      "win_config1.db",
    ]

    for fileName in kDataFiles {
      let srcPath = upstreamSourceFile(["data", "test", "config", fileName])
      let destPath = FileUtil.joinPath(SystemUtil.getUserProfileDirectory(), fileName)
      try FileUtil.copyFile(srcPath, destPath)

      ConfigHandler.setConfigFileNameForTesting("user://\(fileName)")
      ConfigHandler.reload()
    }
  }

  @Test func getDefaultConfig() {
    var output = Config()

    output = Config()
    ConfigHandler.getDefaultConfig(&output)
    // __APPLE__
    #expect(output.sessionKeymap == .kotoeri)
    #expect(output.characterFormRules.count == 13)

    struct TestCase {
      var group: String
      var preeditCharacterForm: Config.CharacterForm
      var conversionCharacterForm: Config.CharacterForm
    }

    let kTestCases: [TestCase] = [
      // "ア"
      TestCase(group: "ア", preeditCharacterForm: .fullWidth, conversionCharacterForm: .fullWidth),
      TestCase(group: "A", preeditCharacterForm: .fullWidth, conversionCharacterForm: .lastForm),
      TestCase(group: "0", preeditCharacterForm: .fullWidth, conversionCharacterForm: .lastForm),
      TestCase(group: "(){}[]", preeditCharacterForm: .fullWidth, conversionCharacterForm: .lastForm),
      TestCase(group: ".,", preeditCharacterForm: .fullWidth, conversionCharacterForm: .lastForm),
      // "。、",
      TestCase(group: "。、", preeditCharacterForm: .fullWidth, conversionCharacterForm: .fullWidth),
      // "・「」"
      TestCase(group: "・「」", preeditCharacterForm: .fullWidth, conversionCharacterForm: .fullWidth),
      TestCase(group: "\"'", preeditCharacterForm: .fullWidth, conversionCharacterForm: .lastForm),
      TestCase(group: ":;", preeditCharacterForm: .fullWidth, conversionCharacterForm: .lastForm),
      TestCase(
        group: "#%&@$^_|`\\", preeditCharacterForm: .fullWidth, conversionCharacterForm: .lastForm),
      TestCase(group: "~", preeditCharacterForm: .fullWidth, conversionCharacterForm: .lastForm),
      TestCase(group: "<>=+-/*", preeditCharacterForm: .fullWidth, conversionCharacterForm: .lastForm),
      TestCase(group: "?!", preeditCharacterForm: .fullWidth, conversionCharacterForm: .lastForm),
    ]
    #expect(output.characterFormRules.count == kTestCases.count)
    for (i, testCase) in kTestCases.enumerated() {
      #expect(output.characterFormRules[i].group == testCase.group)
      #expect(output.characterFormRules[i].preeditCharacterForm == testCase.preeditCharacterForm)
      #expect(
        output.characterFormRules[i].conversionCharacterForm == testCase.conversionCharacterForm)
    }
  }

  @Test func defaultConfig() {
    var config = Config()
    ConfigHandler.getDefaultConfig(&config)
    #expect(ConfigHandler.defaultConfig().textFormatString() == config.textFormatString())
  }

  // Returns concatenated serialized data of |Config::character_form_rules|.
  private static func extractCharacterFormRules(_ config: Config) -> [UInt8] {
    var rules: [UInt8] = []
    for rule in config.characterFormRules {
      let bytes: [UInt8]? = try? rule.serializedBytes()
      #expect(bytes != nil)
      rules += bytes ?? []
    }
    return rules
  }

  @Test func concurrentAccess() async {
    var configs: [Config] = []

    do {
      var config = Config()
      ConfigHandler.getDefaultConfig(&config)
      configs.append(config)
    }
    do {
      var config = Config()
      ConfigHandler.getDefaultConfig(&config)
      config.characterFormRules = []
      do {
        var rule = Config.CharacterFormRule()
        rule.group = "0"
        rule.preeditCharacterForm = .halfWidth
        rule.conversionCharacterForm = .halfWidth
        config.characterFormRules.append(rule)
      }
      do {
        var rule = Config.CharacterFormRule()
        rule.group = "A"
        rule.preeditCharacterForm = .lastForm
        rule.conversionCharacterForm = .lastForm
        config.characterFormRules.append(rule)
      }
      configs.append(config)
    }
    do {
      var config = Config()
      ConfigHandler.getDefaultConfig(&config)
      do {
        var rule = Config.CharacterFormRule()
        rule.group = "0"
        rule.preeditCharacterForm = .halfWidth
        rule.conversionCharacterForm = .halfWidth
        config.characterFormRules.append(rule)
      }
      do {
        var rule = Config.CharacterFormRule()
        rule.group = "A"
        rule.preeditCharacterForm = .lastForm
        rule.conversionCharacterForm = .lastForm
        config.characterFormRules.append(rule)
      }
      configs.append(config)
    }

    // Since |ConfigHandler::SetConfig()| actually updates some metadata in
    // |GeneralConfig|, the returned object from |ConfigHandler::GetConfig()|
    // is not predictable.  Hence we only make sure that
    // |Config::character_form_rules()| is one of expected values.
    var characterFormRulesSet = Set<[UInt8]>()
    for config in configs {
      characterFormRulesSet.insert(Self.extractCharacterFormRules(config))
    }

    // Before starting concurrent test, check to see if it works in single
    // thread.
    for config in configs {
      // Update the global config.
      ConfigHandler.setConfig(config)

      // Check to see if the returned config contains one of expected
      // |Config::character_form_rules()|.
      let rules = Self.extractCharacterFormRules(ConfigHandler.getCopiedConfig())
      #expect(characterFormRulesSet.contains(rules))
    }

    // A Sendable reference: Swift 6.2 does not let task closures capture a noncopyable Mutex local.
    final class Flag: Sendable {
      let value = Mutex(false)
    }
    let cancel = Flag()
    let sendableConfigs = configs
    let sendableSet = characterFormRulesSet
    // Child tasks inherit the task-local ConfigHandler.
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<2 {
        group.addTask {
          var gen = SystemRandomNumberGenerator()
          while !cancel.value.withLock({ $0 }) {
            let nextIndex = Int.random(in: 0..<sendableConfigs.count, using: &gen)
            ConfigHandler.setConfig(sendableConfigs[nextIndex])
            await Task.yield()
          }
        }
      }
      for _ in 0..<4 {
        group.addTask {
          while !cancel.value.withLock({ $0 }) {
            let rules = Self.extractCharacterFormRules(ConfigHandler.getCopiedConfig())
            #expect(sendableSet.contains(rules))
            await Task.yield()
          }
        }
      }
      // Wait for a while to see if everything goes well.
      try? await Task.sleep(for: .milliseconds(250))
      cancel.value.withLock { $0 = true }
    }
  }

  @Test func getSharedConfig() {
    let config1 = ConfigHandler.getSharedConfig()
    let config2 = ConfigHandler.getSharedConfig()
    #expect(config1 == config2)

    var config = config1
    config.incognitoMode = true
    ConfigHandler.setConfig(config)
    let config3 = ConfigHandler.getSharedConfig()
    #expect(config1 != config3)
    #expect(config2 != config3)

    let config4 = ConfigHandler.getSharedConfig()
    #expect(config3 == config4)
  }
}
