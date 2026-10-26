// SwiftUI replacement of mozc/src/gui/dictionary_tool/import_dialog.{h,cc,ui} (3.35.6354).

#if os(macOS)
  import AppKit
  import GenmaiClient
  import SwiftUI

  private let kContext = "genmai::gui::ImportDialog"

  /// The values of an accepted import dialog.
  struct ImportDialogResult: Equatable {
    var fileName: String
    var dicName: String
    var imeType: IMEType
    var encodingType: EncodingType
  }

  @MainActor
  @Observable
  final class ImportDialogModel {
    let mode: DictionaryToolModel.ImportMode
    var fileName = ""
    var dicName = ""
    var imeType: IMEType = .imeAutoDetect
    var encodingType: EncodingType = .encodingAutoDetect

    /// ime_combobox_ items (the non-Windows order).
    static let imeTypes: [(IMEType, String)] = [
      (.imeAutoDetect, "Auto detection"), (.google, "Google"), (.kotoeri, "Kotoeri"), (.atok, "ATOK"),
      (.msime, "Microsoft IME"),
    ]

    /// encoding_combobox_ items.
    static let encodingTypes: [(EncodingType, String)] = [
      (.encodingAutoDetect, "Auto detection"), (.utf16, "Unicode"), (.shiftJIS, "Shift JIS"), (.utf8, "UTF-8"),
    ]

    init(mode: DictionaryToolModel.ImportMode) {
      self.mode = mode
    }

    /// ImportDialog::IsAcceptButtonEnabled.
    var isAcceptButtonEnabled: Bool {
      (mode == .create && !fileName.isEmpty && !dicName.isEmpty) || (mode == .append && !fileName.isEmpty)
    }

    var result: ImportDialogResult {
      ImportDialogResult(fileName: fileName, dicName: dicName, imeType: imeType, encodingType: encodingType)
    }

    /// ImportDialog::SelectFile.
    func selectFile() {
      let panel = NSOpenPanel()
      panel.title = tr(kContext, "Import dictionary")
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = false
      panel.directoryURL =
        fileName.isEmpty
        ? FileManager.default.homeDirectoryForCurrentUser
        : URL(fileURLWithPath: fileName).deletingLastPathComponent()
      if panel.runModal() == .OK, let url = panel.url {
        fileName = url.path
      }
    }
  }

  struct ImportDialogView: View {
    @State private var model: ImportDialogModel
    let completion: (ImportDialogResult?) -> Void

    init(mode: DictionaryToolModel.ImportMode, completion: @escaping (ImportDialogResult?) -> Void) {
      _model = State(initialValue: ImportDialogModel(mode: mode))
      self.completion = completion
    }

    var body: some View {
      @Bindable var model = model
      VStack(spacing: 0) {
        Form {
          Section {
            ImportFileRow(model: model)
            if model.mode == .create {
              TextField(tr("ImportDialog", "Dictionary Name"), text: $model.dicName)
            }
          } header: {
            Text(DictionaryToolStrings.text(.importTitle))
          }
          Section {
            Picker(DictionaryToolStrings.text(.format), selection: $model.imeType) {
              ForEach(ImportDialogModel.imeTypes, id: \.0) { type, label in
                Text(tr(kContext, label)).tag(type)
              }
            }
            Picker(DictionaryToolStrings.text(.encoding), selection: $model.encodingType) {
              ForEach(ImportDialogModel.encodingTypes, id: \.0) { type, label in
                Text(tr(kContext, label)).tag(type)
              }
            }
          }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button(DictionaryToolStrings.text(.cancel), role: .cancel) { completion(nil) }
            .keyboardShortcut(.cancelAction)
          Button(DictionaryToolStrings.text(.importAction)) { completion(model.result) }
            .disabled(!model.isAcceptButtonEnabled)
            .keyboardShortcut(.defaultAction)
        }
        .padding([.horizontal, .bottom], 20)
      }
      .frame(width: 440)
    }
  }

  /// The file location: the chosen file's name and a button that opens the file panel.
  private struct ImportFileRow: View {
    let model: ImportDialogModel

    var body: some View {
      LabeledContent(DictionaryToolStrings.text(.file)) {
        HStack(spacing: 8) {
          if model.fileName.isEmpty {
            Text(DictionaryToolStrings.text(.noFileSelected))
              .foregroundStyle(.secondary)
          } else {
            Label(
              (model.fileName as NSString).lastPathComponent,
              systemImage: "doc.text"
            )
            .lineLimit(1)
            .truncationMode(.middle)
            .help(model.fileName)
          }
          Button(DictionaryToolStrings.text(.chooseFile)) { model.selectFile() }
        }
      }
    }
  }
#endif
