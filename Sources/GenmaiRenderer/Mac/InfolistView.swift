// Port of mozc/src/renderer/mac/InfolistView.{h,mm} (3.35.6354).
//
// -drawView: is split into the layout pass (`InfolistViewModel.updateLayout()`, which produces
// `InfolistRenderData`) and the SwiftUI `InfolistView` that draws it.

import AppKit
import GenmaiProtocol
import Observation
import SwiftUI

/// A multi-line text drawn with -drawWithRect:options:NSStringDrawingUsesLineFragmentOrigin.
public struct BoxedText: Equatable, Sendable {
  public var text: String
  public var rect: CGRect
  public var style: RendererStyle.TextStyle
}

public struct InfolistRowData: Equatable, Sendable, Identifiable {
  public var id: Int { row }
  public var row: Int
  public var isFocused: Bool
  /// The focused row rect (filled + stroked) when `isFocused`.
  public var focusedRect: CGRect?
  /// Title / description backgrounds when not focused.
  public var backgrounds: [Background]
  public var title: BoxedText
  public var description: BoxedText

  public struct Background: Equatable, Sendable {
    public var rect: CGRect
    public var color: RendererStyle.RGBAColor
  }
}

public struct InfolistRenderData: Equatable, Sendable {
  public var size: CGSize = .zero
  public var captionBackground: CGRect?
  public var caption: BoxedText?
  public var rows: [InfolistRowData] = []

  public init() {}
}

@MainActor
@Observable
public final class InfolistViewModel {
  public private(set) var candidateWindow = CandidateWindowMessage()
  public private(set) var style: RendererStyle
  public private(set) var renderData = InfolistRenderData()
  @ObservationIgnored private let measurer: any TextMeasuring

  public init(
    style: RendererStyle = RendererStyleHandler.getRendererStyle(),
    measurer: any TextMeasuring = AppKitTextMeasurer()
  ) {
    self.style = style
    self.measurer = measurer
  }

  public func setStyle(_ style: RendererStyle) { self.style = style }

  public func setCandidateWindow(_ candidateWindow: CandidateWindowMessage) {
    self.candidateWindow = candidateWindow
  }

  /// -updateLayout: computes the size (and, unlike the C++ which recomputes in -drawRect:, keeps the
  /// geometry for drawing).
  @discardableResult
  public func updateLayout() -> CGSize {
    renderData = drawView()
    return renderData.size
  }

  private func drawRow(_ row: Int, ypos: CGFloat) -> (InfolistRowData, CGFloat) {
    let infostyle = style.infolistStyle
    let usages = candidateWindow.usages
    let titleStyle = infostyle.titleStyle
    let descStyle = infostyle.descriptionStyle
    let titleWidth =
      Int(infostyle.windowWidth) - Int(titleStyle.leftPadding) - Int(titleStyle.rightPadding)
      - Int(infostyle.windowBorder) * 2 - Int(infostyle.rowRectPadding) * 2
    let descWidth =
      Int(infostyle.windowWidth) - Int(descStyle.leftPadding) - Int(descStyle.rightPadding)
      - Int(infostyle.windowBorder) * 2 - Int(infostyle.rowRectPadding) * 2
    let info = usages.information[row]

    let titleSize = measurer.boundingSize(
      of: info.title, style: titleStyle, width: CGFloat(titleWidth))
    let descSize = measurer.boundingSize(
      of: info.description_p, style: descStyle, width: CGFloat(descWidth))
    let rowRectPadding = CGFloat(infostyle.rowRectPadding)
    let windowBorder = CGFloat(infostyle.windowBorder)
    let windowWidth = CGFloat(infostyle.windowWidth)
    let height = titleSize.height + descSize.height + rowRectPadding * 2

    let titleRect = CGRect(
      x: windowBorder + rowRectPadding + CGFloat(titleStyle.leftPadding), y: ypos + rowRectPadding,
      width: titleSize.width, height: titleSize.height)
    let descRect = CGRect(
      x: windowBorder + rowRectPadding + CGFloat(descStyle.leftPadding),
      y: ypos + rowRectPadding + titleSize.height, width: descSize.width, height: descSize.height)

    let isFocused = usages.hasFocusedIndex && row == Int(usages.focusedIndex)
    var focusedRect: CGRect?
    var backgrounds: [InfolistRowData.Background] = []
    if isFocused {
      focusedRect = CGRect(
        x: windowBorder, y: ypos, width: windowWidth - windowBorder * 2,
        height: titleSize.height + descSize.height + rowRectPadding * 2)
    } else {
      if titleStyle.hasBackgroundColor {
        backgrounds.append(
          .init(
            rect: CGRect(
              x: windowBorder, y: ypos, width: windowWidth - windowBorder * 2,
              height: titleSize.height + rowRectPadding),
            color: titleStyle.backgroundColor))
      }
      if descStyle.hasBackgroundColor {
        backgrounds.append(
          .init(
            rect: CGRect(
              x: windowBorder, y: ypos + titleSize.height + rowRectPadding,
              width: windowWidth - windowBorder * 2, height: descSize.height + rowRectPadding),
            color: descStyle.backgroundColor))
      }
    }
    let data = InfolistRowData(
      row: row, isFocused: isFocused, focusedRect: focusedRect, backgrounds: backgrounds,
      title: BoxedText(
        text: info.title, rect: CGRect(origin: titleRect.origin, size: CGSize(width: CGFloat(titleWidth), height: titleRect.height)),
        style: titleStyle),
      description: BoxedText(
        text: info.description_p, rect: CGRect(origin: descRect.origin, size: CGSize(width: CGFloat(descWidth), height: descRect.height)),
        style: descStyle))
    return (data, height)
  }

