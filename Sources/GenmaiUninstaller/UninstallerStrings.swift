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
  /// `needsAuthorization`: Genmai is installed for all users (administrator rights, Touch ID or password).
  func confirmMessage(needsAuthorization: Bool) -> String {
    needsAuthorization
      ? pick(
        "Genmai will be removed from this Mac. You’ll be asked to authenticate as an administrator.",
        "このMacからGenmaiを削除します。管理者として認証を求められます。")
      : pick("Genmai will be removed for your user account.", "このユーザーのGenmaiを削除します。")
  }
  var alsoRemove: String { pick("Also remove", "次のデータも削除する") }
  var keptNote: String {
    pick("Data you don’t select is kept for a later installation.", "選んでいないデータは残り、再インストールすると使えます。")
  }

  func userDataName(_ kind: UserDataKind) -> String {
    switch kind {
    case .aiModel: pick("AI model", "AIモデル")
    case .userDictionary: pick("User dictionary", "ユーザー辞書")
    case .learning: pick("Learning data and input history", "学習データと入力履歴")
    case .settings: pick("Settings", "設定")
    }
  }

  func userDataDetail(_ kind: UserDataKind) -> String {
    switch kind {
    case .aiModel: pick("The downloaded language model", "ダウンロードした言語モデル")
    case .userDictionary: pick("Words you registered", "登録した単語")
    case .learning: pick("What conversion learned from your typing", "入力から学習した変換の結果と履歴")
    case .settings: pick("Genmai’s preferences", "Genmaiの各種設定")
    }
  }
  var cancel: String { pick("Cancel", "キャンセル") }
  var uninstall: String { pick("Uninstall…", "アンインストール…") }

  func itemName(_ kind: RemoveItem.Kind) -> String {
    switch kind {
    case .inputMethod: pick("Genmai input method (for all users)", "Genmai入力メソッド（すべてのユーザー用）")
    case .userInputMethod: pick("Genmai input method (for this user)", "Genmai入力メソッド（このユーザー用）")
    }
  }

  // Removing

  var removing: String { pick("Removing Genmai…", "Genmaiを削除しています…") }

  // Success

  var succeededTitle: String { pick("Genmai Has Been Removed", "Genmaiを削除しました") }
  var succeededMessage: String {
    pick(
      "Log out to finish. Until then, apps that are already open may keep using Genmai.",
      "ログアウトすると削除が完了します。それまでは、開いているアプリでGenmaiが使われ続けることがあります。")
  }
  var later: String { pick("Later", "後で") }
  var logOutNow: String { pick("Log Out Now", "今すぐログアウト") }

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
