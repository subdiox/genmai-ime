// The welcome window (app screen welcome; not part of Mozc). The installer opens it once after the first installation
// (Tools/installer/postflight_template.sh): it says how to switch to Genmai and offers to turn on AI conversion,
// which is off by default and needs the model (downloaded here like the settings' Download button). A marker file
// in the user profile keeps it from showing again after updates.

import AppKit
import GenmaiBase
import GenmaiClient
import Observation
import SwiftUI
import Synchronization

/// English / Japanese strings of the welcome window.
public enum WelcomeStrings {
  public enum Key: CaseIterable, Sendable {
    case windowTitle, title, subtitle, switchTitle, switchDetail, aiTitle, aiDetail, enableAI, later, done,
      checking, downloading, installing, enabled, failed, settingsHint, openSettings
  }

  static let english: [Key: String] = [
    .windowTitle: "Welcome to [ProductName]",
    .title: "Welcome to [ProductName]",
    .subtitle: "Japanese input with on-device AI conversion",
    .switchTitle: "Log out to start using [ProductName]",
    .switchDetail:
      "After you log out and log back in, choose [ProductName] in the input menu in the menu bar, or switch with Control-Space.",
    .aiTitle: "AI conversion",
    .aiDetail:
      "In addition to the dictionary-based conversion, a language model on your Mac converts whole sentences. Your input is never sent over the network. Turning it on downloads the model (%@).",
    .enableAI: "Turn On AI Conversion",
    .later: "Not Now",
    .done: "Done",
    .checking: "Looking up the model…",
    .downloading: "Downloading… %@ of %@",
    .installing: "Installing…",
    .enabled: "AI conversion is on.",
    .failed: "Could not install the model: %@",
    .settingsHint: "You can change this at any time in the [ProductName] settings.",
    .openSettings: "Open Settings…",
  ]

  static let japanese: [Key: String] = [
    .windowTitle: "[ProductName] へようこそ",
    .title: "[ProductName] へようこそ",
    .subtitle: "端末内の AI で変換する日本語入力",
    .switchTitle: "ログアウトすると使えるようになります",
    .switchDetail: "ログアウトしてもう一度ログインしたあと、メニューバーの入力メニューで [ProductName] を選ぶか、Control+Space で切り替えます。",
    .aiTitle: "AI 変換",
    .aiDetail:
      "辞書を用いた変換に加えて、この Mac の中の言語モデルで文全体を変換します。入力内容がネットワークに送信されることはありません。オンにするとモデル（%@）をダウンロードします。",
    .enableAI: "AI 変換をオンにする",
    .later: "あとで",
    .done: "完了",
    .checking: "モデルを確認中…",
    .downloading: "ダウンロード中… %1$@ / %2$@",
    .installing: "インストール中…",
    .enabled: "AI 変換をオンにしました。",
    .failed: "モデルをインストールできませんでした: %@",
    .settingsHint: "この設定は [ProductName] の設定からいつでも変更できます。",
    .openSettings: "設定を開く…",
  ]

  public static func text(_ key: Key, language: GUILanguage = .current) -> String {
    let table = language == .japanese ? japanese : english
    return GUIUtil.replaceString(table[key] ?? english[key] ?? "")
  }
}

/// Whether the welcome window was shown (a marker file in the user profile).
public enum GenmaiWelcome {
  public static let markerName = "welcome_shown"

  public static func markerURL(profile: String = SystemUtil.getUserProfileDirectory()) -> URL {
    URL(filePath: profile, directoryHint: .isDirectory).appending(path: markerName)
  }

  public static func wasShown(profile: String = SystemUtil.getUserProfileDirectory()) -> Bool {
    FileManager.default.fileExists(atPath: markerURL(profile: profile).path)
  }

  public static func markShown(profile: String = SystemUtil.getUserProfileDirectory()) {
    try? FileManager.default.createDirectory(atPath: profile, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: markerURL(profile: profile).path, contents: Data())
  }
}

@MainActor
@Observable
public final class WelcomeModel {
  public enum AIState: Equatable, Sendable {
    case off
    case checking
    case downloading(received: Int64, total: Int64)
    case installing
    case enabled
    case failed(String)

    var isBusy: Bool {
      switch self {
      case .checking, .downloading, .installing: true
      case .off, .enabled, .failed: false
      }
    }
  }

  public private(set) var aiState = AIState.off

  /// Looks up the newest model release (replaced by tests).
  var releaseFetcher: @Sendable () async throws -> GenmaiModelRelease = { try await GenmaiModelRelease.latest() }
  /// Installs a release (replaced by tests).
  var installer:
    @Sendable (GenmaiModelRelease, AIModelVariant, URL, @escaping @Sendable (AIModelInstaller.Phase) -> Void)
      async throws
      -> Void = { release, variant, directory, progress in
        try await AIModelInstaller.install(release, variant: variant, to: directory, progress: progress)
      }

  private let client: any GenmaiClientProtocol
  private let settingsURL: URL
  private var task: Task<Void, Never>?

  public init(client: any GenmaiClientProtocol, settingsURL: URL = AIConversionSettings.fileURL) {
    self.client = client
    self.settingsURL = settingsURL
    if AIConversionSettings.load(from: settingsURL).enabled
      && AIModelStatus.check(AIConversionSettings.load(from: settingsURL).resolvedModelDirectory).isFound
    {
      aiState = .enabled
    }
  }

  /// The download size of the default model, shown before it is known.
  static let approximateDownload: Int64 = 340_000_000

