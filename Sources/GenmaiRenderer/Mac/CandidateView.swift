// The candidate window view. Based on mozc/src/renderer/mac/CandidateView.{h,mm} (3.35.6354), but with its own
// look instead of Mozc's: a rounded, translucent panel (the system popover material), an accent-colored
// selection, subdued shortcut numbers and descriptions, and an "AI" badge for candidates of the AI conversion.
//
// The geometry still comes from TableLayout (as in -updateLayout), so CandidateController can place the window
// (candidate column under the preedit, cascading window next to the focused row) the same way. Only the metrics
// differ: they come from `CandidateDesign` instead of renderer_style.textproto, and colors are the system's
// semantic colors (light / dark follow the appearance automatically).

import AppKit
import GenmaiClient
import GenmaiProtocol
import Observation
import SwiftUI

public typealias CandidateWindowMessage = Genmai_Commands_CandidateWindow

/// The column structure of the macOS candidate table view.
public enum ColumnType: Int, CaseIterable, Sendable {
  case shortcut = 0  // Show candidate shortcut key.
  case gap1  // Padding region between shortcut and candidate string.
  case candidate  // Show candidate string value.
  case description  // Show description annotation message.
}

/// Number of columns.
public let kNumberOfColumns = ColumnType.allCases.count

/// Metrics and fonts of the candidate window.
public enum CandidateDesign {
  /// Space between the window edge and the rows.
  public static let windowPadding = 5
  /// Padding inside a row (all sides).
  public static let rowPadding = 4
  public static let minimumRowContentHeight = 18
  public static let shortcutLeading: CGFloat = 4
  public static let gap = 8
  public static let candidateTrailing: CGFloat = 14
  public static let descriptionTrailing: CGFloat = 4
  /// Minimum width of the candidate + description columns.
  public static let minimumContentWidth = 96
  public static let scrollBarWidth = 9
  public static let footerHeight = 22
  public static let footerSpacing: CGFloat = 8
  public static let cornerRadius: CGFloat = 10
  public static let rowCornerRadius: CGFloat = 6

  public static let candidateFontSize: CGFloat = 15
  public static let shortcutFontSize: CGFloat = 11
  public static let descriptionFontSize: CGFloat = 11
  public static let footerFontSize: CGFloat = 11

  /// The description marking candidates of the AI conversion (AIConversionAligner.description).
  public static let aiMarker = "AI"
  public static let aiBadgeFontSize: CGFloat = 10
  public static let aiBadgeIconWidth: CGFloat = 10
  public static let aiBadgeHorizontalPadding: CGFloat = 5
  public static let aiBadgeSpacing: CGFloat = 2
  /// Space between the badge and the rest of the description.
  public static let aiBadgeTrailing: CGFloat = 5

  static func textStyle(size: CGFloat) -> RendererStyle.TextStyle {
    var style = RendererStyle.TextStyle()
    style.fontSize = size
    return style
  }
}

/// A candidate's description split into the AI badge and the remaining text.
public struct CandidateDescription: Equatable, Sendable {
  public var isAI: Bool
  public var text: String

  public init(_ description: String) {
    var words = description.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    if let i = words.firstIndex(of: CandidateDesign.aiMarker) {
      words.remove(at: i)
      isAI = true
    } else {
      isAI = false
    }
    text = isAI ? words.joined(separator: " ") : description
  }
}

/// Everything CandidateView draws for one row (rects in window coordinates, top-left origin).
public struct CandidateRowData: Equatable, Sendable, Identifiable {
  public var id: Int { row }
  public var row: Int
  public var rowRect: Rect
  public var shortcut: String
  /// The candidate value with the annotation prefix / suffix.
  public var value: String
  public var description: CandidateDescription
  public var shortcutRect: CGRect
  public var candidateRect: CGRect
  public var descriptionRect: CGRect
  /// The row has an information (infolist) entry.
  public var hasInformation: Bool
}

public struct CandidateFooterData: Equatable, Sendable {
  public var rect: CGRect
  /// Label and sub label (e.g. "Tabキーで選択").
  public var label: String
  /// "focused/total", empty when the index is hidden.
  public var index: String
}

