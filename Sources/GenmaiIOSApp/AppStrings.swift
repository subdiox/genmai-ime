// English / Japanese strings of the iOS app that the macOS GUI does not have (the shared ones come from `tr`).

import GenmaiGUI

enum AppStrings {
  enum Key: CaseIterable, Sendable {
    case setup, setupSteps, openSettings, fullAccess, keyboard, kanaLayout, twelveKeys, qwerty, flickOnly,
      flickOnlyDetail, qwertyAlphabet, haptics, hapticsDetail, tryIt, tryItPlaceholder, about, version, sourceCode,
      licenses, aiFullAccess, done, cancel, newWord, editWord, deleteWord, reading, word, category, comment,
      dictionaries, newDictionary, renameDictionary, deleteDictionary, noWords, save
  }

  static let english: [Key: String] = [
    .setup: "Setup",
    .setupSteps:
      "1. Open Settings › General › Keyboard › Keyboards.\n2. Tap Add New Keyboard… and choose [ProductName].\n3. While typing, switch keyboards with the globe key.",
    .openSettings: "Open Settings",
    .fullAccess:
      "Turn on Allow Full Access so that the keyboard can use the settings and the user dictionary of this app, keep what it learns from your typing and play haptic feedback. Nothing you type leaves your device.",
    .keyboard: "Keyboard",
    .kanaLayout: "Kana input",
    .twelveKeys: "12 keys (flick)",
    .qwerty: "QWERTY (romaji)",
    .flickOnly: "Flick only",
    .flickOnlyDetail: "Repeated taps do not cycle through the characters of a key.",
    .qwertyAlphabet: "QWERTY for letters",
    .haptics: "Haptic feedback",
    .hapticsDetail: "Needs Full Access.",
    .tryIt: "Try It",
    .tryItPlaceholder: "Type here",
    .about: "About",
    .version: "Version",
    .sourceCode: "Source code",
    .licenses: "Licenses",
    .aiFullAccess:
      "AI conversion needs Full Access for the keyboard (Settings › General › Keyboard › Keyboards › Genmai): without it the keyboard cannot read the model downloaded here. Genmai sends nothing anywhere.",
    .done: "Done",
    .cancel: "Cancel",
    .newWord: "New Word",
    .editWord: "Edit Word",
    .deleteWord: "Delete",
    .reading: "Reading",
    .word: "Word",
    .category: "Part of speech",
    .comment: "Comment",
    .dictionaries: "Dictionaries",
    .newDictionary: "New Dictionary…",
    .renameDictionary: "Rename Dictionary…",
    .deleteDictionary: "Delete Dictionary…",
    .noWords: "No words",
    .save: "Save",
  ]

  static let japanese: [Key: String] = [
    .setup: "セットアップ",
    .setupSteps:
      "1.「設定」›「一般」›「キーボード」›「キーボード」を開きます。\n2.「新しいキーボードを追加…」で [ProductName] を選びます。\n3. 入力中に地球儀キーでキーボードを切り替えます。",
    .openSettings: "設定を開く",
    .fullAccess:
      "「フルアクセスを許可」をオンにすると、このアプリの設定とユーザー辞書がキーボードで使われ、入力から学習した内容の保存と触覚フィードバックが有効になります。入力した内容が端末の外に送られることはありません。",
    .keyboard: "キーボード",
    .kanaLayout: "かな入力",
    .twelveKeys: "12キー（フリック）",
    .qwerty: "QWERTY（ローマ字）",
    .flickOnly: "フリックのみ",
    .flickOnlyDetail: "同じキーを続けて押しても文字が切り替わりません。",
    .qwertyAlphabet: "英字は QWERTY",
    .haptics: "触覚フィードバック",
    .hapticsDetail: "フルアクセスが必要です。",
    .tryIt: "試し打ち",
    .tryItPlaceholder: "ここに入力",
    .about: "情報",
    .version: "バージョン",
    .sourceCode: "ソースコード",
    .licenses: "ライセンス",
    .aiFullAccess:
      "AI 変換を使うには、キーボードの「フルアクセスを許可」をオンにしてください（設定 › 一般 › キーボード › キーボード › Genmai）。オフのままではキーボードがここでダウンロードしたモデルを読み込めません。入力した文字がどこかへ送られることはありません。",
    .done: "完了",
    .cancel: "キャンセル",
    .newWord: "単語を追加",
    .editWord: "単語を編集",
    .deleteWord: "削除",
    .reading: "よみ",
    .word: "単語",
    .category: "品詞",
    .comment: "コメント",
    .dictionaries: "辞書",
    .newDictionary: "辞書を作成…",
    .renameDictionary: "辞書名を変更…",
    .deleteDictionary: "辞書を削除…",
    .noWords: "単語がありません",
    .save: "保存",
  ]

  static func text(_ key: Key, language: GUILanguage = .current) -> String {
    let table = language == .japanese ? japanese : english
    return (table[key] ?? english[key] ?? "").replacing("[ProductName]", with: kProductNameInEnglish)
  }
}