  /// Installs the newest model (unless the installed one is current) and turns AI conversion on.
  public func enableAI() {
    guard task == nil, !aiState.isBusy, aiState != .enabled else { return }
    aiState = .checking
    let settingsURL = settingsURL
    var settings = AIConversionSettings.load(from: settingsURL)
    let directory = settings.resolvedModelDirectory
    let variant = settings.modelVariant
    let fetcher = releaseFetcher
    let installer = installer
    // Progress arrives for every network chunk: forward it only when the shown permille changes.
    let lastShown = Mutex<Int64>(-1)
    let report: @Sendable (AIModelInstaller.Phase) -> Void = { [weak self] phase in
      let next: AIState
      let key: Int64
      switch phase {
      case .downloading(let received, let total):
        next = .downloading(received: received, total: total)
        key = received * 1000 / max(total, 1)
      case .verifying, .installing:
        next = .installing
        key = 1001
      }
      guard
        lastShown.withLock({ last in
          defer { last = key }
          return last != key
        })
      else { return }
      Task { @MainActor [weak self] in
        if self?.aiState.isBusy == true { self?.aiState = next }
      }
    }
    task = Task { [weak self] in
      do {
        let release = try await fetcher()
        if AIModelStatus.check(directory).needsInstall(release, variant: variant) {
          try await installer(release, variant, directory, report)
        }
        settings.enabled = true
        try settings.save(to: settingsURL)
        _ = self?.client.reload()
        self?.aiState = .enabled
      } catch is CancellationError {
        self?.aiState = .off
      } catch {
        self?.aiState = .failed("\(error)")
      }
      self?.task = nil
    }
  }

  public func cancel() {
    task?.cancel()
  }
}

public struct WelcomeView: View {
  @State private var model: WelcomeModel
  let openSettings: @MainActor () -> Void
  @Environment(\.closeDialog) private var closeDialog

  public init(client: any GenmaiClientProtocol, openSettings: @escaping @MainActor () -> Void = {}) {
    _model = State(initialValue: WelcomeModel(client: client))
    self.openSettings = openSettings
  }

  init(model: WelcomeModel) {
    _model = State(initialValue: model)
    openSettings = {}
  }

  public var body: some View {
    VStack(spacing: 0) {
      WelcomeHeader()
        .padding(.top, 28)
        .padding(.bottom, 20)
      VStack(spacing: 12) {
        WelcomeCard(symbol: "keyboard", tint: .blue, title: WelcomeStrings.text(.switchTitle)) {
          Text(verbatim: WelcomeStrings.text(.switchDetail))
        }
        WelcomeCard(symbol: "sparkles", tint: .purple, title: WelcomeStrings.text(.aiTitle)) {
          WelcomeAISection(model: model)
        }
      }
      Text(verbatim: WelcomeStrings.text(.settingsHint))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 14)
      HStack {
        Button(WelcomeStrings.text(.openSettings)) {
          openSettings()
          closeDialog()
        }
        Spacer()
        if model.aiState == .enabled {
          Button(WelcomeStrings.text(.done)) { closeDialog() }
            .keyboardShortcut(.defaultAction)
        } else {
          Button(WelcomeStrings.text(.later)) {
            model.cancel()
            closeDialog()
          }
          .keyboardShortcut(.cancelAction)
          Button(WelcomeStrings.text(.enableAI)) { model.enableAI() }
            .keyboardShortcut(.defaultAction)
            .disabled(model.aiState.isBusy)
        }
      }
      .padding(.top, 18)
    }
    .padding(.horizontal, 28)
    .padding(.bottom, 20)
    .frame(width: 500)
  }
}

private struct WelcomeHeader: View {
  var body: some View {
    VStack(spacing: 6) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .frame(width: 96, height: 96)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .accessibilityHidden(true)
      Text(verbatim: WelcomeStrings.text(.title))
        .font(.system(size: 24, weight: .bold))
        .accessibilityAddTraits(.isHeader)
      Text(verbatim: WelcomeStrings.text(.subtitle))
        .foregroundStyle(.secondary)
    }
  }
}

/// A rounded box with an icon, a title and content.
private struct WelcomeCard<Content: View>: View {
  let symbol: String
  let tint: Color
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 30, height: 30)
        .background(tint.gradient, in: .rect(cornerRadius: 8))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: title)
          .font(.headline)
        content
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(14)
    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
  }
}

private struct WelcomeAISection: View {
  let model: WelcomeModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        verbatim: String(
          format: WelcomeStrings.text(.aiDetail),
          WelcomeModel.approximateDownload.formatted(.byteCount(style: .file))))
      switch model.aiState {
      case .off:
        EmptyView()
      case .checking:
        WelcomeProgressRow(text: WelcomeStrings.text(.checking), fraction: nil)
      case .downloading(let received, let total):
        WelcomeProgressRow(
          text: String(
            format: WelcomeStrings.text(.downloading), received.formatted(.byteCount(style: .file)),
            total.formatted(.byteCount(style: .file))),
          fraction: Double(received) / Double(max(total, 1)))
      case .installing:
        WelcomeProgressRow(text: WelcomeStrings.text(.installing), fraction: nil)
      case .enabled:
        Label {
          Text(verbatim: WelcomeStrings.text(.enabled))
        } icon: {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
        .foregroundStyle(.primary)
      case .failed(let message):
        Text(verbatim: String(format: WelcomeStrings.text(.failed), message))
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }
    }
  }
}

private struct WelcomeProgressRow: View {
  let text: String
  let fraction: Double?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: text)
        .monospacedDigit()
      if let fraction {
        ProgressView(value: fraction)
      } else {
        ProgressView()
          .progressViewStyle(.linear)
      }
    }
  }
}