public struct CandidateScrollBarData: Equatable, Sendable {
  public var barRect: Rect
  public var indicatorRect: Rect
}

/// The result of -updateLayout: all geometry needed to draw the candidate window.
public struct CandidateRenderData: Equatable, Sendable {
  public var totalSize: Size = Size()
  public var rows: [CandidateRowData] = []
  public var scrollBar: CandidateScrollBarData?
  public var footer: CandidateFooterData?
  /// False when the category is not a valid `Category` value (drawRect: draws nothing then).
  public var isValidCategory = true

  public init() {}
}

@MainActor
@Observable
public final class CandidateViewModel {
  public private(set) var candidateWindow = CandidateWindowMessage()
  /// The row which has focused background.
  public private(set) var focusedRow = -1
  public private(set) var renderData = CandidateRenderData()

  @ObservationIgnored public let tableLayout = TableLayout()
  @ObservationIgnored private let measurer: any TextMeasuring
  /// holds a callback for mouse clicks.
  @ObservationIgnored public weak var commandSender: (any SendCommandInterface)?

  public init(measurer: any TextMeasuring = AppKitTextMeasurer()) {
    self.measurer = measurer
  }

  public func setCandidateWindow(_ candidateWindow: CandidateWindowMessage) {
    self.candidateWindow = candidateWindow
  }

  private func width(_ text: String, size: CGFloat) -> CGFloat {
    text.isEmpty ? 0 : measurer.size(of: text, style: CandidateDesign.textStyle(size: size)).width.rounded(.up)
  }

  private func height(_ text: String, size: CGFloat) -> CGFloat {
    measurer.size(of: text, style: CandidateDesign.textStyle(size: size)).height.rounded(.up)
  }

  /// Width of the AI badge (sparkles icon + "AI").
  var aiBadgeWidth: CGFloat {
    CandidateDesign.aiBadgeHorizontalPadding * 2 + CandidateDesign.aiBadgeIconWidth
      + CandidateDesign.aiBadgeSpacing + width(CandidateDesign.aiMarker, size: CandidateDesign.aiBadgeFontSize)
  }

  private func descriptionWidth(_ description: CandidateDescription) -> CGFloat {
    var result = width(description.text, size: CandidateDesign.descriptionFontSize)
    if description.isAI {
      result += aiBadgeWidth + (description.text.isEmpty ? 0 : CandidateDesign.aiBadgeTrailing)
    }
    return result
  }

  private func displayValue(_ candidate: CandidateWindowMessage.Candidate) -> String {
    var value = candidate.value
    if candidate.annotation.hasPrefix {
      value = candidate.annotation.prefix + value  // Prepend the prefix() to value.
    }
    if candidate.annotation.hasSuffix {
      value.append(candidate.annotation.suffix)
    }
    return value
  }

  private func footerLabel(_ footer: Genmai_Commands_Footer) -> String {
    [footer.hasLabel ? footer.label : "", footer.hasSubLabel ? footer.subLabel : ""]
      .filter { !$0.isEmpty }.joined(separator: " ")
  }

  // MARK: - Layout (-updateLayout)

