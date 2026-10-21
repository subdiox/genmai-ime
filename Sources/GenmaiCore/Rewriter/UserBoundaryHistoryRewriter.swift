// Port of mozc/src/rewriter/user_boundary_history_rewriter.{h,cc} (3.35.6354).
//
// Persisted learning data: `user://boundary.db`, an LruStorage file
// (value size 4, 5000 entries, seed 0x761fea81) keyed by the concatenated
// segment keys. Each value is the C++ `LengthArray`: eight 4-bit bit-fields
// packed as clang/gcc lay them out on little-endian targets, i.e. byte i holds
// length[2i] in its low nibble and length[2i+1] in its high nibble. Lengths
// are truncated to 4 bits on store, as in C++.
//
// Deviations from C++:
// - `LengthArray` is a value type packed / unpacked explicitly instead of
//   `reinterpret_cast`; the byte layout is the same.

import GenmaiBase
import GenmaiProtocol
import GenmaiStorage

private let kValueSize = 4
private let kLruSize = 5000
private let kSeedValue: UInt32 = 0x761fea81

private let kFileName = "user://boundary.db"

private struct LengthArray {
  // Packed 4-bit fields, byte compatible with the C++ bit-field struct.
  private var bytes: (UInt8, UInt8, UInt8, UInt8)

  init(_ array: [UInt8]) {
    func pack(_ lo: UInt8, _ hi: UInt8) -> UInt8 { (lo & 0x0F) | ((hi & 0x0F) << 4) }
    bytes = (
      pack(array[0], array[1]), pack(array[2], array[3]), pack(array[4], array[5]),
      pack(array[6], array[7])
    )
  }

  /// Reads the 4 stored bytes.
  init(raw: UnsafeRawBufferPointer) {
    bytes = (raw[0], raw[1], raw[2], raw[3])
  }

  var rawBytes: [UInt8] { [bytes.0, bytes.1, bytes.2, bytes.3] }

  func toUint8Array() -> [UInt8] {
    var result: [UInt8] = []
    result.reserveCapacity(8)
    for b in rawBytes {
      result.append(b & 0x0F)
      result.append(b >> 4)
    }
    return result
  }

  func equal(_ other: LengthArray) -> Bool {
    rawBytes == other.rawBytes
  }
}

private struct SegmentsKey {
  // If segments are {"これは", "Mozcの", "こーどです"},
  // whole_key_: "これはMozcのこーどです" (31 bytes in total)
  // byte_indexs_: {0, 9, 16, 31}
  // char_sizes_: {3, 5, 5}
  let wholeKey: String
  let byteIndexs: [Int]  // indexes in bytes (3 for "あ")
  let charSizes: [UInt8]  // sizes in chars (1 for "あ")

  static func create(_ segments: Segments) -> SegmentsKey? {
    var wholeKey = ""
    var byteIndexs: [Int] = []  // indexes in bytes (3 for "あ")
    var charSizes: [UInt8] = []  // sizes in chars (1 for "あ")

    var byteIndex = 0
    for segment in segments.conversionSegments {
      let key = segment.key
      wholeKey += key
      byteIndexs.append(byteIndex)
      byteIndex += key.utf8.count

      let keySize = segment.keyLen
      if keySize > 255 {  // too long segment
        return nil
      }
      charSizes.append(UInt8(keySize))
    }
    byteIndexs.append(byteIndex)
    return SegmentsKey(wholeKey: wholeKey, byteIndexs: byteIndexs, charSizes: charSizes)
  }

  // Returns the key of the segments at segment_index with segment_size.
  func getKey(_ segmentIndex: Int, _ segmentSize: Int) -> Substring {
    let startIndex = byteIndexs[segmentIndex]
    let endIndex = byteIndexs[segmentIndex + segmentSize]
    return wholeKey.byteSubstring(from: startIndex, length: endIndex - startIndex)
  }

  // Returns the length array of the segments at segment_index with
  // segment_size.
  func getLengthArray(_ segmentIndex: Int, _ segmentSize: Int) -> LengthArray {
    let size = min(segmentSize, 8)
    var lengthArray: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]
    for i in 0..<size {
      lengthArray[i] = charSizes[segmentIndex + i]
    }
    return LengthArray(lengthArray)
  }
}

public final class UserBoundaryHistoryRewriter: RewriterInterface {
  private let storage = LruStorage()

  public init() {
    reload()
  }

