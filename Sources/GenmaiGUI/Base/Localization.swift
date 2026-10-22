// Replacement of Qt's translation machinery used by mozc/src/gui (QObject::tr + gui/base/util.cc
// InstallTranslator / ReplaceString) (3.35.6354).
//
// Qt loads `<dialog>_<lang>.qm` and translates English source strings per class context. The Swift GUI keeps
// the same keys: `tr("genmai::gui::ConfigDialog", "Reset to default")`. Japanese strings are generated from the
// .qtts files into GUIStrings.swift by Tools/generate_gui_strings.py; any other language shows the source.

import Foundation
import Synchronization

public enum GUILanguage: Sendable, Equatable {
  case english
  case japanese

  /// The language used by the GUI: Japanese if the user's first preferred language is Japanese.
  public static var current: GUILanguage {
    if let override = overrideForTesting.withLock({ $0 }) {
      return override
    }
    let first = Locale.preferredLanguages.first ?? "en"
    return first.hasPrefix("ja") ? .japanese : .english
  }

  static let overrideForTesting = Mutex<GUILanguage?>(nil)

  /// Forces a language (tests / previews). Pass nil to restore the system preference.
  public static func setOverride(_ language: GUILanguage?) {
    overrideForTesting.withLock { $0 = language }
  }
}

/// The product name substituted for "[ProductName]" (gui/base/util.cc: GuiUtil::ReplaceString).
public let kProductNameInEnglish = "Genmai"

/// Translates `source` in the Qt class context `context`, replaces "[ProductName]" and strips the Qt
/// mnemonic markers ("&File", "ファイル(&F)").
public func tr(_ context: String, _ source: String, language: GUILanguage = .current) -> String {
  var text = source
  if language == .japanese,
    let translated = kGenmaiJapaneseTranslations[context]?[source] ?? kJapaneseTranslations[context]?[source]
  {
    text = translated
  }
  return GUIUtil.replaceString(GUIUtil.stripMnemonic(text))
}

public enum GUIUtil {
  /// Mirrors GuiUtil::ReplaceString: "[ProductName]" -> product name.
  public static func replaceString(_ str: String) -> String {
    str.replacingOccurrences(of: "[ProductName]", with: kProductNameInEnglish)
  }

  /// Removes Qt mnemonics: "(&X)" suffixes used by Japanese strings and single '&' markers; "&&" -> "&".
  public static func stripMnemonic(_ str: String) -> String {
    guard str.contains("&") else { return str }
    var result = str
    if let range = result.range(of: #"\(&[A-Za-z0-9]\)"#, options: .regularExpression) {
      result.removeSubrange(range)
    }
    var out = ""
    var iterator = result.makeIterator()
    while let ch = iterator.next() {
      if ch == "&" {
        if let next = iterator.next() {
          out.append(next)
        }
        continue
      }
      out.append(ch)
    }
    return out
  }
}