  @discardableResult
  public func updateLayout() -> Size {
    let window = candidateWindow
    tableLayout.initialize(numRows: window.candidate.count, numColumns: kNumberOfColumns)
    tableLayout.setWindowBorder(CandidateDesign.windowPadding)

    // calculating focusedRow_
    if window.hasFocusedIndex && !window.candidate.isEmpty {
      focusedRow = Int(window.focusedIndex) - Int(window.candidate[0].index)
    } else {
      focusedRow = -1
    }

    // Reserve footer space.
    if window.hasFooter {
      let label = footerLabel(window.footer)
      let index = window.footer.indexVisible ? footerIndexString(window) : ""
      var footerWidth = CGFloat(CandidateDesign.rowPadding * 2)
      footerWidth += width(label, size: CandidateDesign.footerFontSize)
      footerWidth += width(index, size: CandidateDesign.footerFontSize)
      if !label.isEmpty && !index.isEmpty {
        footerWidth += CandidateDesign.footerSpacing
      }
      tableLayout.ensureFooterSize(Size(Int(footerWidth.rounded(.up)), CandidateDesign.footerHeight))
    }

    tableLayout.setRowRectPadding(CandidateDesign.rowPadding)
    if window.candidate.count < Int(window.size) {
      tableLayout.setVScrollBar(CandidateDesign.scrollBarWidth)
    }
    tableLayout.ensureCellSize(ColumnType.gap1.rawValue, Size(CandidateDesign.gap, 0))

    for candidate in window.candidate {
      let shortcut = candidate.annotation.shortcut
      if !shortcut.isEmpty {
        let w = CandidateDesign.shortcutLeading + width(shortcut, size: CandidateDesign.shortcutFontSize)
        tableLayout.ensureCellSize(ColumnType.shortcut.rawValue, Size(Int(w), 0))
      }
      let value = displayValue(candidate)
      let valueHeight = max(
        CGFloat(CandidateDesign.minimumRowContentHeight), height(value, size: CandidateDesign.candidateFontSize))
      let valueWidth =
        value.isEmpty ? 0 : width(value, size: CandidateDesign.candidateFontSize) + CandidateDesign.candidateTrailing
      tableLayout.ensureCellSize(ColumnType.candidate.rawValue, Size(Int(valueWidth), Int(valueHeight)))
      let description = CandidateDescription(candidate.annotation.description_p)
      let w = descriptionWidth(description)
      if w > 0 {
        tableLayout.ensureCellSize(
          ColumnType.description.rawValue, Size(Int(w + CandidateDesign.descriptionTrailing), 0))
      }
    }

    tableLayout.ensureColumnsWidth(
      ColumnType.candidate.rawValue, ColumnType.description.rawValue, CandidateDesign.minimumContentWidth)

    tableLayout.freezeLayout()
    renderData = makeRenderData()
    return tableLayout.getTotalSize()
  }

  private func footerIndexString(_ window: CandidateWindowMessage) -> String {
    // +1 to 1-origin from 0-origin.
    "\(Int(window.focusedIndex) + 1)/\(window.size)"
  }

  // MARK: - Drawing data

  private func makeRenderData() -> CandidateRenderData {
    var data = CandidateRenderData()
    data.totalSize = tableLayout.getTotalSize()
    data.isValidCategory = Genmai_Commands_Category(rawValue: candidateWindow.category.rawValue) != nil

    for (row, candidate) in candidateWindow.candidate.enumerated() {
      func cell(_ column: ColumnType) -> CGRect { MacViewUtil.toNSRect(tableLayout.getCellRect(row, column.rawValue)) }
      var shortcutRect = cell(.shortcut)
      shortcutRect.origin.x += CandidateDesign.shortcutLeading
      shortcutRect.size.width = max(shortcutRect.width - CandidateDesign.shortcutLeading, 0)
      data.rows.append(
        CandidateRowData(
          row: row, rowRect: tableLayout.getRowRect(row), shortcut: candidate.annotation.shortcut,
          value: displayValue(candidate), description: CandidateDescription(candidate.annotation.description_p),
          shortcutRect: shortcutRect, candidateRect: cell(.candidate), descriptionRect: cell(.description),
          hasInformation: candidate.hasInformationID))
    }

    if candidateWindow.candidate.count < Int(candidateWindow.size) {
      let vscrollRect = tableLayout.getVScrollBarRect()
      if !vscrollRect.isRectEmpty && !candidateWindow.candidate.isEmpty {
        let beginIndex = Int(candidateWindow.candidate[0].index)
        let candidatesTotal = Int(candidateWindow.size)
        let endIndex = Int(candidateWindow.candidate[candidateWindow.candidate.count - 1].index)
        data.scrollBar = CandidateScrollBarData(
          barRect: vscrollRect,
          indicatorRect: tableLayout.getVScrollIndicatorRect(beginIndex, endIndex, candidatesTotal))
      }
    }

    if candidateWindow.hasFooter {
      let footer = candidateWindow.footer
      data.footer = CandidateFooterData(
        rect: MacViewUtil.toNSRect(tableLayout.getFooterRect()), label: footerLabel(footer),
        index: footer.indexVisible ? footerIndexString(candidateWindow) : "")
    }
    return data
  }

