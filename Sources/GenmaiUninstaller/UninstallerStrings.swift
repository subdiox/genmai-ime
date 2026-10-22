// The uninstaller's user-visible strings (English and Japanese). Genmai's own wording: the window replaces the
// four dialogs of mozc/src/mac/Uninstaller/{English,Japanese}.lproj/Dialogs.xib (3.35.6354) with one flow.

import Foundation

enum UninstallerLanguage: Sendable, Equatable {
  case english
  case japanese

  /// Japanese if the user's first preferred language is Japanese (the bundle's localizations are English and
  /// Japanese; the development region is English).
  static var current: UninstallerLanguage {
    (Locale.preferredLanguages.first ?? "en").hasPrefix("ja") ? .japanese : .english
  }
}

struct UninstallerStrings: Sendable, Equatable {
  let language: UninstallerLanguage

  init(_ language: UninstallerLanguage = .current) {
    self.language = language
  }

  private func pick(_ english: String, _ japanese: String) -> String {
    language == .japanese ? japanese : english
  }

  var windowTitle: String { pick("Uninstall Genmai", "Genmaiのアンインストール") }

  // Confirmation

  var confirmTitle: String { pick("Uninstall Genmai?", "Genmaiをアンインストールしますか？") }
  var confirmMessage: String {
    pick(
      "Genmai will be removed from this Mac. You’ll be asked for an administrator password.",
      "このMacからGenmaiを削除します。管理者のパスワードの入力を求められます。")
  }
  var keptNote: String {
    pick(
      "Your settings, user dictionaries and the downloaded AI model are kept.",
      "設定、ユーザー辞書、ダウンロード済みのAIモデルは残ります。")
  }
  var cancel: String { pick("Cancel", "キャンセル") }
  var uninstall: String { pick("Uninstall…", "アンインストール…") }

  func itemName(_ kind: RemoveItem.Kind) -> String {
    switch kind {
    case .inputMethod: pick("Genmai input method", "Genmai入力メソッド")
    case .applicationsFolder: pick("Genmai folder with this uninstaller", "このアンインストーラを含むGenmaiフォルダ")
    case .manualInputMethod: pick("Genmai input method in your home folder", "ホームフォルダのGenmai入力メソッド")
    }
  }

  // Removing

  var removing: String { pick("Removing Genmai…", "Genmaiを削除しています…") }

  // Success

  var succeededTitle: String { pick("Genmai Has Been Removed", "Genmaiを削除しました") }
  var succeededMessage: String {
    pick(
      "Restart your Mac to finish. Until then, apps that are already open may keep using Genmai.",
      "Macを再起動すると削除が完了します。それまでは、開いているアプリでGenmaiが使われ続けることがあります。")
  }
  var later: String { pick("Later", "後で") }
  var restartNow: String { pick("Restart Now", "今すぐ再起動") }

  // Failure

  var failedTitle: String { pick("Genmai Wasn’t Removed", "Genmaiを削除できませんでした") }
  var authorizationFailedMessage: String {
    pick(
      "The administrator password wasn’t entered or wasn’t accepted, so nothing was removed.",
      "管理者のパスワードが入力されなかったか正しくなかったため、何も削除していません。")
  }
  var removalFailedMessage: String {
    pick(
      "Some of these items couldn’t be removed. Try again, or move them to the Trash in the Finder.",
      "一部の項目を削除できませんでした。もう一度試すか、Finderでゴミ箱に入れてください。")
  }
  var quit: String { pick("Quit", "終了") }
  var tryAgain: String { pick("Try Again…", "再試行…") }
}
