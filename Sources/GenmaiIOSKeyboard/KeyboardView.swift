// The keyboard (not in Mozc): the candidate bar over the 12-key or QWERTY keys of the current input mode.

#if os(iOS)
  import GenmaiIOS
  import SwiftUI
  import UIKit

  /// The system keyboard's geometry, measured on an iPhone 16 Pro (iOS 27, 402 pt wide): keys 47 pt high, 6⅓ pt
  /// apart in a row and 7 pt between rows, 7⅔ pt from the sides, the first row 55⅔ pt below the keyboard's top.
  /// Above a keyboard extension iOS 26 / 27 draws a 17⅔ pt margin of its own (nothing can be drawn there; a system
  /// bug, Apple Developer Forums thread 843093, said to depend on the keyboard switched from, but always there on an
  /// iPhone 16 Pro with iOS 27.0.1), and its bottom bar starts 3 pt above the system keyboard's last row. The
  /// candidates and keys keep the system keyboard's positions (the keys 3 pt higher), so the keyboard is 17⅔ pt
  /// higher than the system's: the margin cannot hold the candidates.
  enum KeyboardMetrics {
    static let candidateBarHeight: CGFloat = 49.7
    static let columnSpacing: CGFloat = 19.0 / 3
    static let rowSpacing: CGFloat = 7
    static let sidePadding: CGFloat = 23.0 / 3
    static let topPadding: CGFloat = 3
    static let bottomPadding: CGFloat = 0
    /// The margin the system draws above a keyboard extension (for the preview).
    static let systemTopMargin: CGFloat = 53.0 / 3

    /// The keys' corner radius and shadow: the system keyboard's keys are rounder and flat from iOS 26.
    static var cornerRadius: CGFloat {
      if #available(iOS 26, *) { 10 } else { 5 }
    }
    static var hasKeyShadow: Bool {
      if #available(iOS 26, *) { false } else { true }
    }
    /// The flick popup's and guide's corners.
    static let popupCornerRadius: CGFloat = 7
    /// Kana labels: 23.3 pt, their glyphs 1.1 pt above the key's middle and 1.2 pt right of it (not in the last
    /// column, as measured); in the popup and the guide 27.7 pt, 1.2 pt above.
    static let labelSize: CGFloat = 23.3
    static func labelOffset(isLastColumn: Bool) -> CGSize {
      CGSize(width: isLastColumn ? 0 : 1.2, height: -1.1)
    }
    static let popupLabelSize: CGFloat = 27.7
    /// The function keys' titles (空白, 次候補, 確定, ABC): 16.5 pt, spaced 1.3 pt (kana / kanji) or 0.7 pt.
    static let functionLabelSize: CGFloat = 16.5
    static func functionLabelTracking(_ title: String) -> CGFloat {
      title.unicodeScalars.contains { $0.value >= 0x3000 } ? 1.3 : 0.7
    }
    static let popupLabelOffset: CGFloat = -1.2

    /// The height of a row of keys (lower in landscape).
    static func rowHeight(_ verticalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
      verticalSizeClass == .compact ? 36 : 47
    }

    /// The height of the four rows of keys.
    static func keysHeight(_ verticalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
      4 * rowHeight(verticalSizeClass) + 3 * rowSpacing + topPadding + bottomPadding
    }

    /// The height of the whole keyboard.
    static func height(for traits: UITraitCollection) -> CGFloat {
      candidateBarHeight + keysHeight(traits.verticalSizeClass == .compact ? .compact : .regular)
    }
  }

  /// The system keyboard's colors (Resources/KeyboardColors.xcassets). From iOS 26 every key has one color and a
  /// pressed key fades towards the background; measured on an iPhone (iOS 27): dark keys 59 / pressed 40 on 29,
  /// light keys white / pressed 231 232 236; the flick guide's cells are white / 76 and the one the finger points at
  /// 224 223 226 / 87; the popup is white, in dark mode lighter in its middle (56 → 62); the focused candidate
  /// 248 247 250 (dark: not measured, the key color).
  /// Before iOS 26 the keys had a shadow, darker function keys and a lighter pressed color (`Legacy*`).
  enum KeyboardColors {
    private static var isGlass: Bool {
      if #available(iOS 26, *) { true } else { false }
    }

    private static func named(_ name: String) -> Color { Color(name, bundle: .module) }

    static let characterKey = named(isGlass ? "Key" : "LegacyKey")
    static let functionKey = named(isGlass ? "Key" : "LegacyFunctionKey")
    static let pressedKey = named(isGlass ? "KeyPressed" : "LegacyKeyPressed")
    /// A pressed function key (before iOS 26 it turned white).
    static let pressedFunctionKey = isGlass ? pressedKey : characterKey
    static let keyShadow = Color.black.opacity(0.3)
    static let popupCenter = named("PopupCenter")
    static let popupEdge = named("PopupEdge")
    static let guideCell = named("GuideCell")
    static let guideSelected = named("GuideSelected")
    static let candidateHighlight = named("CandidateHighlight")
    /// The keyboard's background (drawn by the system around a keyboard extension; for the preview).
    static let background = named("Background")
  }

  struct KeyboardView: View {
    let controller: KeyboardController
    let state: KeyboardHostState
    let inputViewController: UIInputViewController
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var rowHeight: CGFloat { KeyboardMetrics.rowHeight(verticalSizeClass) }

    var body: some View {
      VStack(spacing: 0) {
        CandidateBar(controller: controller, state: state)
          .frame(height: KeyboardMetrics.candidateBarHeight)
        if state.showsAllCandidates {
          CandidateGrid(controller: controller, state: state)
        } else {
          keys
            .padding(.horizontal, KeyboardMetrics.sidePadding)
            .padding(.top, KeyboardMetrics.topPadding)
            .padding(.bottom, KeyboardMetrics.bottomPadding)
        }
      }
      .overlayPreferenceValue(FlickPopupPreference.self) { FlickPopupOverlay(popups: $0) }
      .environment(\.keyActions, KeyActions(controller: controller, state: state))
    }

    @ViewBuilder private var keys: some View {
      let settings = controller.settings
      let context = KeyContext(
        controller: controller, state: state, inputViewController: inputViewController, rowHeight: rowHeight)
      if settings.kanaLayout == .qwerty || (controller.inputMode != .hiragana && settings.qwertyAlphabet) {
        QwertyKeyboard(context: context)
      } else {
        TwelveKeyKeyboard(context: context)
      }
    }
  }

  /// What the key views need.
  @MainActor
  struct KeyContext {
    let controller: KeyboardController
    let state: KeyboardHostState
    let inputViewController: UIInputViewController
    let rowHeight: CGFloat

    var spaceLabel: String {
      if controller.isComposing { return "次候補" }
      return controller.inputMode == .hiragana || controller.settings.kanaLayout == .twelveKeys ? "空白" : "space"
    }

    /// The enter key's symbol: ⏎ for a newline, a magnifier to search; nil shows `enterLabel`.
    var enterImage: String? {
      if controller.isComposing { return nil }
      switch state.returnKeyType {
      case .default: return "return.left"
      case .google, .yahoo, .search: return "magnifyingglass"
      default: return nil
      }
    }

    var enterLabel: String {
      if controller.isComposing { return "確定" }
      let japanese = controller.inputMode == .hiragana
      switch state.returnKeyType {
      case .go: return japanese ? "開く" : "go"
      case .google, .yahoo, .search: return japanese ? "検索" : "search"
      case .join: return japanese ? "参加" : "join"
      case .next: return japanese ? "次へ" : "next"
      case .route: return japanese ? "経路" : "route"
      case .send: return japanese ? "送信" : "send"
      case .done: return japanese ? "完了" : "done"
      case .emergencyCall: return japanese ? "緊急" : "SOS"
      case .continue: return japanese ? "続ける" : "continue"
      default: return japanese ? "改行" : "return"
      }
    }

    /// The enter key is blue for actions other than a newline (as on the system keyboard).
    var enterIsProminent: Bool {
      !controller.isComposing && state.returnKeyType != .default
    }
  }

  /// Key presses go through here (haptics, then the controller).
  @MainActor
  struct KeyActions {
    let controller: KeyboardController?
    let state: KeyboardHostState?

    private static let feedback = UIImpactFeedbackGenerator(style: .light)

    func feedback() {
      guard let controller, let state, controller.settings.haptics, state.hasFullAccess else { return }
      Self.feedback.impactOccurred()
    }

    func input(_ text: String) {
      state?.showsAllCandidates = false
      controller?.input(text)
    }

    func perform(_ function: KeyboardFunction) {
      controller?.perform(function)
    }

    /// The key whose kana the next tap toggles (highlighted like a pressed key).
    var togglingKey: String? { controller?.togglingKey }

    /// While a flick guide is shown, the other keys' labels dim.
    var dimsLabels: Bool { state?.showsFlickGuide ?? false }

    func setShowsFlickGuide(_ shown: Bool) {
      guard state?.showsFlickGuide != shown else { return }
      state?.showsFlickGuide = shown
    }
  }

  extension EnvironmentValues {
    @Entry var keyActions = KeyActions(controller: nil, state: nil)
  }

  // MARK: - 12 keys

  struct TwelveKeyKeyboard: View {
    let context: KeyContext

    private var keys: [[CharacterKey]] {
      switch context.controller.inputMode {
      case .hiragana: KeyboardKeys.kana
      case .alphabet: KeyboardKeys.alphabet
      case .digit: KeyboardKeys.number
      }
    }

    var body: some View {
      let spacing = KeyboardMetrics.rowSpacing
      let mode = context.controller.inputMode
      HStack(spacing: KeyboardMetrics.columnSpacing) {
        VStack(spacing: spacing) {
          if context.controller.settings.flickOnly {
            modeKeys
          } else {
            toggleKeys(mode)
          }
        }
        .containerRelativeFrame(.horizontal) { width, _ in Self.columnWidth(width) }
        VStack(spacing: spacing) {
          ForEach(keys.indices, id: \.self) { row in
            HStack(spacing: KeyboardMetrics.columnSpacing) {
              ForEach(keys[row].indices, id: \.self) { column in
                if mode == .hiragana, row == keys.count - 1, column == 0, !context.controller.isComposing {
                  // as on the system keyboard: the emoticons until something is typed, then 小゛゜
                  FunctionKey(
                    title: "^_^", height: context.rowHeight, labelSize: 16.5, labelTracking: -3,
                    labelOffset: CGSize(width: -1.3, height: -1)
                  ) {
                    $0.perform(.kaomoji)
                  }
                } else {
                  FlickKey(
                    key: keys[row][column], height: context.rowHeight, isLastColumn: column == keys[row].count - 1)
                }
              }
            }
          }
        }
        .frame(maxWidth: .infinity)
        VStack(spacing: spacing) {
          FunctionKey(systemImage: "delete.left", height: context.rowHeight, repeats: true) { $0.perform(.backspace) }
          SpaceKey(title: context.spaceLabel, height: context.rowHeight)
          EnterKey(
            title: context.enterLabel, systemImage: context.enterImage, prominent: context.enterIsProminent,
            height: 2 * context.rowHeight + spacing)
        }
        .containerRelativeFrame(.horizontal) { width, _ in Self.columnWidth(width) }
      }
    }

    /// The left column as on the system keyboard with toggle input: → and ↺ (gray without a composition), then a
    /// tall key to the next input mode (ABC → ☆123 → あいう).
    @ViewBuilder
    private func toggleKeys(_ mode: IosEngine.InputMode) -> some View {
      let composing = context.controller.isComposing
      FunctionKey(
        title: "⟶", height: context.rowHeight, isEnabled: composing, labelSize: 21,
        labelOffset: CGSize(width: 0, height: -4.7)
      ) {
        $0.perform(.advance)
      }
      FunctionKey(
        systemImage: "arrow.counterclockwise", height: context.rowHeight, isEnabled: composing, labelSize: 18.7
      ) {
        $0.perform(.undo)
      }
      let next: (title: String, mode: IosEngine.InputMode) =
        switch mode {
        case .hiragana: ("ABC", .alphabet)
        case .alphabet: ("☆123", .digit)
        case .digit: ("あいう", .hiragana)
        }
      modeKey(next.title, next.mode)
    }

    /// The left column with flick only: ☆123, ABC and a tall あいう.
    @ViewBuilder
    private var modeKeys: some View {
      FunctionKey(title: "☆123", height: context.rowHeight) { $0.perform(.inputMode(.digit)) }
      FunctionKey(title: "ABC", height: context.rowHeight) { $0.perform(.inputMode(.alphabet)) }
      modeKey("あいう", .hiragana)
    }

    /// The tall bottom-left key; the globe takes its lower half when the system asks for one.
    @ViewBuilder
    private func modeKey(_ title: String, _ mode: IosEngine.InputMode) -> some View {
      if context.state.needsInputModeSwitchKey {
        FunctionKey(title: title, height: context.rowHeight) { $0.perform(.inputMode(mode)) }
        GlobeOrDismissKey(context: context)
      } else {
        FunctionKey(title: title, height: 2 * context.rowHeight + KeyboardMetrics.rowSpacing) {
          $0.perform(.inputMode(mode))
        }
      }
    }

    /// Five columns of the same width; the function keys take the outer ones.
    static func columnWidth(_ width: CGFloat) -> CGFloat {
      (width - 2 * KeyboardMetrics.sidePadding - 4 * KeyboardMetrics.columnSpacing) / 5
    }
  }

  // MARK: - QWERTY

  struct QwertyKeyboard: View {
    let context: KeyContext

    var body: some View {
      let spacing = KeyboardMetrics.columnSpacing
      let mode = context.controller.inputMode
      let isKana = mode == .hiragana
      let rows =
        mode == .digit
        ? KeyboardKeys.qwertySymbols
        : KeyboardKeys.qwerty(kana: isKana, uppercase: context.controller.isShifted)
      VStack(spacing: KeyboardMetrics.rowSpacing) {
        letterRow(rows[0])
        letterRow(rows[1])
        HStack(spacing: spacing) {
          if mode == .alphabet {
            FunctionKey(
              systemImage: context.controller.isShifted ? "shift.fill" : "shift", height: context.rowHeight
            ) { $0.perform(.shift) }
            .frame(width: 44)
          } else if isKana {
            QwertyKey(key: CharacterKey("、", tap: ","), height: context.rowHeight)
          }
          letterRow(rows[2])
          if isKana {
            QwertyKey(key: CharacterKey("。", tap: "."), height: context.rowHeight)
          }
          FunctionKey(systemImage: "delete.left", height: context.rowHeight, repeats: true) { $0.perform(.backspace) }
            .frame(width: 44)
        }
        HStack(spacing: spacing) {
          FunctionKey(title: mode == .digit ? "ABC" : "123", height: context.rowHeight) {
            $0.perform(.inputMode(mode == .digit ? .alphabet : .digit))
          }
          .frame(width: 50)
          FunctionKey(title: isKana ? "ABC" : "あいう", height: context.rowHeight) {
            $0.perform(.inputMode(isKana ? .alphabet : .hiragana))
          }
          .frame(width: 50)
          GlobeOrDismissKey(context: context)
            .frame(width: 44)
          SpaceKey(title: context.spaceLabel, height: context.rowHeight)
          EnterKey(
            title: context.enterLabel, systemImage: context.enterImage, prominent: context.enterIsProminent,
            height: context.rowHeight
          )
          .frame(width: 88)
        }
      }
    }

    private func letterRow(_ keys: [CharacterKey]) -> some View {
      HStack(spacing: KeyboardMetrics.columnSpacing) {
        ForEach(keys) { key in
          QwertyKey(key: key, height: context.rowHeight)
            .containerRelativeFrame(.horizontal) { width, _ in
              (width - 2 * KeyboardMetrics.sidePadding) / 10 - KeyboardMetrics.columnSpacing
            }
        }
      }
    }
  }
#endif
