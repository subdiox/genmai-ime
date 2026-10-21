// Strings of mozc/src/mac/Uninstaller/{English,Japanese}.lproj/Dialogs.xib and InfoPlist.strings
// (3.35.6354), verbatim (including the double spaces of the English messages and the "Mozc" product name).

import Foundation

enum UninstallerLanguage: Sendable, Equatable {
  case english
  case japanese

  /// Japanese if the user's first preferred language is Japanese (the xib localizations are English and
  /// Japanese; CFBundleDevelopmentRegion is English).
  static var current: UninstallerLanguage {
    (Locale.preferredLanguages.first ?? "en").hasPrefix("ja") ? .japanese : .english
  }
}

/// One dialog of Dialogs.xib: window title, message and push buttons.
struct UninstallerDialogStrings: Sendable, Equatable {
  var title: String
  var message: String
  /// The button bound to runUninstall: / dialogOK: (the rightmost one).
  var okButton: String
  /// The button bound to cancel: / dialogCancel: (left of the OK button), if any.
  var cancelButton: String?
}

enum UninstallerStrings {
  /// confirmDialog_ (window 367).
  static func confirm(_ language: UninstallerLanguage) -> UninstallerDialogStrings {
    switch language {
    case .english:
      UninstallerDialogStrings(
        title: "Uninstall", message: "Are you sure you want to uninstall Genmai?", okButton: "OK",
        cancelButton: "Cancel")
    case .japanese:
      UninstallerDialogStrings(
        title: "確認", message: "Genmaiを削除してもよろしいですか？", okButton: "OK", cancelButton: "キャンセル")
    }
  }

  /// reportAuthErrorDialog_ (window 468).
  static func authError(_ language: UninstallerLanguage) -> UninstallerDialogStrings {
    switch language {
    case .english:
      UninstallerDialogStrings(
        title: "Authentication failed",
        message: "Authentication failed.  Please ensure your username and password are correct.",
        okButton: "OK", cancelButton: nil)
    case .japanese:
      UninstallerDialogStrings(
        title: "認証の失敗", message: "認証に失敗しました。 名前とパスワードを確認してください。", okButton: "OK",
        cancelButton: nil)
    }
  }

  /// uninstallSucceededDialog_ (window 475).
  static func uninstallSucceeded(_ language: UninstallerLanguage) -> UninstallerDialogStrings {
    switch language {
    case .english:
      UninstallerDialogStrings(
        title: "Uninstall successful",
        message:
          "Genmai files have been erased. Please restart your computer to complete the uninstallation.",
        okButton: "Restart now", cancelButton: "Later")
    case .japanese:
      UninstallerDialogStrings(
        title: "削除の完了", message: "ファイルを削除しました。 再起動するとアンインストールが完了します。",
        okButton: "再起動", cancelButton: "後で")
    }
  }

  /// uninstallErrorDialog_ (window 492).
  static func uninstallError(_ language: UninstallerLanguage) -> UninstallerDialogStrings {
    switch language {
    case .english:
      UninstallerDialogStrings(
        title: "Uninstall failed", message: "Uninstallation failed.  Please try again.", okButton: "OK",
        cancelButton: nil)
    case .japanese:
      UninstallerDialogStrings(
        title: "アンインストールの失敗", message: "アンインストールに失敗しました。 お手数ですがもう一度お試しください。",
        okButton: "OK", cancelButton: nil)
    }
  }
}
