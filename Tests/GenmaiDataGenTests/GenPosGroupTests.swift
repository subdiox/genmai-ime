// Tests of the POS / boundary / segmenter / connection generators against the
// Bazel intermediates (bazel-bin/data_manager/{oss,testing}/*.data).

import Foundation
import GenmaiBase
import GenmaiDataGen
import Testing

@Suite struct GenPosGroupTests {
  static func bazelBin(_ set: String, _ file: String) -> String? {
    let p = DataGenTestPaths.srcRoot + "/bazel-bin/data_manager/\(set)/\(file)"
    return FileManager.default.fileExists(atPath: p) ? p : nil
  }

  @Test(arguments: ["oss", "testing"])
  func posListMatchesBazel(_ set: String) throws {
    guard let ref = Self.bazelBin(set, "pos_list.data") else {
      print("skipped: bazel-bin/data_manager/\(set)/pos_list.data missing (run Tools/build_oracle.sh)")
      return
    }
    let root = DataGenTestPaths.srcRoot
    let sources: DataGenSources =
      set == "oss"
      ? .oss(srcRoot: root, auxDictionary: "", filteredDictionary: "", usageDict: nil)
      : .mock(srcRoot: root, usageDict: nil)
    let out = try GenUserPosData.sections(DataGenContext(sources: sources))
    let expected = try FileUtil.getContentBytes(ref)
    #expect(out["pos_list"] == expected)
  }

  @Test(arguments: ["oss", "testing"])
  func sectionsMatchBazel(_ set: String) throws {
    let root = DataGenTestPaths.srcRoot
    let sources: DataGenSources =
      set == "oss"
      ? .oss(srcRoot: root, auxDictionary: "", filteredDictionary: "", usageDict: nil)
      : .mock(srcRoot: root, usageDict: nil)
    let ctx = DataGenContext(sources: sources)
    let cases: [(DataGenerator, [(String, String)])] = [
      (.posMatcher, [("pos_matcher", "pos_matcher.data")]),
      (.userPos, [("user_pos_token", "user_pos_token_array.data"), ("user_pos_string", "user_pos_string_array.data")]),
      (.posIdMap, [("pos_id_map", "pos_id_map.data")]),
      (.posGroup, [("posg", "pos_group.data")]),
      (.boundary, [("bdry", "boundary.data")]),
      (
        .segmenter,
        [
          ("segmenter_sizeinfo", "segmenter_sizeinfo.data"), ("segmenter_ltable", "segmenter_ltable.data"),
          ("segmenter_rtable", "segmenter_rtable.data"), ("segmenter_bitarray", "segmenter_bitarray.data"),
        ]
      ),
      (.connection, [("conn", "connection.data")]),
    ]
    for (gen, files) in cases {
      let out = try gen.run(ctx)
      for (key, file) in files {
        guard let ref = Self.bazelBin(set, file) else {
          print("skipped: bazel-bin/data_manager/\(set)/\(file) missing")
          continue
        }
        let expected = try FileUtil.getContentBytes(ref)
        #expect(out[key] == expected, "\(set) \(key)")
      }
    }
  }
}