  // MARK: - Event handling callbacks

  private func row(at localPos: Point) -> Int? {
    for i in 0..<tableLayout.numberOfRows where tableLayout.getRowRect(i).ptrInRect(localPos) {
      return i
    }
    return nil
  }

  /// -mouseDown: / -mouseDragged:
  public func mouseDown(at location: CGPoint) {
    let localPos = MacViewUtil.toPoint(location)
    if let clickedRow = row(at: localPos), clickedRow != focusedRow {
      focusedRow = clickedRow
    }
  }

  /// -mouseUp:
  public func mouseUp(at location: CGPoint) {
    let localPos = MacViewUtil.toPoint(location)
    guard let commandSender else { return }
    if candidateWindow.candidate.count < tableLayout.numberOfRows {
      return
    }
    if let clicked = row(at: localPos) {
      var command = SessionCommand()
      command.type = .selectCandidate
      command.id = candidateWindow.candidate[clicked].id
      commandSender.sendCommand(command)
    }
  }
}

// MARK: - SwiftUI views

/// Renders a `CandidateViewModel`.
public struct CandidateView: View {
  let model: CandidateViewModel

  public init(model: CandidateViewModel) {
    self.model = model
  }

  public var body: some View {
    let data = model.renderData
    ZStack(alignment: .topLeading) {
      if data.isValidCategory {
        ForEach(data.rows) { row in
          CandidateRowView(row: row, isFocused: row.row == model.focusedRow)
        }
        if let scrollBar = data.scrollBar {
          CandidateScrollBarView(scrollBar: scrollBar)
        }
        if let footer = data.footer {
          CandidateFooterView(footer: footer)
        }
      }
    }
    .frame(
      width: CGFloat(data.totalSize.width), height: CGFloat(data.totalSize.height),
      alignment: .topLeading
    )
    .modifier(CandidatePanelBackground())
    .contentShape(.rect)
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .onChanged { model.mouseDown(at: $0.location) }
        .onEnded { model.mouseUp(at: $0.location) }
    )
    .accessibilityElement(children: .contain)
  }
}

/// The rounded, translucent panel behind the candidate and infolist windows.
struct CandidatePanelBackground: ViewModifier {
  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: CandidateDesign.cornerRadius, style: .continuous)
    content
      .background { VisualEffectBackground() }
      .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
      .clipShape(shape)
  }
}

/// NSVisualEffectView that always looks active: the candidate panel never becomes key, and the inactive state of
/// the material is a flat gray.
struct VisualEffectBackground: NSViewRepresentable {
  func makeNSView(context: NSViewRepresentableContext<Self>) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .popover
    view.blendingMode = .behindWindow
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: NSViewRepresentableContext<Self>) {}
}

struct CandidateRowView: View {
  let row: CandidateRowData
  let isFocused: Bool

