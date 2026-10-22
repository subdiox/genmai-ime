// English / Japanese strings of the dictionary tool views that Mozc's Qt translations do not have (or have
// only in an outdated form: "..." instead of "…", "ユーザ" instead of "ユーザー"). Messages of the model keep
// using the Qt translations through tr().

import Foundation

enum DictionaryToolStrings {
  enum Key: CaseIterable, Sendable {
    case dictionaries, newDictionary, newDictionaryMenu, renameDictionaryMenu, deleteDictionaryMenu,
      importAsNewMenu, exportCurrentMenu, importToThisMenu, exportThisMenu, renameMenu,
      deleteMenu, editCommentMenu, moreMenu, addWord, deleteWords, findNext, findPrevious, searchPrompt, wordCountOne,
      wordCountMany, noDictionaries, noDictionariesDescription, noSelection, noSelectionDescription, noWords,
      noWordsDescription, unavailableTitle, close, cancel, create, rename, ok, newDictionaryTitle,
      renameDictionaryTitle, editCommentTitle, importTitle, importAction, file,
      noFileSelected, chooseFile, format, encoding
  }

  static let english: [Key: String] = [
    .dictionaries: "Dictionaries",
    .newDictionary: "New Dictionary",
    .newDictionaryMenu: "New Dictionary…",
    .renameDictionaryMenu: "Rename Dictionary…",
    .deleteDictionaryMenu: "Delete Dictionary…",
    .importAsNewMenu: "Import as New Dictionary…",
    .exportCurrentMenu: "Export Dictionary…",
    .importToThisMenu: "Import into This Dictionary…",
    .exportThisMenu: "Export This Dictionary…",
    .renameMenu: "Rename…",
    .deleteMenu: "Delete…",
    .editCommentMenu: "Edit Comment…",
    .moreMenu: "More",
    .addWord: "Add Word",
    .deleteWords: "Delete Selected Words",
    .findNext: "Find Next",
    .findPrevious: "Find Previous",
    .searchPrompt: "Reading or Word",
    .wordCountOne: "1 word",
    .wordCountMany: "%d words",
    .noDictionaries: "No Dictionaries",
    .noDictionariesDescription: "Create a dictionary to register your own words.",
    .noSelection: "No Dictionary Selected",
    .noSelectionDescription: "Select a dictionary in the sidebar.",
    .noWords: "No Words",
    .noWordsDescription: "Words you add to this dictionary appear here.",
    .unavailableTitle: "Can’t Open the User Dictionary",
    .close: "Close",
    .cancel: "Cancel",
    .create: "Create",
    .rename: "Rename",
    .ok: "OK",
    .newDictionaryTitle: "New Dictionary",
    .renameDictionaryTitle: "Rename Dictionary",
    .editCommentTitle: "Edit Comment",
    .importTitle: "Import Dictionary",
    .importAction: "Import",
    .file: "File",
    .noFileSelected: "No file selected",
    .chooseFile: "Choose…",
    .format: "Format",
    .encoding: "Encoding",
  ]

  static let japanese: [Key: String] = [
    .dictionaries: "辞書",
    .newDictionary: "新しい辞書",
    .newDictionaryMenu: "新しい辞書…",
    .renameDictionaryMenu: "辞書の名前を変更…",
    .deleteDictionaryMenu: "辞書を削除…",
    .importAsNewMenu: "新しい辞書としてインポート…",
    .exportCurrentMenu: "辞書をエクスポート…",
    .importToThisMenu: "この辞書にインポート…",
    .exportThisMenu: "この辞書をエクスポート…",
    .renameMenu: "名前を変更…",
    .deleteMenu: "削除…",
    .editCommentMenu: "コメントを編集…",
    .moreMenu: "その他",
    .addWord: "単語を追加",
    .deleteWords: "選択した単語を削除",
    .findNext: "次を検索",
    .findPrevious: "前を検索",
    .searchPrompt: "よみ・単語",
    .wordCountOne: "1 語",
    .wordCountMany: "%d 語",
    .noDictionaries: "辞書がありません",
    .noDictionariesDescription: "辞書を作成すると、自分の単語を登録できます。",
    .noSelection: "辞書が選択されていません",
    .noSelectionDescription: "サイドバーで辞書を選択してください。",
    .noWords: "単語がありません",
    .noWordsDescription: "この辞書に追加した単語がここに表示されます。",
    .unavailableTitle: "ユーザー辞書を開けません",
    .close: "閉じる",
    .cancel: "キャンセル",
    .create: "作成",
    .rename: "名前を変更",
    .ok: "OK",
    .newDictionaryTitle: "新しい辞書",
    .renameDictionaryTitle: "辞書の名前を変更",
    .editCommentTitle: "コメントを編集",
    .importTitle: "辞書をインポート",
    .importAction: "インポート",
    .file: "ファイル",
    .noFileSelected: "選択されていません",
    .chooseFile: "選択…",
    .format: "フォーマット",
    .encoding: "エンコード",
  ]

  static func text(_ key: Key, language: GUILanguage = .current) -> String {
    let table = language == .japanese ? japanese : english
    return table[key] ?? english[key] ?? ""
  }

  /// "1 word" / "12 words".
  static func wordCount(_ count: Int, language: GUILanguage = .current) -> String {
    count == 1
      ? text(.wordCountOne, language: language)
      : String(format: text(.wordCountMany, language: language), count)
  }
}