  private func drawView() -> InfolistRenderData {
    var data = InfolistRenderData()
    guard candidateWindow.hasUsages else {
      return data
    }
    let infostyle = style.infolistStyle
    let usages = candidateWindow.usages
    let windowBorder = CGFloat(infostyle.windowBorder)
    let windowWidth = CGFloat(infostyle.windowWidth)

    var ypos = windowBorder

    if infostyle.hasCaptionString {
      let captionStyle = infostyle.captionStyle
      let captionHeight = CGFloat(infostyle.captionHeight)
      data.captionBackground = CGRect(
        x: windowBorder, y: ypos, width: windowWidth - windowBorder * 2, height: captionHeight)
      data.caption = BoxedText(
        text: infostyle.captionString,
        rect: CGRect(
          x: windowBorder + CGFloat(infostyle.captionPadding) + CGFloat(captionStyle.leftPadding),
          y: ypos + CGFloat(infostyle.captionPadding), width: windowWidth - windowBorder * 2,
          height: captionHeight),
        style: captionStyle)
    }
    ypos += CGFloat(infostyle.captionHeight)
    for i in usages.information.indices {
      let (row, height) = drawRow(i, ypos: ypos)
      data.rows.append(row)
      ypos += height
    }
    ypos += windowBorder
    data.size = CGSize(width: windowWidth, height: ypos)
    return data
  }
}

public struct InfolistView: View {
  let model: InfolistViewModel

  public init(model: InfolistViewModel) {
    self.model = model
  }

  public var body: some View {
    let data = model.renderData
    let infostyle = model.style.infolistStyle
    ZStack(alignment: .topLeading) {
      if let background = data.captionBackground {
        PlacedRect(rect: background) {
          Rectangle().fill(MacViewUtil.toColor(infostyle.captionBackgroundColor))
        }
      }
      if let caption = data.caption {
        BoxedTextView(boxed: caption)
          .accessibilityAddTraits(.isHeader)
      }
      ForEach(data.rows) { row in
        InfolistRowView(row: row, infostyle: infostyle)
      }
    }
    .frame(width: data.size.width, height: data.size.height, alignment: .topLeading)
    .modifier(CandidatePanelBackground())
    .accessibilityElement(children: .contain)
  }
}

struct InfolistRowView: View {
  let row: InfolistRowData
  let infostyle: RendererStyle.InfolistStyle

  var body: some View {
    ZStack(alignment: .topLeading) {
      if let focusedRect = row.focusedRect {
        PlacedRect(rect: focusedRect) {
          Rectangle()
            .fill(MacViewUtil.toColor(infostyle.focusedBackgroundColor))
            .overlay(
              Rectangle().strokeBorder(
                MacViewUtil.toColor(infostyle.focusedBorderColor), lineWidth: 1))
        }
      }
      ForEach(row.backgrounds.indices, id: \.self) { i in
        PlacedRect(rect: row.backgrounds[i].rect) {
          Rectangle().fill(MacViewUtil.toColor(row.backgrounds[i].color))
        }
      }
      BoxedTextView(boxed: row.title)
      BoxedTextView(boxed: row.description)
    }
    .accessibilityElement(children: .combine)
  }
}

/// `-[NSAttributedString drawWithRect:options:NSStringDrawingUsesLineFragmentOrigin]`.
struct BoxedTextView: View {
  let boxed: BoxedText

  var body: some View {
    Text(verbatim: boxed.text)
      .font(Font(MacViewUtil.toNSFont(boxed.style)))
      .foregroundStyle(
        boxed.style.hasForegroundColor
          ? MacViewUtil.toColor(boxed.style.foregroundColor) : Color(nsColor: .black)
      )
      .fixedSize(horizontal: false, vertical: true)
      .frame(width: boxed.rect.width, alignment: .topLeading)
      .offset(x: boxed.rect.minX, y: boxed.rect.minY)
  }
}
