// Tests of the CandidateView / InfolistView layout logic (CandidateView.swift has its own design;
// InfolistView.mm) with deterministic text metrics, and of the CandidateController coordinate helpers.
// The C++ has no unit tests for these Cocoa views.

import AppKit
import GenmaiClient
import GenmaiProtocol
import Testing

@testable import GenmaiRenderer

/// width = 10 px per UTF-16 unit, height = font size + 2.
struct FixedMeasurer: TextMeasuring {
  func size(of text: String, style: RendererStyle.TextStyle) -> CGSize {
    CGSize(width: CGFloat(text.utf16.count * 10), height: style.fontSize + 2)
  }

  func boundingSize(of text: String, style: RendererStyle.TextStyle, width: CGFloat) -> CGSize {
    let total = CGFloat(text.utf16.count * 10)
    let lines = max(1, Int((total / width).rounded(.up)))
    return CGSize(width: min(total, width), height: CGFloat(lines) * (style.fontSize + 2))
  }
}

@MainActor
final class RecordingSender: SendCommandInterface {
  var commands: [SessionCommand] = []
  func sendCommand(_ command: SessionCommand) -> Output? {
    commands.append(command)
    return Output()
  }
}

func makeCandidateWindow() -> CandidateWindowMessage {
  var window = CandidateWindowMessage()
  window.size = 10
  window.focusedIndex = 0
  let values = [("あ", "1", "D"), ("いい", "2", ""), ("う", "3", "")]
  for (i, (value, shortcut, description)) in values.enumerated() {
    var candidate = CandidateWindowMessage.Candidate()
    candidate.index = UInt32(i)
    candidate.id = Int32(100 + i)
    candidate.value = value
    candidate.annotation.shortcut = shortcut
    if !description.isEmpty {
      candidate.annotation.description_p = description
    }
    if i == 2 {
      candidate.annotation.prefix = "["
      candidate.annotation.suffix = "]"
    }
    if i == 0 {
      candidate.informationID = 7
    }
    window.candidate.append(candidate)
  }
  window.footer.label = "L"
  window.footer.indexVisible = true
  return window
}

@MainActor
@Suite struct CandidateViewTests {
  @Test func updateLayout() throws {
    let model = CandidateViewModel(measurer: FixedMeasurer())
    model.setCandidateWindow(makeCandidateWindow())
    let size = model.updateLayout()

    // Columns: shortcut 4 + 10, gap 10, candidate max("[う]") 30 + 16, description "D" 10 + book icon 16 + 4
    // extended so that candidate + description reach the 120 px minimum -> 14 + 10 + 46 + 74 = 144.
    // width = 6 * 2 (window padding) + 5 * 2 (row padding) + 144 + 8 (scroll bar) = 174.
    // height = 12 + 3 rows * (20 + 10) + footer 26 = 128.
    #expect(size == Size(174, 128))
    #expect(model.focusedRow == 0)
    let data = model.renderData
    #expect(data.rows.count == 3)
    #expect(data.rows[1].rowRect == Rect(6, 36, 154, 30))
    // Candidate text with prefix / suffix.
    #expect(data.rows.map(\.value) == ["あ", "いい", "[う]"])
    #expect(data.rows.map(\.shortcut) == ["1", "2", "3"])
    #expect(data.rows[0].description == CandidateDescription("D"))
    #expect(data.rows[0].candidateRect == CGRect(x: 35, y: 11, width: 46, height: 20))
    #expect(data.rows[0].shortcutRect == CGRect(x: 15, y: 11, width: 10, height: 20))
    #expect(data.rows[0].descriptionRect == CGRect(x: 81, y: 11, width: 74, height: 20))
    #expect(data.rows[0].hasInformation)
    #expect(!data.rows[1].hasInformation)
    // Scroll bar since 3 < 10 candidates.
    #expect(data.scrollBar?.barRect == Rect(160, 6, 8, 90))
    let footer = try #require(data.footer)
    #expect(footer.rect == CGRect(x: 6, y: 96, width: 162, height: 26))
    #expect(footer.label == "L")
    #expect(footer.index == "1 / 10")
    // The candidate column (aligned under the preedit by CandidateController).
    #expect(model.tableLayout.getColumnRect(ColumnType.candidate.rawValue).left == 35)
  }

  @Test func noScrollBarWhenAllCandidatesShown() {
    let model = CandidateViewModel(measurer: FixedMeasurer())
    var window = makeCandidateWindow()
    window.size = 3
    window.clearFooter()
    model.setCandidateWindow(window)
    let size = model.updateLayout()
    #expect(model.renderData.scrollBar == nil)
    #expect(model.renderData.footer == nil)
    #expect(size == Size(166, 102))
  }

