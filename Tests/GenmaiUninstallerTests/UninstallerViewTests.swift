// Layout of the uninstaller window in every phase and language. With GENMAI_UNINSTALLER_SNAPSHOTS=<directory>
// the window is also written there as PNGs (light and dark), to look at the phases without uninstalling.

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import GenmaiUninstaller

@MainActor
@Suite struct UninstallerViewTests {
  /// Puts the controller into `phase` by running a deletion that ends there.
  static func controller(_ phase: UninstallerController.Phase, language: UninstallerLanguage) async throws
    -> UninstallerController
  {
    let result: PrivilegedCommandResult =
      switch phase {
      case .failed(.authorization): .authorizationFailed
      case .failed(.removal): .failed("rm")
      default: .success
      }
    let icon = NSImage(contentsOf: Self.repositoryRoot.appending(path: "Tools/assets/genmai.icns")) ?? NSImage()
    let controller = UninstallerController(
      uninstaller: Uninstaller(layout: try FakeInstall().layout, runner: FixedCommandRunner(result)),
      language: language, icon: icon, terminate: {})
    switch phase {
    case .confirm:
      break
    case .removing:
      // uninstall() pauses in .removing before it runs the deletion; the task finishes after the snapshot.
      Task { await controller.uninstall() }
      while controller.phase != .removing {
        await Task.yield()
      }
    default:
      await controller.uninstall()
    }
    #expect(controller.phase == phase)
    return controller
  }

  static let repositoryRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

  static func name(_ phase: UninstallerController.Phase) -> String {
    switch phase {
    case .confirm: "confirm"
    case .removing: "removing"
    case .succeeded: "succeeded"
    case .failed(.authorization): "authorization-failed"
    case .failed(.removal): "removal-failed"
    }
  }

  static let phases: [UninstallerController.Phase] = [
    .confirm, .removing, .succeeded, .failed(.authorization), .failed(.removal),
  ]

  @Test(arguments: [UninstallerLanguage.english, .japanese])
  func windowFitsEveryPhase(language: UninstallerLanguage) async throws {
    let directory = ProcessInfo.processInfo.environment["GENMAI_UNINSTALLER_SNAPSHOTS"].map { URL(filePath: $0) }
    for phase in Self.phases {
      let controller = try await Self.controller(phase, language: language)
      let host = NSHostingView(rootView: UninstallerView(controller: controller))
      let size = host.fittingSize
      #expect(size.width == 480)
      #expect(size.height > 150 && size.height < 420, "\(phase) \(language): \(size)")
      guard let directory else {
        continue
      }
      for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let snapshot = NSHostingView(
          rootView: UninstallerView(controller: controller).background(Color(nsColor: .windowBackgroundColor)))
        snapshot.appearance = NSAppearance(named: appearance)
        snapshot.frame = NSRect(origin: .zero, size: size)
        snapshot.layoutSubtreeIfNeeded()
        let rep = try #require(snapshot.bitmapImageRepForCachingDisplay(in: snapshot.bounds))
        snapshot.cacheDisplay(in: snapshot.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: directory.appending(path: "uninstaller-\(language)-\(Self.name(phase))-\(name).png"))
      }
    }
  }
}
