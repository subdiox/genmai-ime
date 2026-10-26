// The iOS app's entry point; the UI is GenmaiIOSApp in the Swift package.

import GenmaiIOS
import GenmaiIOSApp
import SwiftUI

#if DEBUG
  import GenmaiIOSKeyboard
#endif

@main
struct GenmaiApp: App {
  init() {
    // The settings and the user dictionary live in the app group, shared with the keyboard extension.
    SharedContainer.useSharedProfile()
  }

  var body: some Scene {
    WindowGroup {
      #if DEBUG
        // development: the keyboard in the app's window (`-keyboardPreview`)
        if ProcessInfo.processInfo.arguments.contains("-keyboardPreview") {
          KeyboardPreview()
        } else if ProcessInfo.processInfo.arguments.contains("-textField") {
          TextFieldTest()
        } else {
          GenmaiIOSRootView()
        }
      #else
        GenmaiIOSRootView()
      #endif
    }
  }
}

#if DEBUG
  /// development: only a text field, focused at launch (`-textField`), to compare keyboards on a device
  private struct TextFieldTest: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
      TextEditor(text: $text)
        .focused($focused)
        .padding()
        .onAppear { focused = true }
    }
  }
#endif
