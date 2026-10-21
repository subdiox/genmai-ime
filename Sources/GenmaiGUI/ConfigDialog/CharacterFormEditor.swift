// Port of mozc/src/gui/config_dialog/character_form_editor.{h,cc} (3.35.6354).
//
// The Qt editor is a QTableWidget (Group / Composition / Conversion) with ComboBoxDelegates listing
// "Fullwidth", "Halfwidth" and "Remember". The preedit form of the Katakana group is not editable.

import GenmaiCore
import GenmaiProtocol
import Observation
import SwiftUI

/// What a cell of the editor shows (FormToString / StringToForm).
public enum CharacterFormChoice: Hashable, Sendable, CaseIterable {
  case fullWidth
  case halfWidth
  case remember
  /// "Unknown": any other form (e.g. NO_CONVERSION). Saved as FULL_WIDTH (the failsafe of StringToForm).
  case unknown

  init(_ form: Genmai_Config_Config.CharacterForm) {
    switch form {
    case .fullWidth: self = .fullWidth
    case .halfWidth: self = .halfWidth
    case .lastForm: self = .remember
    default: self = .unknown
    }
  }

  var form: Genmai_Config_Config.CharacterForm {
    switch self {
    case .fullWidth, .unknown: .fullWidth
    case .halfWidth: .halfWidth
    case .remember: .lastForm
    }
  }

  var title: String {
    switch self {
    case .fullWidth: tr("QObject", "Fullwidth")
    case .halfWidth: tr("QObject", "Halfwidth")
    case .remember: tr("QObject", "Remember")
    case .unknown: tr("QObject", "Unknown")
    }
  }

  /// The delegate's item list.
  static let selectable: [CharacterFormChoice] = [.fullWidth, .halfWidth, .remember]
}

public struct CharacterFormRow: Identifiable, Equatable, Sendable {
  public let id = UUID()
  /// The rule group ("ア", "0", "A", or a list of symbols).
  public var group: String
  public var preedit: CharacterFormChoice
  public var conversion: CharacterFormChoice

  /// GroupToString.
  public var groupTitle: String {
    switch group {
    case "ア": tr("QObject", "Katakana")
    case "0": tr("QObject", "Numbers")
    case "A": tr("QObject", "Alphabets")
    default: group
    }
  }

  /// Preedit Katakana is always FULLWIDTH; this item is not editable.
  public var isPreeditEditable: Bool { group != "ア" }
}

@MainActor
@Observable
public final class CharacterFormEditorModel {
  public var rows: [CharacterFormRow] = []

  public init() {}

  /// Load(config).
  public func load(_ config: Genmai_Config_Config) {
    // make sure that table isn't empty.
    let rules =
      config.characterFormRules.isEmpty
      ? ConfigHandler.defaultConfig().characterFormRules : config.characterFormRules
    rows = rules.map {
      CharacterFormRow(
        group: $0.group, preedit: CharacterFormChoice($0.preeditCharacterForm),
        conversion: CharacterFormChoice($0.conversionCharacterForm))
    }
  }

  /// Save(config).
  public func save(_ config: inout Genmai_Config_Config) {
    if rows.isEmpty {
      return
    }
    config.characterFormRules = rows.compactMap { row in
      if row.group.isEmpty {
        return nil
      }
      var rule = Genmai_Config_Config.CharacterFormRule()
      rule.group = row.group
      rule.preeditCharacterForm = row.preedit.form
      rule.conversionCharacterForm = row.conversion.form
      return rule
    }
  }
}

struct CharacterFormEditorView: View {
  @Bindable var model: CharacterFormEditorModel
  let onEdit: () -> Void

  var body: some View {
    let context = "genmai::gui::CharacterFormEditor"
    Table($model.rows) {
      TableColumn(tr(context, "Group")) { $row in
        Text(verbatim: row.groupTitle)
      }
      TableColumn(tr(context, "Composition")) { $row in
        CharacterFormPicker(selection: $row.preedit, onEdit: onEdit)
          .disabled(!row.isPreeditEditable)
      }
      TableColumn(tr(context, "Conversion")) { $row in
        CharacterFormPicker(selection: $row.conversion, onEdit: onEdit)
      }
    }
    .help(tr(context, "Character form editor"))
    .frame(minHeight: 140)
  }
}

struct CharacterFormPicker: View {
  @Binding var selection: CharacterFormChoice
  let onEdit: () -> Void

  var body: some View {
    Picker("", selection: $selection) {
      if selection == .unknown {
        Text(verbatim: CharacterFormChoice.unknown.title).tag(CharacterFormChoice.unknown)
      }
      ForEach(CharacterFormChoice.selectable, id: \.self) { choice in
        Text(verbatim: choice.title).tag(choice)
      }
    }
    .labelsHidden()
    .onChange(of: selection) { onEdit() }
  }
}
