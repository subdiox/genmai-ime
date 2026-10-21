// Port of mozc/src/data_manager/oss/gen_oss_segmenter_bitarray_main.cc and
// mozc/src/data_manager/testing/gen_mock_segmenter_bitarray_main.cc
// (3.35.6354).
//
// Both mains are identical except for the included segmenter_inl.inc, which
// GenSegmenterCode evaluates from the data set's id.def / special_pos.def /
// segmenter.def.

import Foundation
import GenmaiBase
import GenmaiCore

public enum GenSegmenterBitarrayMain {
  public static func sections(_ ctx: DataGenContext) throws -> [String: [UInt8]] {
    let s = ctx.sources
    let code = try GenSegmenterCode(idFile: s.idDef, specialPosFile: s.specialPos, segmenterDef: s.segmenterDef)
    let table = code.isBoundaryTable()
    let rsize = code.rsize
    let r = try SegmenterBitarrayGenerator.generateBitarray(code.lsize, code.rsize) { rid, lid in
      table[rid * rsize + lid]
    }
    return [
      "segmenter_sizeinfo": r.sizeInfo,
      "segmenter_ltable": r.ltable,
      "segmenter_rtable": r.rtable,
      "segmenter_bitarray": r.bitarray,
    ]
  }
}
