// Port of mozc/src/data_manager/oss/oss_data_manager.{h,cc} (3.35.6354).
//
// The C++ class embeds the OSS data set (mozc_data.inc, 19 MB) into the
// executable. The Swift port memory-maps the data set file instead:
// `$GENMAI_DATA_FILE` if set, else `genmai.data` in the resources of the running
// app bundle (Mozc.app/Contents/Resources, installed by
// Tools/make_ime_bundle.sh; the Genmai app (Genmai.app), which lives in that directory, finds
// it next to itself), else `Data/genmai.data` at the repository root (created by
// Tools/build_oracle.sh) for development builds and tests.

import Foundation
import GenmaiBase

/// This is a simple wrapper of DataManager that uses the OSS data set. (The C++
/// subclass is a factory here: `DataManager` is a final class.)
public enum OssDataManager {
  /// The length of the OSS magic number "\xEFMOZC\r\n"
  /// (MOZC_DATASET_MAGIC_NUMBER_LENGTH in data_manager/oss/BUILD.bazel).
  public static let kMagicNumberLength = 7

  /// The environment variable that overrides `defaultDataPath`.
  public static let dataFileEnvironmentVariable = "GENMAI_DATA_FILE"

  /// `Data/genmai.data` at the repository root (located from this source file).
  public static let repositoryDataPath: String = {
    var url = URL(fileURLWithPath: #filePath)
    // Sources/GenmaiCore/DataManager/Oss/OssDataManager.swift -> repository root
    for _ in 0..<5 {
      url.deleteLastPathComponent()
    }
    return url.appendingPathComponent("Data/genmai.data").path
  }()

  /// The file name of the data set in an app bundle's resources.
  public static let bundleResourceName = "genmai.data"

  /// `genmai.data` of the running app bundle, if any: Contents/Resources of the
  /// main bundle, or the directory containing the main bundle (a helper app
  /// nested in Genmai.app/Contents/Resources), or the iOS app containing the
  /// main bundle (the keyboard extension, Genmai.app/PlugIns/*.appex).
  public static var bundleDataPath: String? {
    let bundle = Bundle.main
    var candidates: [URL] = []
    if let resources = bundle.resourceURL {
      candidates.append(resources.appendingPathComponent(bundleResourceName))
    }
    if bundle.bundleURL.pathExtension == "app" {
      candidates.append(
        bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleResourceName))
    }
    if bundle.bundleURL.pathExtension == "appex" {
      candidates.append(
        bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
          .appendingPathComponent(bundleResourceName))
    }
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
  }

  /// The data set used by `create()`: `$GENMAI_DATA_FILE` if set, otherwise
  /// `bundleDataPath`, otherwise `repositoryDataPath`.
  public static var defaultDataPath: String {
    if let path = ProcessInfo.processInfo.environment[dataFileEnvironmentVariable], !path.isEmpty {
      return path
    }
    if let path = bundleDataPath {
      return path
    }
    return repositoryDataPath
  }

  /// Loads the OSS data set from `path` (default: `defaultDataPath`). Throws
  /// (instead of the C++ CHECK failure) when the file is missing or broken.
  /// As in C++, only the length of the magic number is checked.
  public static func create(path: String = OssDataManager.defaultDataPath) throws -> DataManager {
    let dataManager = DataManager()
    try dataManager.initFromFile(path, magicLength: OssDataManager.kMagicNumberLength)
    return dataManager
  }
}
