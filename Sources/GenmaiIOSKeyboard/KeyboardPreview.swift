// The keyboard in the app's own window, for development (not in Mozc): launched with `-keyboardPreview`, the debug
// app shows `KeyboardView` over a text area instead of its settings, so the keys can be looked at and tapped in a
// simulator without a software keyboard (Xcode 27 runs simulators headless).

#if os(iOS) && DEBUG
  import GenmaiAIClient
  import GenmaiBase
  import GenmaiClient
  import GenmaiCore
  import GenmaiIOS
  import SwiftUI
  import UIKit

  public struct KeyboardPreview: View {
    @State private var model = PreviewModel()

    public init() {}

    public var body: some View {
      VStack(spacing: 0) {
        ScrollView {
          // the marked text underlined, as text fields show it
          (Text(verbatim: model.document.text) + Text(verbatim: model.document.marked).underline(color: .blue))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        KeyboardView(
          controller: model.controller, state: model.state, inputViewController: model.inputViewController
        )
        .frame(height: KeyboardMetrics.height(for: UITraitCollection.current))
        .padding(.top, KeyboardMetrics.systemTopMargin)
        .background(KeyboardColors.background)
      }
      .onAppear { model.controller.activate(settings: KeyboardSettings.load()) }
    }

    @MainActor
    @Observable
    final class PreviewModel {
      let document = PreviewDocument()
      let state = KeyboardHostState()
      let inputViewController = UIInputViewController()
      let controller: KeyboardController

      init() {
        let aiHook = AIConversionHook.makeGenmai(settings: AIConversionSettings.load())
        controller = KeyboardController(
          engine: IosEngine(dataFilePath: OssDataManager.defaultDataPath, aiHook: aiHook))
        controller.document = document
        // as on an iPhone with Face ID, where the system draws the globe under the keyboard
        state.needsInputModeSwitchKey = false
      }
    }

    /// The text area as the keyboard's text field.
    @MainActor
    @Observable
    final class PreviewDocument: KeyboardTextDocument {
      var text = ""
      var marked = ""

      func insertText(_ text: String) {
        self.text += text
        marked = ""
      }
      func deleteBackward() {
        if !marked.isEmpty {
          marked.removeLast()
        } else if !text.isEmpty {
          text.removeLast()
        }
      }
      func setMarkedText(_ text: String, selectedRange: NSRange) { marked = text }
      func unmarkText() {
        text += marked
        marked = ""
      }
      func adjustTextPosition(byCharacterOffset offset: Int) {}
      var precedingText: String? { text }
    }
  }
#endif
