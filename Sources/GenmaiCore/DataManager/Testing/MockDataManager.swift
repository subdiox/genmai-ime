// Port of mozc/src/data_manager/testing/mock_data_manager.{h,cc} (3.35.6354).
//
// The C++ class embeds the mock data set (mock_mozc_data.inc) built from
// data/test/dictionary. The Swift port memory-maps `mock_genmai.data` instead:
// `$GENMAI_MOCK_DATA_FILE`, else `Data/mock_genmai.data` at the repository root,
// else the Bazel output `Vendor/mozc/src/bazel-bin/data_manager/testing/
// mock_genmai.data` (target //data_manager/testing:mozc_dataset_for_testing).
// The gmock `MOCK_METHOD(GetDataVersion)` becomes an optional override.

import Foundation
import GenmaiBase

public final class MockDataManager: DataManager, @unchecked Sendable {
  /// The length of the mock magic number "MOCK"
  /// (MOZC_DATASET_MAGIC_NUMBER_LENGTH in data_manager/testing/BUILD.bazel).
  public static let kMagicNumberLength = 4

  public static let dataFileEnvironmentVariable = "GENMAI_MOCK_DATA_FILE"

  private static let repositoryRoot: URL = {
    var url = URL(fileURLWithPath: #filePath)
    // Sources/GenmaiCore/DataManager/Testing/MockDataManager.swift -> repository root
    for _ in 0..<5 {
      url.deleteLastPathComponent()
    }
    return url
  }()

  /// Candidate locations of the mock data set, in lookup order.
  public static var candidateDataPaths: [String] {
    var paths: [String] = []
    if let path = ProcessInfo.processInfo.environment[dataFileEnvironmentVariable], !path.isEmpty {
      paths.append(path)
    }
    paths.append(repositoryRoot.appendingPathComponent("Data/mock_genmai.data").path)
    paths.append(
      repositoryRoot.appendingPathComponent(
        "Vendor/mozc/src/bazel-bin/data_manager/testing/mock_mozc.data"
      ).path)
    return paths
  }

  /// The first existing candidate path, or nil when the mock data set has not
  /// been built.
  public static var defaultDataPath: String? {
    candidateDataPaths.first { FileManager.default.fileExists(atPath: $0) }
  }

  private let dataVersionOverride: String?

  /// Loads the mock data set. `dataVersion` replaces GetDataVersion()'s
  /// result (the C++ test mocks it with gmock).
  public init(dataVersion: String? = nil) throws {
    guard let path = MockDataManager.defaultDataPath else {
      throw StatusError.notFound(
        "mock_genmai.data not found in \(MockDataManager.candidateDataPaths)")
    }
    dataVersionOverride = dataVersion
    super.init()
    try initFromFile(path, magicLength: MockDataManager.kMagicNumberLength)
  }

  public override func getDataVersion() -> String {
    dataVersionOverride ?? super.getDataVersion()
  }
}
