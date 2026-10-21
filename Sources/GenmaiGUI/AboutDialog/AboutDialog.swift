// Port of mozc/src/gui/about_dialog/about_dialog.{h,cc,ui} (3.35.6354).

import AppKit
import GenmaiBase
import SwiftUI

private let kContext = "AboutDialog"

/// The texts of the about dialog after GuiUtil::ReplaceWidgetLabels and the about dialog's ReplaceString.
public struct AboutDialogContent: Equatable, Sendable {
  public var windowTitle: String
  public var productName: String
  public var version: String
  public var copyright: String
  public var terms: AttributedString
  public var credits: AttributedString

  /// - Parameter creditsPath: the full path of credits_en.html (SystemUtil::GetDocumentDirectory()).
  public init(language: GUILanguage = .current, creditsPath: String) {
    windowTitle = tr(kContext, "About [ProductName]", language: language)
    productName = tr(kContext, "[ProductName]", language: language)
    version = "(" + Version.getProductVersion() + ")"
    copyright = tr(kContext, "Copyright 2026 Google LLC. All rights reserved.", language: language)
    let termsHTML = tr(
      kContext,
      "<html><body>[ProductName] <a href=\"[ProductUrl]\"><span style=\" text-decoration: underline; color:#0000ff;\">product information</span></a> <a href=\"[ForumUrl]\"><span style=\" text-decoration: underline; color:#0000ff;\">[ForumName]</span></a></body></html>",
      language: language)
    let creditsHTML = tr(
      kContext,
      "<html><body>[ProductName] is made possible by <a href=\"file://credits_en.html\"><span style=\" text-decoration: underline; color:#0000ff;\">open source software</span></a>.</body></html>",
      language: language)
    terms = QtRichText.attributedString(Self.replaceString(termsHTML, creditsPath: creditsPath, language: language))
    credits = QtRichText.attributedString(Self.replaceString(creditsHTML, creditsPath: creditsPath, language: language))
  }

  /// about_dialog.cc: ReplaceString (the OSS build branch).
  static func replaceString(_ str: String, creditsPath: String, language: GUILanguage) -> String {
    var replaced = GUIUtil.replaceString(str)
    replaced = replaced.replacingOccurrences(of: "[ProductUrl]", with: "https://github.com/subdiox/genmai-ime")
    replaced = replaced.replacingOccurrences(
      of: "[ForumUrl]", with: "https://github.com/subdiox/genmai-ime/issues")
    replaced = replaced.replacingOccurrences(
      of: "[ForumName]", with: tr("QObject", "issues", language: language))
    replaced = replaced.replacingOccurrences(of: "credits_en.html", with: creditsPath)
    return replaced
  }

  /// Where credits_en.html is installed: next to GenmaiTool.app in Mozc.app/Contents/Resources, or in the
  /// tool's own resources.
  @MainActor
  public static func defaultCreditsPath() -> String {
    let besideTool = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(
      "credits_en.html")
    if FileManager.default.fileExists(atPath: besideTool.path) {
      return besideTool.path
    }
    return Bundle.main.path(forResource: "credits_en", ofType: "html")
      ?? FileUtil.joinPath(SystemUtil.getDocumentDirectory(), "credits_en.html")
  }
}

public struct AboutDialogView: View {
  let content: AboutDialogContent
  let productImage: NSImage?
  @Environment(\.closeDialog) private var closeDialog

  @MainActor
  public init(content: AboutDialogContent? = nil, productImage: NSImage? = nil) {
    self.content = content ?? AboutDialogContent(creditsPath: AboutDialogContent.defaultCreditsPath())
    self.productImage =
      productImage ?? Bundle.main.image(forResource: "product_logo")
      ?? Bundle.main.image(forResource: "product_icon_32bpp-128")
  }

  public var body: some View {
    VStack(spacing: 0) {
      AboutHeaderView(content: content, productImage: productImage)
      AboutFooterView(content: content) { closeDialog() }
    }
    .frame(width: 440)
    .background(Color.white)
    .environment(\.colorScheme, .light)
    .environment(\.openURL, OpenURLAction { url in
      // we don't activate the link if about dialog is running as root
      guard RunLevel.isValidClientRunLevel() else { return .discarded }
      return .systemAction(url)
    })
    .navigationTitle(content.windowTitle)
  }
}

private struct AboutHeaderView: View {
  let content: AboutDialogContent
  let productImage: NSImage?

  var body: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 4) {
        // change font size for product name
        Text(verbatim: content.productName)
          .font(.system(size: 26))
          .accessibilityAddTraits(.isHeader)
        Text(verbatim: content.version)
          .font(.callout)
          .textSelection(.enabled)
      }
      Spacer()
      if let productImage {
        Image(nsImage: productImage)
          .resizable()
          .frame(width: 128, height: 128)
          .accessibilityHidden(true)
      }
    }
    .foregroundStyle(.black)
    .padding(.horizontal, 20)
    .padding(.top, 16)
  }
}

private struct AboutFooterView: View {
  let content: AboutDialogContent
  let onOK: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(content.terms)
      Text(content.credits)
      Text(verbatim: content.copyright)
        .font(.caption)
      HStack {
        Spacer()
        Button(tr(kContext, "OK"), action: onOK)
          .keyboardShortcut(.defaultAction)
      }
    }
    .font(.callout)
    .foregroundStyle(.black)
    .tint(.blue)
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(red: 236 / 255, green: 233 / 255, blue: 216 / 255))
  }
}
