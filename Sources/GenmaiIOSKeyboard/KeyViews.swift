// The keys of the iOS keyboard (not in Mozc).

#if os(iOS)
  import GenmaiIOS
  import SwiftUI
  import UIKit

  /// The rounded key shape of the system keyboard: from iOS 26 rounder and flat, before with a bottom shadow.
  private struct KeyBackground: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
      content
        .background(color, in: .rect(cornerRadius: KeyboardMetrics.cornerRadius))
        .shadow(color: KeyboardMetrics.hasKeyShadow ? KeyboardColors.keyShadow : .clear, radius: 0, x: 0, y: 1)
    }
  }

  extension View {
    fileprivate func keyBackground(_ color: Color) -> some View {
      modifier(KeyBackground(color: color))
    }
  }

  /// A 12-key key: tap (toggle) or flick in four directions, with the system keyboard's feedback (from screen
  /// recordings of iOS 27): a pressed key darkens; after a tap that can toggle it stays dark until the toggle ends
  /// (with flick only nothing toggles, so it is dark only while touched); a flick shows its character in a popup on that side, pointing at the key; held for 0.4 s the key shows
  /// its guide (its characters as a cross, the one the finger points at lighter) and the other keys' labels dim.
  /// The popups are drawn over the whole keyboard (`FlickPopupOverlay`, fed through `FlickPopupPreference`).
  struct FlickKey: View {
    let key: CharacterKey
    let height: CGFloat
    var isLastColumn = false
    @Environment(\.keyActions) private var actions
    @State private var isPressed = false
    @State private var direction: FlickDirection?
    @State private var showsGuide = false
    @State private var guideTask: Task<Void, Never>?

    private static let threshold: CGFloat = 20
    private static let guideDelay: Duration = .milliseconds(400)

    var body: some View {
      let highlighted = isPressed || actions.togglingKey == key.tap
      label
        .foregroundStyle(actions.dimsLabels ? .secondary : .primary)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .keyBackground(highlighted ? KeyboardColors.pressedKey : KeyboardColors.characterKey)
        .contentShape(.rect)
        .anchorPreference(key: FlickPopupPreference.self, value: .bounds) { bounds in
          guard isPressed, direction != nil || showsGuide else { return [] }
          return [FlickPopup(bounds: bounds, key: key, direction: direction, showsGuide: showsGuide)]
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              if !isPressed {
                isPressed = true
                actions.feedback()
                guideTask = Task {
                  try? await Task.sleep(for: Self.guideDelay)
                  guard !Task.isCancelled else { return }
                  showsGuide = true
                  actions.setShowsFlickGuide(true)
                }
              }
              let direction = Self.direction(of: value.translation)
              if direction != nil, !showsGuide {
                // a flick, not a hold: no guide
                guideTask?.cancel()
              }
              self.direction = direction
            }
            .onEnded { value in
              let direction = Self.direction(of: value.translation)
              guideTask?.cancel()
              guideTask = nil
              isPressed = false
              showsGuide = false
              actions.setShowsFlickGuide(false)
              self.direction = nil
              if let text = key.text(for: direction) {
                actions.input(text)
              }
            }
        )
        .accessibilityElement()
        .accessibilityLabel(key.label)
        .accessibilityAddTraits(.isKeyboardKey)
        .accessibilityAction { actions.input(key.tap) }
    }

    /// The label, drawn like the system keyboard's for 小゛゜, わ and 、。?!.
    @ViewBuilder private var label: some View {
      switch key.label {
      case "小゛゜":
        ZStack {
          Text(verbatim: "小").font(.system(size: 11.5)).offset(y: 3.5)
          Text(verbatim: "゛").font(.system(size: 13)).offset(x: -8, y: -5.5)
          Text(verbatim: "゜").font(.system(size: 13)).offset(x: 8, y: -5.5)
        }
        .offset(x: 6.5, y: 3)
      case "わ":
        ZStack {
          Text(verbatim: "わ").font(.system(size: KeyboardMetrics.labelSize))
          Text(verbatim: "_").font(.system(size: 16)).offset(x: 7.7, y: 6.3)
        }
        .offset(KeyboardMetrics.labelOffset(isLastColumn: isLastColumn))
      case "、。?!":
        // the system sets 、。 narrow: their half-width forms
        Text(verbatim: "､｡?!").font(.system(size: 23)).offset(y: -2)
      default:
        Text(key.label)
          .font(.system(size: key.label.count > 2 ? 16 : KeyboardMetrics.labelSize))
          .offset(key.label.count > 2 ? .zero : KeyboardMetrics.labelOffset(isLastColumn: isLastColumn))
      }
    }

    static func direction(of translation: CGSize) -> FlickDirection? {
      let dx = translation.width
      let dy = translation.height
      guard max(abs(dx), abs(dy)) >= threshold else { return nil }
      if abs(dx) > abs(dy) {
        return dx < 0 ? .left : .right
      }
      return dy < 0 ? .up : .down
    }
  }

  /// A QWERTY key: tap only.
  struct QwertyKey: View {
    let key: CharacterKey
    let height: CGFloat
    @Environment(\.keyActions) private var actions
    @State private var isPressed = false

    var body: some View {
      Text(key.label)
        .font(.system(size: 22))
        .foregroundStyle(actions.dimsLabels ? .secondary : .primary)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .keyBackground(isPressed ? KeyboardColors.pressedKey : KeyboardColors.characterKey)
        .contentShape(.rect)
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { _ in
              if !isPressed {
                isPressed = true
                actions.feedback()
              }
            }
            .onEnded { _ in
              isPressed = false
              actions.input(key.tap)
            }
        )
        .accessibilityElement()
        .accessibilityLabel(key.label)
        .accessibilityAddTraits(.isKeyboardKey)
        .accessibilityAction { actions.input(key.tap) }
    }
  }

  /// A key with a title or a symbol. `repeats`: held down, the action repeats (backspace).
  struct FunctionKey: View {
    var title: String?
    var systemImage: String?
    let height: CGFloat
    var repeats = false
    /// A disabled key shows a gray label and does nothing (the system's → and ↺ without a composition).
    var isEnabled = true
    /// The label's size and tracking when they differ from the function keys' (measured per key).
    var labelSize: CGFloat?
    var labelTracking: CGFloat?
    var labelOffset: CGSize?
    let action: @MainActor (KeyActions) -> Void
    @Environment(\.keyActions) private var actions
    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    init(
      title: String? = nil, systemImage: String? = nil, height: CGFloat, repeats: Bool = false,
      isEnabled: Bool = true, labelSize: CGFloat? = nil, labelTracking: CGFloat? = nil, labelOffset: CGSize? = nil,
      action: @escaping @MainActor (KeyActions) -> Void
    ) {
      self.labelOffset = labelOffset
      self.labelSize = labelSize
      self.labelTracking = labelTracking
      self.title = title
      self.systemImage = systemImage
      self.height = height
      self.repeats = repeats
      self.isEnabled = isEnabled
      self.action = action
    }

    var body: some View {
      label
        .foregroundStyle(!isEnabled ? .tertiary : actions.dimsLabels ? .secondary : .primary)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .keyBackground(isPressed ? KeyboardColors.pressedFunctionKey : KeyboardColors.functionKey)
        .contentShape(.rect)
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { _ in
              guard !isPressed, isEnabled else { return }
              isPressed = true
              actions.feedback()
              guard repeats else { return }
              action(actions)
              repeatTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                while !Task.isCancelled {
                  action(actions)
                  try? await Task.sleep(for: .milliseconds(80))
                }
              }
            }
            .onEnded { _ in
              guard isEnabled else { return }
              isPressed = false
              repeatTask?.cancel()
              repeatTask = nil
              if !repeats {
                action(actions)
              }
            }
        )
        .accessibilityElement()
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(.isKeyboardKey)
        .accessibilityAction { action(actions) }
    }

    @ViewBuilder private var label: some View {
      if let systemImage {
        Image(systemName: systemImage).font(.system(size: labelSize ?? 21.5))
      } else {
        Text(title ?? "").font(.system(size: labelSize ?? KeyboardMetrics.functionLabelSize))
          .tracking(labelTracking ?? KeyboardMetrics.functionLabelTracking(title ?? "")).lineLimit(1)
          .minimumScaleFactor(0.6)
          .offset(labelOffset ?? CGSize(width: KeyboardMetrics.functionLabelTracking(title ?? ""), height: 0))
      }
    }

    private var accessibilityTitle: String {
      switch systemImage {
      case "delete.left": "削除"
      case "arrow.counterclockwise": "取り消し"
      case "arrow.right": "次の文字へ"
      case "shift", "shift.fill": "シフト"
      case "keyboard.chevron.compact.down": "キーボードを閉じる"
      default: title ?? ""
      }
    }
  }

  /// The space key: tap for space / conversion; drag sideways to move the cursor.
  struct SpaceKey: View {
    let title: String
    let height: CGFloat
    @Environment(\.keyActions) private var actions
    @State private var isPressed = false
    @State private var movedSteps = 0
    @State private var isMovingCursor = false

    private static let step: CGFloat = 12

    var body: some View {
      Text(title)
        .tracking(KeyboardMetrics.functionLabelTracking(title))
        .offset(x: KeyboardMetrics.functionLabelTracking(title))
        .font(.system(size: KeyboardMetrics.functionLabelSize))
        .foregroundStyle(actions.dimsLabels ? .secondary : .primary)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .keyBackground(isPressed ? KeyboardColors.pressedKey : KeyboardColors.characterKey)
        .contentShape(.rect)
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              if !isPressed {
                isPressed = true
                actions.feedback()
              }
              if abs(value.translation.width) > Self.step {
                isMovingCursor = true
              }
              guard isMovingCursor else { return }
              let steps = Int(value.translation.width / Self.step)
              while movedSteps < steps {
                actions.perform(.cursorRight)
                movedSteps += 1
              }
              while movedSteps > steps {
                actions.perform(.cursorLeft)
                movedSteps -= 1
              }
            }
            .onEnded { _ in
              if !isMovingCursor {
                actions.perform(.space)
              }
              isPressed = false
              isMovingCursor = false
              movedSteps = 0
            }
        )
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isKeyboardKey)
        .accessibilityAction { actions.perform(.space) }
    }
  }

  struct EnterKey: View {
    let title: String
    var systemImage: String?
    let prominent: Bool
    let height: CGFloat
    @Environment(\.keyActions) private var actions
    @State private var isPressed = false

    var body: some View {
      label
        .foregroundStyle(prominent ? .white : actions.dimsLabels ? .secondary : .primary)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .keyBackground(
          isPressed ? KeyboardColors.pressedFunctionKey : prominent ? Color.accentColor : KeyboardColors.functionKey
        )
        .contentShape(.rect)
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { _ in
              if !isPressed {
                isPressed = true
                actions.feedback()
              }
            }
            .onEnded { _ in
              isPressed = false
              actions.perform(.enter)
            }
        )
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isKeyboardKey)
        .accessibilityAction { actions.perform(.enter) }
    }

    @ViewBuilder private var label: some View {
      if let systemImage {
        Image(systemName: systemImage).font(.system(size: 21.5))
      } else {
        Text(title).font(.system(size: KeyboardMetrics.functionLabelSize))
          .tracking(KeyboardMetrics.functionLabelTracking(title))
          .offset(x: KeyboardMetrics.functionLabelTracking(title))
      }
    }
  }

  /// The globe key when the system asks for one (it switches keyboards and shows the list on a long press),
  /// otherwise a key that dismisses the keyboard.
  struct GlobeOrDismissKey: View {
    let context: KeyContext

    var body: some View {
      if context.state.needsInputModeSwitchKey {
        NextKeyboardButton(inputViewController: context.inputViewController)
          .frame(maxWidth: .infinity)
          .frame(height: context.rowHeight)
          .keyBackground(KeyboardColors.functionKey)
          .accessibilityLabel("次のキーボード")
      } else {
        FunctionKey(systemImage: "keyboard.chevron.compact.down", height: context.rowHeight) { _ in
          context.inputViewController.dismissKeyboard()
        }
      }
    }
  }

  /// handleInputModeList(from:with:) needs the touch events of a UIView.
  struct NextKeyboardButton: UIViewRepresentable {
    let inputViewController: UIInputViewController

    func makeUIView(context: Context) -> UIButton {
      let button = UIButton(type: .system)
      button.setImage(UIImage(systemName: "globe"), for: .normal)
      button.tintColor = .label
      button.addTarget(
        inputViewController, action: #selector(UIInputViewController.handleInputModeList(from:with:)),
        for: .allTouchEvents)
      return button
    }

    func updateUIView(_ button: UIButton, context: Context) {}
  }

  /// A pressed 12-key key that shows a popup: a flick or the guide.
  struct FlickPopup {
    let bounds: Anchor<CGRect>
    let key: CharacterKey
    let direction: FlickDirection?
    let showsGuide: Bool
  }

  struct FlickPopupPreference: PreferenceKey {
    static let defaultValue: [FlickPopup] = []

    static func reduce(value: inout [FlickPopup], nextValue: () -> [FlickPopup]) {
      value += nextValue()
    }
  }

  /// Draws the popups of `FlickPopupPreference` over the keyboard (it does not take touches). Geometry measured
  /// from screen recordings of the system keyboard (iPhone 16 Pro, iOS 27): every cell is a key grown to the middle
  /// of the gaps around it; a flick popup is the neighbour's cell whose side facing the key comes to a point 29.5 %
  /// of the way from the key's center to the neighbour's, its sides sloping 1 : 2 (corners 7 pt, shoulders 8.6 pt,
  /// tip 1 pt); the guide is the key's cell with the cells of its flick directions, the one the finger points at
  /// (or the center) highlighted.
  struct FlickPopupOverlay: View {
    let popups: [FlickPopup]

    private static let tipPosition: CGFloat = 0.295
    private static let slope: CGFloat = 0.5
    private static let shoulderRadius: CGFloat = 8.6
    private static let tipRadius: CGFloat = 1

    var body: some View {
      GeometryReader { proxy in
        ForEach(popups.indices, id: \.self) { index in
          let popup = popups[index]
          let rect = proxy[popup.bounds]
          if popup.showsGuide {
            guide(popup, around: rect)
          } else if let direction = popup.direction, let flick = popup.key.flicks[direction] {
            flickPopup(flick.label, from: rect, toward: direction, in: proxy.size)
          }
        }
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }

    @ViewBuilder
    private func flickPopup(_ label: String, from key: CGRect, toward direction: FlickDirection, in size: CGSize)
      -> some View
    {
      let cell = Self.cell(Self.neighbour(of: key, toward: direction))
      Self.popupOutline(from: key, toward: direction)
        .fill(
          RadialGradient(
            colors: [KeyboardColors.popupCenter, KeyboardColors.popupEdge],
            center: UnitPoint(x: cell.midX / max(size.width, 1), y: cell.midY / max(size.height, 1)),
            startRadius: 0, endRadius: hypot(cell.width, cell.height) / 2)
        )
      Text(label)
        .font(.system(size: KeyboardMetrics.popupLabelSize))
        .position(x: cell.midX, y: cell.midY + KeyboardMetrics.popupLabelOffset)
    }

    /// The key's characters as a cross: the center and the cells of the directions that have a character.
    @ViewBuilder
    private func guide(_ popup: FlickPopup, around key: CGRect) -> some View {
      let center = Self.cell(key)
      let arms = FlickDirection.allCases.filter { popup.key.flicks[$0] != nil }
      let radius = KeyboardMetrics.popupCornerRadius
      ForEach(arms, id: \.self) { direction in
        guideCell(
          popup.key.flicks[direction]?.label ?? "", in: Self.cell(Self.neighbour(of: key, toward: direction)),
          shape: Self.armShape(toward: direction, radius: radius), selected: popup.direction == direction)
      }
      guideCell(
        popup.key.label, in: center,
        shape: UnevenRoundedRectangle(
          topLeadingRadius: arms.contains(.up) || arms.contains(.left) ? 0 : radius,
          bottomLeadingRadius: arms.contains(.down) || arms.contains(.left) ? 0 : radius,
          bottomTrailingRadius: arms.contains(.down) || arms.contains(.right) ? 0 : radius,
          topTrailingRadius: arms.contains(.up) || arms.contains(.right) ? 0 : radius),
        selected: popup.direction == nil)
    }

    private func guideCell(_ label: String, in rect: CGRect, shape: UnevenRoundedRectangle, selected: Bool)
      -> some View
    {
      Text(label)
        .font(.system(size: KeyboardMetrics.popupLabelSize))
        .offset(y: KeyboardMetrics.popupLabelOffset)
        .frame(width: rect.width, height: rect.height)
        .background(selected ? KeyboardColors.guideSelected : KeyboardColors.guideCell, in: shape)
        .position(x: rect.midX, y: rect.midY)
    }

    /// The neighbour key of `key` in `direction`.
    static func neighbour(of key: CGRect, toward direction: FlickDirection) -> CGRect {
      let dx = key.width + KeyboardMetrics.columnSpacing
      let dy = key.height + KeyboardMetrics.rowSpacing
      return switch direction {
      case .left: key.offsetBy(dx: -dx, dy: 0)
      case .right: key.offsetBy(dx: dx, dy: 0)
      case .up: key.offsetBy(dx: 0, dy: -dy)
      case .down: key.offsetBy(dx: 0, dy: dy)
      }
    }

    /// A key grown to the middle of the gaps around it.
    static func cell(_ key: CGRect) -> CGRect {
      key.insetBy(dx: -KeyboardMetrics.columnSpacing / 2, dy: -KeyboardMetrics.rowSpacing / 2)
    }

    /// A flick popup's outline: the neighbour's cell, pointed towards the key.
    static func popupOutline(from key: CGRect, toward direction: FlickDirection) -> Path {
      let neighbour = neighbour(of: key, toward: direction)
      let cell = cell(neighbour)
      let tip = CGPoint(
        x: key.midX + tipPosition * (neighbour.midX - key.midX),
        y: key.midY + tipPosition * (neighbour.midY - key.midY))
      // the shoulders (where the point meets the cell's sides) and the far corners
      let corners: [CGPoint] =
        switch direction {
        case .right:
          [
            CGPoint(x: tip.x + slope * cell.height / 2, y: cell.minY), CGPoint(x: cell.maxX, y: cell.minY),
            CGPoint(x: cell.maxX, y: cell.maxY), CGPoint(x: tip.x + slope * cell.height / 2, y: cell.maxY),
          ]
        case .left:
          [
            CGPoint(x: tip.x - slope * cell.height / 2, y: cell.maxY), CGPoint(x: cell.minX, y: cell.maxY),
            CGPoint(x: cell.minX, y: cell.minY), CGPoint(x: tip.x - slope * cell.height / 2, y: cell.minY),
          ]
        case .down:
          [
            CGPoint(x: cell.maxX, y: tip.y + slope * cell.width / 2), CGPoint(x: cell.maxX, y: cell.maxY),
            CGPoint(x: cell.minX, y: cell.maxY), CGPoint(x: cell.minX, y: tip.y + slope * cell.width / 2),
          ]
        case .up:
          [
            CGPoint(x: cell.minX, y: tip.y - slope * cell.width / 2), CGPoint(x: cell.minX, y: cell.minY),
            CGPoint(x: cell.maxX, y: cell.minY), CGPoint(x: cell.maxX, y: tip.y - slope * cell.width / 2),
          ]
        }
      let radius = KeyboardMetrics.popupCornerRadius
      return roundedPolygon(
        corners + [tip], radii: [shoulderRadius, radius, radius, shoulderRadius, tipRadius])
    }

    /// A closed polygon whose corners are rounded with the given radii.
    static func roundedPolygon(_ points: [CGPoint], radii: [CGFloat]) -> Path {
      var path = Path()
      guard let first = points.first, let last = points.last else { return path }
      path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
      for (index, point) in points.enumerated() {
        path.addArc(
          tangent1End: point, tangent2End: points[(index + 1) % points.count], radius: radii[index])
      }
      path.closeSubpath()
      return path
    }

    /// A guide arm is rounded on its far side only.
    static func armShape(toward direction: FlickDirection, radius: CGFloat) -> UnevenRoundedRectangle {
      switch direction {
      case .right: UnevenRoundedRectangle(bottomTrailingRadius: radius, topTrailingRadius: radius)
      case .left: UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius)
      case .down: UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
      case .up: UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius)
      }
    }
  }
#endif
