// Port of mozc/src/dictionary/suffix_dictionary.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::dictionary::SuffixDictionary`: a special dictionary which handles
/// Japanese bunsetsu suffixes.
///
/// Japanese bunsetsu consists of two parts.
/// Content words: ("自立語") and Functional words ("付属語")
/// Japanese Bunsets = (Content word){1,1}(Functional words){1,}
///
/// Suffix dictionary contains sequences of functional words
/// frequently appear on the web.
/// When user inputs a content word, we can predict an appropriate
/// functional word with this dictionary.
///
/// Data: `DataManager.getSuffixDictionaryData()`.
public final class SuffixDictionary: DictionaryInterface, Sendable {
  // Immutable views of the data set.

  // struct TokenArrayData { uint32_t lid, rid, cost; } (12 bytes, packed)
  private static let kTokenArrayDataSize = 12

  private let keyArray: SerializedStringArray
  private let valueArray: SerializedStringArray
  private let tokenArray: DataView

  public init(_ keyArrayData: DataView, _ valueArrayData: DataView, _ tokenArrayData: DataView) {
    tokenArray = tokenArrayData
    var keyArray = SerializedStringArray()
    keyArray.set(keyArrayData)
    self.keyArray = keyArray
    var valueArray = SerializedStringArray()
    valueArray.set(valueArrayData)
    self.valueArray = valueArray
    assert(keyArray.count == tokenArraySize)
    assert(valueArray.count == tokenArraySize)
  }

  private var tokenArraySize: Int { tokenArray.count / Self.kTokenArrayDataSize }

  public func hasKey(_ key: String) -> Bool {
    // SuffixDictionary::HasKey() is never called and unnecessary to
    // implement. To avoid accidental calls of this method, the method simply dies
    // so that we can immediately notice this unimplemented method during
    // development.
    fatalError("bool SuffixDictionary::HasKey() is not implemented")
  }

  public func hasValue(_ value: String) -> Bool {
    // SuffixDictionary::HasValue() is never called and unnecessary to
    // implement. To avoid accidental calls of this method, the method simply dies
    // so that we can immediately notice this unimplemented method during
    // development.
    fatalError("bool SuffixDictionary::HasValue() is not implemented")
  }

  // Kana modifier insensitive lookup is not supported.
  public func lookupPredictive(_ key: String, callback: any DictionaryCallback) {
    let keyBytes = Array(key.utf8)
    // compare by the prefix.
    func cmp(_ i: Int) -> Int {
      keyArray.comparePrefix(at: i, bytes: keyBytes)
    }
    // std::equal_range.
    var begin = 0
    var n = keyArray.count
    while n > 0 {
      let half = n / 2
      if cmp(begin + half) < 0 {
        begin += half + 1
        n -= half + 1
      } else {
        n = half
      }
    }
    var end = begin
    n = keyArray.count - begin
    while n > 0 {
      let half = n / 2
      if !(cmp(end + half) > 0) {
        end += half + 1
        n -= half + 1
      } else {
        n = half
      }
    }

    var index = begin
    while index < end {
      defer { index += 1 }
      let entryKey = keyArray[index]
      switch callback.onKey(entryKey) {
      case .traverseDone:
        return
      case .traverseNextKey:
        continue
      case .traverseCull:
        fatalError("Culling is not supported.")
      default:
        break
      }
      if callback.onActualKey(entryKey, entryKey, 0) == .traverseDone {
        return
      }
      // Invalid index.
      if index >= tokenArraySize {
        break
      }
      var token = Token()
      token.attributes = Token.Attribute.suffixDictionary
      token.key = entryKey
      let value = valueArray[index]
      if value.isEmpty {
        token.value = token.key
      } else {
        token.value = value
      }
      let o = index * Self.kTokenArrayDataSize
      token.lid = UInt16(truncatingIfNeeded: tokenArray.load(fromByteOffset: o, as: UInt32.self))
      token.rid = UInt16(truncatingIfNeeded: tokenArray.load(fromByteOffset: o + 4, as: UInt32.self))
      token.cost = Int(Int32(bitPattern: tokenArray.load(fromByteOffset: o + 8, as: UInt32.self)))
      if callback.onToken(entryKey, entryKey, token) != .traverseContinue {
        break
      }
    }
  }
}