  @Test func aiDescription() {
    #expect(CandidateDescription("AI") == CandidateDescription(isAIForTest: true, text: ""))
    #expect(CandidateDescription("AI 環境依存") == CandidateDescription(isAIForTest: true, text: "環境依存"))
    #expect(CandidateDescription("AIR") == CandidateDescription(isAIForTest: false, text: "AIR"))
    #expect(CandidateDescription("[全]カタカナ") == CandidateDescription(isAIForTest: false, text: "[全]カタカナ"))

    let model = CandidateViewModel(measurer: FixedMeasurer())
    var window = makeCandidateWindow()
    window.size = 3
    window.clearFooter()
    window.candidate[1].annotation.description_p = "AI"
    model.setCandidateWindow(window)
    let size = model.updateLayout()
    // Badge: padding 5 * 2 + icon 10 + spacing 2 + "AI" 20 = 42, + book icon 16 + 4 trailing -> description
    // column 62; candidate + description = 108 < 120 -> 74.
    #expect(model.aiBadgeWidth == 42)
    #expect(size == Size(166, 102))
    #expect(model.renderData.rows[1].description.isAI)
  }

  @Test func mouseClickSelectsCandidate() {
    let model = CandidateViewModel(measurer: FixedMeasurer())
    let sender = RecordingSender()
    model.commandSender = sender
    model.setCandidateWindow(makeCandidateWindow())
    model.updateLayout()

    model.mouseDown(at: CGPoint(x: 10, y: 40))
    #expect(model.focusedRow == 1)
    model.mouseUp(at: CGPoint(x: 10, y: 40))
    #expect(sender.commands.count == 1)
    #expect(sender.commands[0].type == .selectCandidate)
    #expect(sender.commands[0].id == 101)

    // Outside of rows (the footer): nothing.
    model.mouseUp(at: CGPoint(x: 10, y: 100))
    #expect(sender.commands.count == 1)
  }

  @Test func focusedRowRelativeToPage() {
    let model = CandidateViewModel(measurer: FixedMeasurer())
    var window = makeCandidateWindow()
    for i in window.candidate.indices {
      window.candidate[i].index += 9
    }
    window.focusedIndex = 10
    model.setCandidateWindow(window)
    model.updateLayout()
    #expect(model.focusedRow == 1)
    #expect(model.renderData.footer?.index == "11 / 10")
  }
}

extension CandidateDescription {
  init(isAIForTest isAI: Bool, text: String) {
    self.init("")
    self.isAI = isAI
    self.text = text
  }
}

@MainActor
@Suite struct InfolistViewTests {
  @Test func updateLayout() throws {
    let model = InfolistViewModel(measurer: FixedMeasurer())
    var window = makeCandidateWindow()
    var info = Genmai_Commands_Information()
    info.title = "TT"
    info.description_p = String(repeating: "d", count: 30)
    window.usages.information = [info, info]
    window.usages.focusedIndex = 1
    model.setCandidateWindow(window)
    let size = model.updateLayout()
    // Text width 300 - 8 * 2 - 8 * 2 = 268: title 15, description 300 px -> 2 lines * 14 = 28.
    // Entry 8 + 15 + 2 + 28 + 8 = 61; caption 24; 8 + 24 + 61 + 2 + 61 + 8 = 164.
    #expect(size == CGSize(width: 300, height: 164))
    let data = model.renderData
    #expect(data.caption?.text == "用例")
    #expect(data.rows.map(\.isFocused) == [false, true])
    #expect(data.rows[0].rect == CGRect(x: 8, y: 32, width: 284, height: 61))
    #expect(data.rows[1].rect == CGRect(x: 8, y: 95, width: 284, height: 61))
    #expect(data.rows[0].title.rect == CGRect(x: 16, y: 40, width: 268, height: 15))
    #expect(data.rows[0].description.rect == CGRect(x: 16, y: 57, width: 268, height: 28))
  }

  @Test func noUsages() {
    let model = InfolistViewModel(measurer: FixedMeasurer())
    model.setCandidateWindow(makeCandidateWindow())
    #expect(model.updateLayout() == .zero)
  }
}

@Suite struct CandidateControllerHelperTests {
  @Test func coordinateConversion() {
    #expect(originPointInCocoaCoord(Rect(10, 20, 30, 40)) == NSPoint(x: 10, y: -60))
    #expect(rectInGenmaiCoord(NSRect(x: 0, y: 0, width: 1440, height: 900)) == Rect(0, -900, 1440, 900))
  }

  @Test func nearestDisplay() {
    let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900), NSRect(x: 1440, y: 0, width: 1920, height: 1080)]
    // A point inside the second screen (cocoa x = 2000, y = 500 -> mozc bottom = -500).
    #expect(getNearestDisplayRect(Rect(2000, -510, 10, 10), screens: screens) == Rect(1440, -1080, 1920, 1080))
    // Far left: nearest is the first screen.
    #expect(getNearestDisplayRect(Rect(-500, -510, 10, 10), screens: screens) == Rect(0, -900, 1440, 900))
    #expect(getBaseScreenHeight(screens: screens) == 900)
  }
}
