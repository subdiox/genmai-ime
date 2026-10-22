// The infolist window's view (usage examples of the focused candidate). Based on
// mozc/src/renderer/mac/InfolistView.{h,mm} (3.35.6354), with Genmai's own card layout instead of the colors and
// metrics of renderer_style.textproto: the layout pass (`InfolistViewModel.updateLayout()`) measures the texts and
// produces `InfolistRenderData`, which the SwiftUI `InfolistView` draws.

import AppKit
import GenmaiProtocol
import Observation
import SwiftUI

/// A multi-line text placed at `rect` (top-left origin).
public struct BoxedText: Equatable, Sendable {
  public var text: String
  public var rect: CGRect
  public var fontSize: CGFloat
}

/// Metrics of the infolist panel.
public enum InfolistDesign {
  public static let width: CGFloat = 300
  /// Space between the window edge and the content.
  public static let padding: CGFloat = 8
  public static let captionHeight: CGFloat = 24
  public static let captionFontSize: CGFloat = 11
  /// Padding inside an entry.
  public static let entryPadding: CGFloat = 8
  public static let entrySpacing: CGFloat = 2
  public static let titleFontSize: CGFloat = 13
  public static let descriptionFontSize: CGFloat = 12
  public static let titleSpacing: CGFloat = 2

  static func textStyle(size: CGFloat) -> RendererStyle.TextStyle {
    var style = RendererStyle.TextStyle()
    style.fontSize = size
    return style
  }
}

public struct InfolistRowData: Equatable, Sendable, Identifiable {
  public var id: Int { row }
  public var row: Int
  public var isFocused: Bool
  /// The entry's background (highlighted when focused).
  public var rect: CGRect
  public var title: BoxedText
  public var description: BoxedText
}

public struct InfolistRenderData: Equatable, Sendable {
  public var size: CGSize = .zero
  public var caption: BoxedText?
  public var rows: [InfolistRowData] = []

  public init() {}
}

@MainActor
@Observable
public final class InfolistViewModel {
  public private(set) var candidateWindow = CandidateWindowMessage()
  /// Only the caption ("用例") comes from the renderer style.
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

  /// Computes the size and the geometry for drawing.
  @discardableResult
  public func updateLayout() -> CGSize {
    renderData = layout()
    return renderData.size
  }

  private func textSize(_ text: String, size: CGFloat, width: CGFloat) -> CGSize {
    let measured = measurer.boundingSize(of: text, style: InfolistDesign.textStyle(size: size), width: width)
    return CGSize(width: measured.width.rounded(.up), height: measured.height.rounded(.up))
  }

  private func layout() -> InfolistRenderData {
    var data = InfolistRenderData()
    guard candidateWindow.hasUsages else {
      return data
    }
    let d = InfolistDesign.self
    let usages = candidateWindow.usages
    let entryWidth = d.width - d.padding * 2
    let textWidth = entryWidth - d.entryPadding * 2
    var y = d.padding
    let caption = style.infolistStyle.captionString
    if !caption.isEmpty {
      data.caption = BoxedText(
        text: caption,
        rect: CGRect(x: d.padding + d.entryPadding, y: y, width: textWidth, height: d.captionHeight),
        fontSize: d.captionFontSize)
      y += d.captionHeight
    }
    for (row, info) in usages.information.enumerated() {
      if row > 0 {
        y += d.entrySpacing
      }
      let titleHeight = textSize(info.title, size: d.titleFontSize, width: textWidth).height
      let descriptionHeight = textSize(info.description_p, size: d.descriptionFontSize, width: textWidth).height
      let x = d.padding + d.entryPadding
      let titleY = y + d.entryPadding
      let descriptionY = titleY + titleHeight + d.titleSpacing
      let height = d.entryPadding * 2 + titleHeight + d.titleSpacing + descriptionHeight
      data.rows.append(
        InfolistRowData(
          row: row, isFocused: usages.hasFocusedIndex && row == Int(usages.focusedIndex),
          rect: CGRect(x: d.padding, y: y, width: entryWidth, height: height),
          title: BoxedText(
            text: info.title, rect: CGRect(x: x, y: titleY, width: textWidth, height: titleHeight),
            fontSize: d.titleFontSize),
          description: BoxedText(
            text: info.description_p,
            rect: CGRect(x: x, y: descriptionY, width: textWidth, height: descriptionHeight),
            fontSize: d.descriptionFontSize)))
      y += height
    }
    y += d.padding
    data.size = CGSize(width: d.width, height: y)
    return data
  }
}

/// The usage examples of the focused candidate, next to the candidate window: a caption and one card per entry,
/// the focused entry highlighted.
public struct InfolistView: View {
  let model: InfolistViewModel

  public init(model: InfolistViewModel) {
    self.model = model
  }

  public var body: some View {
    let data = model.renderData
    ZStack(alignment: .topLeading) {
      if let caption = data.caption {
        InfolistCaptionView(caption: caption)
      }
      ForEach(data.rows) { row in
        InfolistRowView(row: row)
      }
    }
    .frame(width: data.size.width, height: data.size.height, alignment: .topLeading)
    .modifier(CandidatePanelBackground())
    .accessibilityElement(children: .contain)
  }
}

struct InfolistCaptionView: View {
  let caption: BoxedText

  var body: some View {
    PlacedRect(rect: caption.rect) {
      Label {
        Text(verbatim: caption.text)
      } icon: {
        Image(systemName: "book.closed.fill")
      }
      .font(.system(size: caption.fontSize, weight: .semibold))
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    .accessibilityAddTraits(.isHeader)
  }
}

struct InfolistRowView: View {
  let row: InfolistRowData

  var body: some View {
    ZStack(alignment: .topLeading) {
      if row.isFocused {
        PlacedRect(rect: row.rect) {
          RoundedRectangle(cornerRadius: CandidateDesign.rowCornerRadius, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
        }
      }
      BoxedTextView(boxed: row.title, weight: .semibold, style: .primary)
      BoxedTextView(boxed: row.description, weight: .regular, style: .secondary)
    }
    .accessibilityElement(children: .combine)
  }
}

struct BoxedTextView: View {
  let boxed: BoxedText
  let weight: Font.Weight
  let style: HierarchicalShapeStyle

  var body: some View {
    Text(verbatim: boxed.text)
      .font(.system(size: boxed.fontSize, weight: weight))
      .foregroundStyle(style)
      .fixedSize(horizontal: false, vertical: true)
      .frame(width: boxed.rect.width, alignment: .topLeading)
      .offset(x: boxed.rect.minX, y: boxed.rect.minY)
  }
}
