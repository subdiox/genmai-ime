// Test helpers for the data_manager tests (Swift only). Namespaced to avoid
// clashing with helpers of other GenmaiCoreTests folders.

import Foundation
import GenmaiBase

@testable import GenmaiCore

enum DataManagerTestSupport {
  /// Converts a C-like literal with `\xNN` escapes (written as a raw string)
  /// to bytes.
  static func cBytes(_ s: String) -> [UInt8] {
    var result: [UInt8] = []
    let u = Array(s.utf8)
    var i = 0
    while i < u.count {
      if u[i] == 0x5C, i + 3 < u.count, u[i + 1] == 0x78 {
        let hex = String(decoding: u[(i + 2)..<(i + 4)], as: UTF8.self)
        result.append(UInt8(hex, radix: 16)!)
        i += 4
      } else {
        result.append(u[i])
        i += 1
      }
    }
    return result
  }

  /// Repository root, located from this source file.
  static let repositoryRoot: String = {
    var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
    // Tests/GenmaiCoreTests/DataManager/<file>.swift -> repository root
    for _ in 0..<4 {
      url.deleteLastPathComponent()
    }
    return url.path
  }()

  /// Absolute path of a file in the repository.
  static func path(_ relative: String) -> String {
    FileUtil.joinPath(repositoryRoot, relative)
  }

  /// Absolute path of a file in Vendor/mozc/src (C++ GetSourceFileOrDie).
  static func sourcePath(_ components: String...) -> String {
    FileUtil.joinPath(repositoryRoot, "Vendor/mozc/src/" + components.joined(separator: "/"))
  }

  static var ossDataPath: String { OssDataManager.defaultDataPath }

  static var hasOssData: Bool { FileManager.default.fileExists(atPath: ossDataPath) }

  static var hasMockData: Bool { MockDataManager.defaultDataPath != nil }
}
