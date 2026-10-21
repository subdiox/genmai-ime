// SwiftUI replacement of mozc/src/mac/Uninstaller/{English,Japanese}.lproj/Dialogs.xib (3.35.6354).
//
// Every xib window is a titled 367 x 198 panel: the message at the top left (system font) and push buttons at
// the bottom right, the OK button rightmost with Cancel / Later to its left.

import SwiftUI

struct DialogsView: View {
  let controller: DialogsController

  var body: some View {
    let strings = controller.strings
    VStack(alignment: .leading, spacing: 0) {
      Text(strings.message)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 16)
      DialogButtons(controller: controller, strings: strings)
    }
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, 16)
    .frame(width: 367, height: 198)
    .navigationTitle(strings.title)
  }
}

private struct DialogButtons: View {
  let controller: DialogsController
  let strings: UninstallerDialogStrings

  var body: some View {
    HStack(spacing: 12) {
      Spacer()
      if let cancelButton = strings.cancelButton {
        Button(cancelButton, action: cancel)
          .keyboardShortcut(.cancelAction)
          .frame(minWidth: 84)
      }
      Button(strings.okButton, action: ok)
        .frame(minWidth: 84)
    }
    .controlSize(.regular)
    .disabled(controller.isBusy)
  }

  private func cancel() {
    if controller.dialog == .confirm {
      controller.cancel()
    } else {
      controller.dialogCancel()
    }
  }

  private func ok() {
    if controller.dialog == .confirm {
      Task { await controller.runUninstall() }
    } else {
      controller.dialogOK()
    }
  }
}
