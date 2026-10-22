// Tests of the app update lookup and settings (not part of Mozc).

import Foundation
import Testing

@testable import GenmaiClient

@Suite struct GenmaiUpdateTests {
  /// A trimmed `/repos/<repo>/releases` answer: a pre-release, a draft, a release without a package, 0.10.0 and 0.9.0.
  static let releasesJSON = """
    [
      {"tag_name": "v0.11.0-beta", "draft": false, "prerelease": true, "html_url": "https://github.com/x/y/releases/b",
       "body": "", "assets": [{"name": "Genmai-0.11.0.pkg", "size": 1, "browser_download_url": "https://x/b.pkg"}]},
      {"tag_name": "v0.12.0", "draft": true, "prerelease": false, "html_url": "https://github.com/x/y/releases/d",
       "body": "", "assets": [{"name": "Genmai-0.12.0.pkg", "size": 1, "browser_download_url": "https://x/d.pkg"}]},
      {"tag_name": "v0.11.0", "draft": false, "prerelease": false, "html_url": "https://github.com/x/y/releases/n",
       "body": "", "assets": [{"name": "notes.txt", "size": 1, "browser_download_url": "https://x/n.txt"}]},
      {"tag_name": "v0.9.0", "draft": false, "prerelease": false, "html_url": "https://github.com/x/y/releases/9",
       "body": "old", "assets": [{"name": "Genmai-0.9.0.pkg", "size": 5, "browser_download_url": "https://x/9.pkg"}]},
      {"tag_name": "v0.10.0", "draft": false, "prerelease": false, "html_url": "https://github.com/x/y/releases/10",
       "body": "* new", "assets": [
         {"name": "Genmai-0.10.0.pkg", "size": 1234, "browser_download_url": "https://x/10.pkg",
          "digest": "sha256:ABCDEF"}]}
    ]
    """

  @Test func releases() throws {
    let releases = try GenmaiAppRelease.releases(Data(Self.releasesJSON.utf8))
    #expect(releases.map(\.version) == ["0.10.0", "0.9.0"])
    let newest = releases[0]
    #expect(newest.tag == "v0.10.0")
    #expect(newest.notes == "* new")
    #expect(newest.pageURL == URL(string: "https://github.com/x/y/releases/10"))
    #expect(
      newest.package
        == .init(name: "Genmai-0.10.0.pkg", url: URL(validLiteral: "https://x/10.pkg"), size: 1234, sha256: "abcdef"))
    #expect(releases[1].package.sha256 == nil)
    #expect(newest.isNewer(than: "0.9.9"))
    #expect(!newest.isNewer(than: "0.10.0"))
    #expect(throws: GenmaiUpdateError.self) { try GenmaiAppRelease.releases(Data("{}".utf8)) }
  }

  static func release(_ version: String) -> GenmaiAppRelease {
    GenmaiAppRelease(
      version: version, tag: "v\(version)", pageURL: URL(validLiteral: "https://example.com"), notes: "",
      package: .init(
        name: "Genmai-\(version).pkg", url: URL(validLiteral: "https://example.com/p.pkg"), size: 1, sha256: nil))
  }

  @Test func settings() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    var settings = GenmaiUpdateSettings()
    #expect(settings.isCheckDue(at: now))
    settings.lastCheck = now.addingTimeInterval(-3600)
    #expect(!settings.isCheckDue(at: now))
    settings.lastCheck = now.addingTimeInterval(-GenmaiUpdateSettings.checkInterval)
    #expect(settings.isCheckDue(at: now))
    settings.lastCheck = now.addingTimeInterval(3600)  // clock set back
    #expect(settings.isCheckDue(at: now))
    settings.automaticCheck = false
    #expect(!settings.isCheckDue(at: now))

    #expect(settings.shouldOffer(Self.release("0.2.0"), currentVersion: "0.1.0"))
    #expect(!settings.shouldOffer(Self.release("0.1.0"), currentVersion: "0.1.0"))
    settings.skippedVersion = "0.2.0"
    #expect(!settings.shouldOffer(Self.release("0.2.0"), currentVersion: "0.1.0"))
    #expect(settings.shouldOffer(Self.release("0.3.0"), currentVersion: "0.1.0"))
  }

  @Test func settingsFile() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "update-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: GenmaiUpdateSettings.fileName)
    #expect(GenmaiUpdateSettings.load(from: url) == GenmaiUpdateSettings())
    let checked = Date(timeIntervalSince1970: 1_700_000_000)
    try GenmaiUpdateSettings.update(at: url) {
      $0.automaticCheck = false
      $0.lastCheck = checked
    }
    #expect(GenmaiUpdateSettings.load(from: url) == GenmaiUpdateSettings(automaticCheck: false, lastCheck: checked))
    let json = try String(contentsOf: url, encoding: .utf8)
    #expect(json.contains("\"automatic_check\" : false"))
    #expect(json.contains("2023-11-14T22:13:20Z"))
    try Data("{\"skipped_version\": \"1.0.0\"}".utf8).write(to: url)
    #expect(GenmaiUpdateSettings.load(from: url) == GenmaiUpdateSettings(skippedVersion: "1.0.0"))
  }
}