  public func checkResizeSegmentsRequest(_ request: ConversionRequest, _ segments: Segments)
    -> Rewriter.ResizeSegmentsRequest?
  {
    if segments.resized {
      return nil
    }

    if request.incognitoMode() {
      return nil
    }

    if request.config().historyLearningLevel == .noHistory {
      return nil
    }

    if !request.options().enableUserHistoryForConversion {
      return nil
    }

    if request.options().skipSlowRewriters {
      return nil
    }

    if Rewriter.disableLaegacyRewriterInMixedConversion(
      request, Rewriter.LegacyRewriterType.disableUserBoundaryHistory)
      || Rewriter.disableLegacyRewriter(
        request, Rewriter.LegacyRewriterType.disableUserBoundaryHistory)
    {
      return nil
    }

    let targetSegmentsSize = segments.conversionSegmentsSize

    // No effective segments found
    if targetSegmentsSize == 0 {
      return nil
    }

    guard let segmentsKey = SegmentsKey.create(segments) else {
      // too long segment
      return nil
    }

    var segIdx = 0
    while segIdx < targetSegmentsSize {
      let kMaxKeysSize = 5
      let keysSize = min(max(targetSegmentsSize - segIdx, 0), kMaxKeysSize)
      var segSize = keysSize
      while segSize != 0 {
        defer { segSize -= 1 }
        let key = segmentsKey.getKey(segIdx, segSize)
        guard let raw = storage.lookup(key) else {
          // If the key is not in the history, resize is not needed.
          // Continue to the next step with a smaller segment key.
          continue
        }
        let value = LengthArray(raw: raw)

        let lengthArray = segmentsKey.getLengthArray(segIdx, segSize)
        if value.equal(lengthArray) {
          // If the segments are already same as the history, resize is not
          // needed. Skip the checked segments.
          segIdx += segSize - 1  // -1 as the main loop will add +1.
          break
        }

        return Rewriter.ResizeSegmentsRequest(
          segmentIndex: segIdx, segmentSizes: value.toUint8Array())
      }
      segIdx += 1
    }

    return nil
  }

  public func rewrite(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    false
  }

  public func finish(_ request: ConversionRequest, _ segments: Segments) {
    if request.requestType() != .conversion {
      return
    }

    if request.incognitoMode() {
      return
    }

    if request.config().historyLearningLevel != .defaultHistory {
      return
    }

    if !request.options().enableUserHistoryForConversion {
      return
    }

    if segments.resized {
      _ = insert(request, segments)
    }
  }

  @discardableResult public func sync() -> Bool { true }

  @discardableResult public func reload() -> Bool {
    let filename = ConfigFileStream.getFileName(kFileName)
    if !storage.openOrCreate(filename, kValueSize, kLruSize, kSeedValue) {
      GenmaiLog.warning("cannot initialize UserBoundaryHistoryRewriter")
      _ = storage.clear()
      return false
    }

    let kFileSuffix = ".merge_pending"
    let mergePendingFile = filename + kFileSuffix

    // merge pending file does not always exist.
    do {
      try FileUtil.fileExists(mergePendingFile)
      _ = storage.merge(mergePendingFile)
      FileUtil.unlinkOrLogError(mergePendingFile)
    } catch let error as StatusError where error.code == .notFound {
      // Not found is expected.
    } catch {
      GenmaiLog.error("Cannot check if \(mergePendingFile) exists: \(error)")
    }

    return true
  }

  public func clear() {
    _ = storage.clear()
  }

  private func insert(_ request: ConversionRequest, _ segments: Segments) -> Bool {
    // Get the prefix of segments having FIXED_VALUE state.
    var targetSegmentsSize = 0
    for segment in segments.conversionSegments where segment.segmentType == .fixedValue {
      targetSegmentsSize += 1
    }

    // No effective segments found
    if targetSegmentsSize == 0 {
      return false
    }

    guard let segmentsKey = SegmentsKey.create(segments) else {
      // too long segment
      return false
    }

    for segIdx in 0..<targetSegmentsSize {
      let kMaxKeysSize = 5
      let keysSize = min(max(targetSegmentsSize - segIdx, 0), kMaxKeysSize)
      var segSize = keysSize
      while segSize != 0 {
        let key = segmentsKey.getKey(segIdx, segSize)
        let lengthArray = segmentsKey.getLengthArray(segIdx, segSize)
        _ = storage.insert(key, lengthArray.rawBytes)
        segSize -= 1
      }
    }

    return true
  }
}
