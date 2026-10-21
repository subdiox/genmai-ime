// Port of mozc/src/session/ime_context_test.cc (3.35.6354).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

@Suite struct ImeContextTests {
  @Test func defaultValues() {
    withScopedSessionEnvironment {
      let context = ImeContext()
      #expect(context.createTime == Date.distantPast)
      #expect(context.lastCommandTime == Date.distantPast)
      #expect(!context.hasConverter)
      #expect(context.state == .none)
      #expect(context.getRequest() == Genmai_Commands_Request())
      #expect(context.getConfig() == ConfigHandler.defaultConfig())
    }
  }

  @Test func basicTest() {
    withScopedSessionEnvironment {
      let request = Genmai_Commands_Request()
      let config = Genmai_Config_Config()
      let keymap = KeyMapManager()

      let converter = MockConverter()
      let context = ImeContext(EngineConverter(converter))

      context.createTime = Date(unixSeconds: 100)
      #expect(context.createTime == Date(unixSeconds: 100))

      context.lastCommandTime = Date(unixSeconds: 12345)
      #expect(context.lastCommandTime == Date(unixSeconds: 12345))

      context.state = .composition
      #expect(context.state == .composition)

      context.setRequest(request)
      context.setConfig(config)
      context.setKeyMapManager(keymap)
      #expect(context.getRequest() == request)
      #expect(context.getConfig() == config)
      #expect(context.getKeyMapManager() === keymap)

      context.clientCapability.textDeletion = .deletePrecedingText
      #expect(context.clientCapability.textDeletion == .deletePrecedingText)

      context.applicationInfo.processID = 123
      #expect(context.applicationInfo.processID == 123)

      context.output.id = 1414
      #expect(context.output.id == 1414)
    }
  }

  @Test func copyContext() {
    withScopedSessionEnvironment {
      let table = Table()
      table.addRule("a", "あ", "")
      table.addRule("n", "ん", "")
      table.addRule("na", "な", "")
      let request = Genmai_Commands_Request()
      var config = Genmai_Config_Config()
      let keymap = KeyMapManager()

      config.sessionKeymap = .chromeos

      let converter = MockConverter()

      let segments = Segments()
      let segment = segments.addSegment()
      segment.setKey("あん")
      let candidate = segment.addCandidate()
      candidate.value = "庵"
      converter.setStartConversion(segments, true)

      do {
        let source = ImeContext(EngineConverter(converter))
        source.setRequest(request)
        source.setConfig(config)
        source.setKeyMapManager(keymap)
        source.composer.setTable(table)

        source.state = .composition
        source.composer.insertCharacter("a")
        source.composer.insertCharacter("n")

        var composition = source.composer.getStringForSubmission()
        #expect(composition == "あｎ")

        let destination = ImeContext(copying: source)

        #expect(source.getRequest() == destination.getRequest())
        #expect(source.getConfig() == destination.getConfig())
        #expect(source.getKeyMapManager() === destination.getKeyMapManager())
        #expect(destination.state == .composition)
        composition = destination.composer.getStringForSubmission()
        #expect(composition == "あｎ")
      }

      do {
        let kCreateTime = Date(unixSeconds: 100)
        let kLastCommandTime = Date(unixSeconds: 200)

        let source = ImeContext(EngineConverter(converter))
        source.setRequest(request)
        source.setConfig(config)
        source.setKeyMapManager(keymap)
        source.composer.setTable(table)
        source.createTime = kCreateTime
        source.lastCommandTime = kLastCommandTime

        source.state = .conversion
        source.composer.insertCharacter("a")
        source.composer.insertCharacter("n")
        _ = source.converter.convert(source.composer)
        let kQuick = "早い"
        source.composer.setSourceText(kQuick)

        var composition = source.composer.getQueryForConversion()
        #expect(composition == "あん")

        var output = Genmai_Commands_Output()
        source.converter.fillOutput(source.composer, &output)
        #expect(output.preedit.segment.count == 1)
        #expect(output.preedit.segment.first?.value == "庵")

        let destination = ImeContext(copying: source)
        #expect(destination.createTime == kCreateTime)
        #expect(destination.lastCommandTime == kLastCommandTime)
        #expect(destination.state == .conversion)
        composition = destination.composer.getQueryForConversion()
        #expect(composition == "あん")

        output = Genmai_Commands_Output()
        destination.converter.fillOutput(source.composer, &output)
        #expect(output.preedit.segment.count == 1)
        #expect(output.preedit.segment.first?.value == "庵")

        #expect(destination.composer.sourceText == kQuick)
      }
    }
  }
}
