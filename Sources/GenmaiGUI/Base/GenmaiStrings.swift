// Japanese strings of Genmai's own UI texts (not part of Mozc): texts the redesigned windows add or word
// differently from Mozc's Qt dialogs. `tr` looks here before Mozc's translations (GUIStrings.swift), so an
// entry also replaces a Mozc translation for the same English source. Key: context, then English source.

let kGenmaiJapaneseTranslations: [String: [String: String]] = [
  "Settings": [
    "[ProductName] Settings": "[ProductName] 設定",
    // Panes
    "General": "一般",
    "Input": "入力",
    "Conversion": "変換",
    "Suggestions": "サジェスト",
    "AI": "AI",
    "Privacy": "プライバシー",
    "Updates": "アップデート",
    // General
    "Typing": "入力",
    "Input method": "入力方式",
    "Romaji input": "ローマ字入力",
    "Kana input": "かな入力",
    "Key bindings": "キー操作",
    "Customize…": "カスタマイズ…",
    "Romaji table": "ローマ字テーブル",
    "The custom key bindings are empty. Customize them, or choose another style; until then the settings are not saved.":
      "カスタムのキー操作が空です。カスタマイズするか、別の設定を選んでください。それまで設定は保存されません。",
    "Characters": "文字",
    "Punctuation": "句読点",
    "Symbols": "記号",
    "Space": "スペース",
    "Numeric keypad": "テンキー",
    "¥ key": "¥ キー",
    "Candidates": "候補",
    "Selection shortcut": "候補を選ぶショートカット",
    "None": "なし",
    "1–9": "1〜9",
    "A–L": "A〜L",
    "Reset": "リセット",
    "Reset All Settings…": "すべての設定を初期値に戻す…",
    "Personalization data and input history are kept.": "学習データと入力履歴は残ります。",
    "Do you want to reset all settings to their defaults? Personalization data and input history are kept.":
      "すべての設定を初期値に戻しますか？学習データと入力履歴は残ります。",
    // Input
    "Input assistance": "入力補助",
    "Switch to halfwidth automatically": "自動で半角英数に切り替える",
    "Switches to halfwidth alphanumerics when the input looks like English, a URL or a number.":
      "英単語、URL、数字のような入力を自動で半角英数にします。",
    "Shift key switches to": "Shift キーで切り替える入力",
    "Convert at punctuation": "句読点で自動変換する",
    "Always use the Japanese keyboard layout": "日本語入力では常に日本語キー配列を使う",
    "Fullwidth and halfwidth": "全角と半角",
    // Conversion
    "Learning": "学習",
    "Learn from what you type": "入力内容から学習する",
    "Yes": "する",
    "Yes, without recording new data": "する（新しく記録しない）",
    "No": "しない",
    "Clear Personalization Data…": "学習データを消去…",
    "Dictionaries": "辞書",
    "User dictionary": "ユーザー辞書",
    "Edit…": "編集…",
    "Homonym dictionary": "同音異義語辞書",
    "Shows how words with the same reading differ, next to the candidates.":
      "同じ読みの言葉の使い分けを候補の横に表示します。",
    "Special conversions": "特殊変換",
    "Single kanji": "単漢字",
    "Symbols and arrows": "記号",
    "Emoticons": "顔文字",
    "Katakana to English": "カタカナ英語",
    "Postal codes": "郵便番号",
    "Spelling correction (もしかして)": "「もしかして」変換",
    "Calculator": "計算機",
    "Special numbers": "特殊数字",
    "Date and time": "日付と時刻",
    "Emoji": "絵文字",
    // Suggestions
    "Sources": "候補のもと",
    "Input history": "入力履歴",
    "System dictionary": "システム辞書",
    "Realtime conversion": "リアルタイム変換",
    "Shows the conversion of the whole input as the first suggestion.": "入力全体の変換結果を最初の候補に表示します。",
    "Display": "表示",
    "Maximum number of suggestions": "サジェストの最大数",
    // Privacy
    "Secret mode": "シークレットモード",
    "Temporarily stops learning, history-based suggestions and the user dictionary.":
      "学習、入力履歴からのサジェスト、ユーザー辞書を一時的に止めます。",
    "Presentation mode": "プレゼンテーションモード",
    "Temporarily hides all suggestions.": "すべてのサジェストを一時的に表示しません。",
    // Updates
    "Logging level (debug builds)": "ログレベル（デバッグビルド）",
    "Logging": "ログ",
  ],
  "About": [
    "About [ProductName]": "[ProductName] について",
    "Version %@": "バージョン %@",
    "Japanese input with on-device AI conversion": "端末内の AI で変換する日本語入力",
    "Website": "Web サイト",
    "Report an Issue": "問題を報告",
    "Acknowledgments": "謝辞",
  ],
]
