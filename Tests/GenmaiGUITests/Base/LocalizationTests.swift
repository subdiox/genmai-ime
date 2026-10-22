// Tests of the Qt translation replacement (tr / GuiUtil::ReplaceString) and the rich-text label parser.

import Foundation
import GenmaiBase
import Testing

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
}

@Suite struct AboutAndErrorDialogTests {
  @Test func aboutContent() {
    let content = AboutDialogContent(language: .english, creditsPath: "/tmp/credits_en.html")
    #expect(content.windowTitle == "About Genmai")
    #expect(content.productName == "Genmai")
    #expect(content.version == "Version " + Version.getProductVersion())
    #expect(content.copyright == "Copyright © 2026 subdiox")
    #expect(content.creditsURL == URL(filePath: "/tmp/credits_en.html"))

    let ja = AboutDialogContent(language: .japanese, creditsPath: "/tmp/credits_en.html")
    #expect(ja.windowTitle == "Genmai について")
    #expect(ja.version == "バージョン " + Version.getProductVersion())
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
        == "変換エンジンを起動できません。Mac を再起動してください。")
    #expect(ErrorMessageDialog.title(language: .japanese) == "Genmai エラー")
  }
}
