// SwiftUI replacement of mozc/src/gui/dictionary_tool/find_dialog.{h,cc,ui} (3.35.6354).
// The search logic (FindDialog::Find / Match) lives in DictionaryToolModel.find(_:direction:).

import SwiftUI

struct FindDialogView: View {
  let model: DictionaryToolModel
  @State private var query = ""
  @State private var lastDirection: DictionaryToolModel.FindDirection = .forward
  @FocusState private var queryFocused: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(tr("FindDialog", "Reading or Word:"))
        TextField("", text: $query)
          .focused($queryFocused)
          .frame(minWidth: 200)
          .onSubmit { find(lastDirection) }
      }
      HStack {
        Spacer()
        Button(tr("FindDialog", "Cancel"), role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(tr("FindDialog", "Up")) { find(.backward) }
          .disabled(query.isEmpty)
        Button(tr("FindDialog", "Down")) { find(.forward) }
          .disabled(query.isEmpty)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .navigationTitle(tr("FindDialog", "[ProductName] Dictionary Find Dialog"))
    .onAppear {
      queryFocused = true
      model.resetFind()
    }
    .onDisappear { model.resetFind() }
  }

  private func find(_ direction: DictionaryToolModel.FindDirection) {
    lastDirection = direction
    model.find(query, direction: direction)
  }
}
