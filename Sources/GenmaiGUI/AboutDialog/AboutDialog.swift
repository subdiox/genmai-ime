// The About window (app screen about_dialog): the app icon, name, version and tagline, links to the website, the
// issue tracker and the acknowledgments (credits_en.html: the licenses of Mozc and the other open source software
// Genmai is built on, which their licenses require to be shown), and the copyright.

import AppKit
import GenmaiBase
import SwiftUI

public struct AboutDialogContent: Equatable, Sendable {
  public static let websiteURL = URL(validLiteral: "https://github.com/subdiox/genmai-ime")
  public static let issuesURL = URL(validLiteral: "https://github.com/subdiox/genmai-ime/issues")

  public var windowTitle: String
  public var productName: String
  public var version: String
  public var tagline: String
  public var copyright: String
  public var creditsURL: URL

  /// - Parameter creditsPath: the full path of credits_en.html.
  public init(language: GUILanguage = .current, creditsPath: String) {
    windowTitle = tr("About", "About [ProductName]", language: language)
    productName = kProductNameInEnglish
    version = String(format: tr("About", "Version %@", language: language), Version.getProductVersion())
    tagline = tr("About", "Japanese input with on-device AI conversion", language: language)
    copyright = "Copyright © 2026 subdiox"
    creditsURL = URL(filePath: creditsPath)
  }

  /// Where credits_en.html is installed: next to the Genmai app in Genmai.app/Contents/Resources, or in the app's
  /// own resources.
  @MainActor
  public static func defaultCreditsPath() -> String {
    let besideApp = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(
      "credits_en.html")
    if FileManager.default.fileExists(atPath: besideApp.path) {
      return besideApp.path
    }
    return Bundle.main.path(forResource: "credits_en", ofType: "html")
      ?? FileUtil.joinPath(SystemUtil.getDocumentDirectory(), "credits_en.html")
  }
}

public struct AboutDialogView: View {
  let content: AboutDialogContent
  let icon: NSImage

  @MainActor
  public init(content: AboutDialogContent? = nil, icon: NSImage? = nil) {
    self.content = content ?? AboutDialogContent(creditsPath: AboutDialogContent.defaultCreditsPath())
    self.icon = icon ?? NSApplication.shared.applicationIconImage
  }

  public var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: icon)
        .resizable()
        .interpolation(.high)
        .frame(width: 112, height: 112)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .accessibilityHidden(true)
        .padding(.bottom, 12)
      Text(verbatim: content.productName)
        .font(.system(size: 28, weight: .bold))
        .accessibilityAddTraits(.isHeader)
      Text(verbatim: content.version)
        .font(.callout)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .padding(.top, 2)
      Text(verbatim: content.tagline)
        .font(.body)
        .multilineTextAlignment(.center)
        .padding(.top, 12)
      AboutLinks(content: content)
        .padding(.top, 20)
      Text(verbatim: content.copyright)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.top, 20)
    }
    .padding(.horizontal, 32)
    .padding(.top, 28)
    .padding(.bottom, 20)
    .frame(width: 380)
    .environment(
      \.openURL,
      OpenURLAction { url in
        // we don't activate the link if about dialog is running as root
        guard RunLevel.isValidClientRunLevel() else { return .discarded }
        return .systemAction(url)
      }
    )
    .navigationTitle(content.windowTitle)
  }
}

private struct AboutLinks: View {
  let content: AboutDialogContent
  @Environment(\.openURL) private var openURL

  var body: some View {
    HStack(spacing: 8) {
      Button(tr("About", "Website")) { openURL(AboutDialogContent.websiteURL) }
      Button(tr("About", "Report an Issue")) { openURL(AboutDialogContent.issuesURL) }
      Button(tr("About", "Acknowledgments")) { openURL(content.creditsURL) }
    }
    .controlSize(.regular)
  }
}
