// English / Japanese strings of the dictionary tool views that Mozc's Qt translations do not have (or have
// only in an outdated form: "..." instead of "…", "ユーザ" instead of "ユーザー"), including the messages of
// `DictionaryToolModel`. Message templates use QString::arg markers (%1, %2) for `DictionaryToolText.arg`.

import Foundation

enum DictionaryToolStrings {
  enum Key: CaseIterable, Sendable {
    case dictionaries, newDictionary, newDictionaryMenu, renameDictionaryMenu, deleteDictionaryMenu,
      importAsNewMenu, exportCurrentMenu, importToThisMenu, exportThisMenu, renameMenu,
      deleteMenu, editCommentMenu, moreMenu, addWord, deleteWords, findNext, findPrevious, searchPrompt, wordCountOne,
      wordCountMany, noDictionaries, noDictionariesDescription, noSelection, noSelectionDescription, noWords,
      noWordsDescription, unavailableTitle, close, cancel, create, rename, ok, newDictionaryTitle,
      renameDictionaryTitle, editCommentTitle, importTitle, importAction, file,
      noFileSelected, chooseFile, format, encoding,
      // Model messages
      defaultDictionaryName, newDictionaryNameLabel, renameDictionaryLabel, newCommentLabel, storageLocked,
      tooManyDictionaries, noDictionarySelected, confirmDeleteDictionary, tooManyWords, importFinished,
      importNotSupported, importTooManyWords, importInvalidEntries, importFatal, cannotOpenFile, exportFinished,
      confirmDeleteWord, confirmDeleteWords, cannotMoveWords, invalidReading, patternNotFound, findTitle,
      dictionaryTooLarge, invalidDictionaryName, dictionaryNameEmpty, dictionaryNameTooLong, dictionaryExists,
      fatalError
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
    .defaultDictionaryName: "User Dictionary 1",
    .newDictionaryNameLabel: "Name of the new dictionary",
    .renameDictionaryLabel: "New name of the dictionary",
    .newCommentLabel: "New comment",
    .storageLocked: "Another process is accessing the user dictionary file.",
    .tooManyDictionaries: "You can't have more than %1 dictionaries.",
    .noDictionarySelected: "No dictionary is selected.",
    .confirmDeleteDictionary: "Do you want to delete %1?",
    .tooManyWords: "You can't have more than %1 words in one dictionary.",
    .importFinished: "%1 entries are imported to %2.",
    .importNotSupported:
      "You have imported a file in an invalid or unsupported file format.\n\nPlease check the file format. ATOK11 or older format is not supported by %1.",
    .importTooManyWords:
      "%1 doesn't have enough space to import all words in the file. First %2 entries are imported.",
    .importInvalidEntries:
      "%1 entries are imported to %2.\n\nSome imported words were not recognized by %3. Please check the original import file.",
    .importFatal: "Failed to open the user dictionary.",
    .cannotOpenFile: "Can't open %1.",
    .exportFinished: "Dictionary export finished.",
    .confirmDeleteWord: "Do you want to delete this word?",
    .confirmDeleteWords: "Do you want to delete the selected words?",
    .cannotMoveWords: "Cannot move all the selected items.\nThe target dictionary can have maximum %1 entries.",
    .invalidReading: "An invalid character is included in the reading.",
    .patternNotFound: "Cannot find pattern %1",
    .findTitle: "Find",
    .dictionaryTooLarge:
      "The user dictionary is getting dangerously large. If the dictionary file grows larger than 256 MB, none of its words are loaded, to keep the converter from stalling.",
    .invalidDictionaryName: "An invalid character is included in the dictionary name.",
    .dictionaryNameEmpty: "Dictionary name is empty.",
    .dictionaryNameTooLong: "Dictionary name is too long.",
    .dictionaryExists: "Dictionary already exists.",
    .fatalError: "A fatal error occurred.",
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
    .defaultDictionaryName: "ユーザー辞書 1",
    .newDictionaryNameLabel: "辞書名",
    .renameDictionaryLabel: "新しい辞書名",
    .newCommentLabel: "新しいコメント",
    .storageLocked: "別のアプリケーションがユーザー辞書を使用しています。",
    .tooManyDictionaries: "辞書は %1 個までしか作成できません。",
    .noDictionarySelected: "辞書が選択されていません。",
    .confirmDeleteDictionary: "「%1」を削除しますか？",
    .tooManyWords: "1 つの辞書に登録できる単語は %1 語までです。",
    .importFinished: "「%2」に %1 語をインポートしました。",
    .importNotSupported:
      "このファイルは無効な形式か、%1 が対応していない形式です。\n\nファイルの形式を確認してください。ATOK・ことえり・MS-IME のバイナリ形式の辞書は、それぞれの辞書ツールでテキスト形式に書き出してからインポートしてください。ATOK11 以前の形式には対応していません。",
    .importTooManyWords:
      "「%1」にはファイルのすべての単語をインポートする空きがありません。先頭の %2 語をインポートしました。",
    .importInvalidEntries:
      "「%2」に %1 語をインポートしました。\n\n%3 で扱えない可能性のある単語が含まれています。インポート元のファイルを確認してください。",
    .importFatal: "ユーザー辞書を開けませんでした。",
    .cannotOpenFile: "%1 を開けません。",
    .exportFinished: "辞書のエクスポートが完了しました。",
    .confirmDeleteWord: "この単語を削除しますか？",
    .confirmDeleteWords: "選択した単語を削除しますか？",
    .cannotMoveWords: "選択したすべての単語は移動できません。\n移動先の辞書に登録できる単語は %1 語までです。",
    .invalidReading: "よみに使用できない文字が含まれています。",
    .patternNotFound: "「%1」は見つかりませんでした。",
    .findTitle: "検索",
    .dictionaryTooLarge:
      "ユーザー辞書が非常に大きくなっています。辞書ファイルが 256 MB を超えると、変換エンジンが停止しないように、辞書の単語はすべて読み込まれなくなります。",
    .invalidDictionaryName: "辞書名に使用できない文字が含まれています。",
    .dictionaryNameEmpty: "辞書名が入力されていません。",
    .dictionaryNameTooLong: "辞書名が長すぎます。",
    .dictionaryExists: "同じ名前の辞書がすでにあります。",
    .fatalError: "エラーが発生しました。",
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
