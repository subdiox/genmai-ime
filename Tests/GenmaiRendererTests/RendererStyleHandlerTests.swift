// Port of mozc/src/renderer/renderer_style_handler_test.cc (3.35.6354).

import Testing

@testable import GenmaiRenderer

@Suite struct RendererStyleHandlerTests {
  @Test func getRendererStyle() {
    let style = RendererStyleHandler.getRendererStyle()
    #expect(style.hasWindowBorder)
    #expect(style.hasInfolistStyle)
    #expect(style.infolistStyle.hasFocusedBorderColor)
  }

  // Swift-only checks of the embedded text protos.
  @Test func lightStyleValues() {
    let style = RendererStyleHandler.getRendererStyle(.light)
    #expect(style.windowBorder == 1)
    #expect(style.scrollbarWidth == 4)
    #expect(style.rowRectPadding == 1)
    #expect(style.columnMinimumWidthString == "そのほかの文字種")
    #expect(style.logoFileName == "candidate_window_logo.tiff")
    #expect(style.footerBorderColors.count == 1)
    // Default background added by the handler.
    #expect(style.candidateStyle.backgroundColor.r == 255)
    #expect(style.infolistStyle.captionString == "用例")
    #expect(style.infolistStyle.windowWidth == 300)
  }

  @Test func darkStyleValues() {
    let style = RendererStyleHandler.getRendererStyle(.dark)
    #expect(style.borderColor.r == 74)
    #expect(style.candidateStyle.backgroundColor.r == 44)
    #expect(style.infolistStyle.titleStyle.foregroundColor.r == 229)
  }
}