  var body: some View {
    ZStack(alignment: .topLeading) {
      if isFocused {
        PlacedRect(rect: MacViewUtil.toNSRect(row.rowRect)) {
          RoundedRectangle(cornerRadius: CandidateDesign.rowCornerRadius, style: .continuous)
            .fill(Color.accentColor)
        }
      }
      if !row.shortcut.isEmpty {
        CellText(
          text: row.shortcut, rect: row.shortcutRect,
          font: .system(size: CandidateDesign.shortcutFontSize, weight: .medium).monospacedDigit(),
          color: isFocused ? .white.opacity(0.8) : .secondary)
      }
      CellText(
        text: row.value, rect: row.candidateRect, font: .system(size: CandidateDesign.candidateFontSize),
        color: isFocused ? .white : .primary)
      if row.description.isAI || !row.description.text.isEmpty {
        PlacedRect(rect: row.descriptionRect) {
          CandidateDescriptionView(description: row.description, isFocused: isFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
      }
      if row.hasInformation {
        let rect = MacViewUtil.toNSRect(row.rowRect)
        PlacedRect(rect: CGRect(x: rect.maxX - 7, y: rect.midY - 2, width: 4, height: 4)) {
          Circle().fill(isFocused ? Color.white.opacity(0.8) : Color.accentColor)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      [row.shortcut, row.value, row.description.isAI ? CandidateDesign.aiMarker : "", row.description.text]
        .filter { !$0.isEmpty }.joined(separator: " ")
    )
    .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
  }
}

struct CandidateDescriptionView: View {
  let description: CandidateDescription
  let isFocused: Bool

  var body: some View {
    HStack(spacing: CandidateDesign.aiBadgeTrailing) {
      if description.isAI {
        AIBadge(isFocused: isFocused)
      }
      if !description.text.isEmpty {
        Text(verbatim: description.text)
          .font(.system(size: CandidateDesign.descriptionFontSize))
          .foregroundStyle(isFocused ? Color.white.opacity(0.85) : Color.secondary)
          .lineLimit(1)
          .fixedSize()
      }
    }
  }
}

/// The "AI" mark of candidates from the AI conversion.
struct AIBadge: View {
  let isFocused: Bool

  private static let gradient = LinearGradient(
    colors: [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.23, green: 0.51, blue: 0.96)],
    startPoint: .leading, endPoint: .trailing)

  var body: some View {
    HStack(spacing: CandidateDesign.aiBadgeSpacing) {
      Image(systemName: "sparkles")
        .font(.system(size: CandidateDesign.aiBadgeFontSize - 1, weight: .semibold))
        .frame(width: CandidateDesign.aiBadgeIconWidth)
      Text(verbatim: CandidateDesign.aiMarker)
        .font(.system(size: CandidateDesign.aiBadgeFontSize, weight: .bold))
    }
    .foregroundStyle(.white)
    .padding(.horizontal, CandidateDesign.aiBadgeHorizontalPadding)
    .padding(.vertical, 2)
    .background {
      if isFocused {
        Capsule().fill(.white.opacity(0.25))
      } else {
        Capsule().fill(Self.gradient)
      }
    }
    .fixedSize()
    .accessibilityHidden(true)
  }
}

struct CandidateScrollBarView: View {
  let scrollBar: CandidateScrollBarData

  var body: some View {
    let indicator = MacViewUtil.toNSRect(scrollBar.indicatorRect)
    // A thin capsule centered in the scroll bar column, inset from the top and bottom.
    PlacedRect(rect: indicator.insetBy(dx: 3, dy: 2)) {
      Capsule().fill(.tertiary)
    }
    .accessibilityHidden(true)
  }
}

struct CandidateFooterView: View {
  let footer: CandidateFooterData

  var body: some View {
    PlacedRect(rect: footer.rect) {
      VStack(spacing: 0) {
        Divider()
        HStack(spacing: CandidateDesign.footerSpacing) {
          if !footer.label.isEmpty {
            Text(verbatim: footer.label).lineLimit(1)
          }
          Spacer(minLength: 0)
          if !footer.index.isEmpty {
            Text(verbatim: footer.index).monospacedDigit().lineLimit(1)
          }
        }
        .font(.system(size: CandidateDesign.footerFontSize))
        .foregroundStyle(.secondary)
        .padding(.horizontal, CGFloat(CandidateDesign.rowPadding))
        .frame(maxHeight: .infinity)
      }
    }
  }
}

/// One line of text vertically centered in `rect`.
struct CellText: View {
  let text: String
  let rect: CGRect
  let font: Font
  let color: Color

  var body: some View {
    PlacedRect(rect: rect) {
      Text(verbatim: text)
        .font(font)
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
  }
}

/// Places `content` at `rect` (top-left origin) inside a top-leading ZStack.
struct PlacedRect<Content: View>: View {
  let rect: CGRect
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(width: max(rect.width, 0), height: max(rect.height, 0))
      .offset(x: rect.minX, y: rect.minY)
  }
}
