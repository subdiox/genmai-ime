// Tests of the Qt translation replacement (tr / GuiUtil::ReplaceString) and the rich-text label parser.

import Foundation
import Testing
import GenmaiBase

@testable import GenmaiGUI

@Suite struct LocalizationTests {
  @Test func translatesWithContext() {
    #expect(tr("ConfigDialog", "General", language: .japanese) == "一般")
    #expect(tr("ConfigDialog", "General", language: .english) == "General")
    // Unknown strings fall back to the source.
    #expect(tr("ConfigDialog", "No such string", language: .japanese) == "No such string")
  }

  @Test func replacesProductName() {
    #expect(tr("ConfigDialog", "[ProductName] Settings", language: .english) == "Genmai Settings")
    #expect(tr("ConfigDialog", "[ProductName] Settings", language: .japanese) == "Genmai プロパティ")
  }

  @Test func stripsMnemonics() {
    #expect(GUIUtil.stripMnemonic("&File") == "File")
    #expect(GUIUtil.stripMnemonic("ファイル(&F)") == "ファイル")
    #expect(GUIUtil.stripMnemonic("A && B") == "A & B")
    #expect(GUIUtil.stripMnemonic("plain") == "plain")
  }

  @Test func richTextLinks() {
    let html =
      "<html><body>Genmai <a href=\"https://example.com/\"><span style=\"x\">info</span></a> &amp; more</body></html>"
    let attributed = QtRichText.attributedString(html)
    #expect(String(attributed.characters) == "Genmai info & more")
    let links = attributed.runs.compactMap(\.link)
    #expect(links == [URL(string: "https://example.com/")!])
  }
}

@Suite struct AboutAndErrorDialogTests {
  @Test func aboutContent() {
    let content = AboutDialogContent(language: .english, creditsPath: "/tmp/credits_en.html")
    #expect(content.windowTitle == "About Genmai")
    #expect(content.version == "(" + Version.getProductVersion() + ")")
    #expect(String(content.terms.characters) == "Genmai product information issues")
    let termLinks = content.terms.runs.compactMap(\.link).map(\.absoluteString)
    #expect(termLinks == ["https://github.com/subdiox/genmai-ime", "https://github.com/subdiox/genmai-ime/issues"])
    #expect(content.credits.runs.compactMap(\.link).map(\.absoluteString) == ["file:///tmp/credits_en.html"])

    let ja = AboutDialogContent(language: .japanese, creditsPath: "/tmp/credits_en.html")
    #expect(ja.windowTitle == "Genmai について")
    #expect(String(ja.credits.characters).contains("オープンソースソフトウェア"))
  }

  @Test func errorMessages() {
    for type in [
      "server_timeout", "server_broken_message", "server_version_mismatch", "server_shutdown",
      "server_fatal", "renderer_version_mismatch", "renderer_fatal",
    ] {
      #expect(ErrorMessageDialog.message(forErrorType: type, language: .english) != nil)
    }
    #expect(ErrorMessageDialog.message(forErrorType: "unknown") == nil)
    #expect(
      ErrorMessageDialog.message(forErrorType: "server_fatal", language: .japanese)
        == "変換エンジンプログラムの起動に失敗しました。新しい Genmaiを利用するためにコンピュータを再起動してください。")
    #expect(ErrorMessageDialog.title(language: .japanese) == "Genmai エラー")
  }
}
