// Tests for DictionaryToolTextLineIterator.swift (the file iterators of
// mozc/src/gui/dictionary_tool/dictionary_tool.cc, which has no C++ test).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

@Suite struct DictionaryToolTextLineIteratorTests {
  typealias UserDictionary = Genmai_UserDictionary_UserDictionary
  typealias Importer = UserDictionaryImporter

  private func lines(_ iter: any TextLineIteratorInterface) -> [String] {
    var result: [String] = []
    while let line = iter.next() {
      result.append(String(decoding: line, as: UTF8.self))
    }
    return result
  }

  private func write(_ bytes: [UInt8], _ name: String, in dir: TempDirectory) throws -> String {
    let path = FileUtil.joinPath(dir.path, name)
    try FileUtil.setContents(path, bytes)
    return path
  }

  @Test func multiByteUtf8() throws {
    let dir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(dir) {} }
    let path = try write(
      [0xEF, 0xBB, 0xBF] + Array("きょうと\t京都\t名詞\r\nおおさか\t大阪\t地名\rx".utf8), "utf8.txt", in: dir)
    #expect(Importer.guessFileEncodingType(path) == .utf8)
    let iter = try #require(Importer.createTextLineIterator(.encodingAutoDetect, path))
    #expect(iter is MultiByteTextLineIterator)
    #expect(iter.isAvailable)
    #expect(lines(iter) == ["きょうと\t京都\t名詞", "おおさか\t大阪\t地名", "x"])
    #expect(iter.isAvailable)  // eof
    iter.reset()
    var dic = UserDictionary()
    // "x" has fewer than 3 columns and is silently ignored.
    try Importer.importFromTextLineIterator(.imeAutoDetect, iter, &dic)
    #expect(dic.entries.map(\.value) == ["京都", "大阪"])
  }

  @Test func multiByteShiftJIS() throws {
    let dir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(dir) {} }
    // "とうきょう\t東京\t地名\n" in Shift_JIS.
    let sjis: [UInt8] =
      [0x82, 0xC6, 0x82, 0xA4, 0x82, 0xAB, 0x82, 0xE5, 0x82, 0xA4, 0x09, 0x93, 0x8C, 0x8B, 0x9E, 0x09]
      + [0x92, 0x6E, 0x96, 0xBC, 0x0A]
    let path = try write(sjis, "sjis.txt", in: dir)
    #expect(Importer.guessFileEncodingType(path) == .shiftJIS)
    let iter = try #require(Importer.createTextLineIterator(.encodingAutoDetect, path))
    var dic = UserDictionary()
    try Importer.importFromTextLineIterator(.google, iter, &dic)
    #expect(dic.entries.count == 1)
    #expect(dic.entries.first?.key == "とうきょう")
    #expect(dic.entries.first?.value == "東京")
    #expect(dic.entries.first?.pos == .placeName)
  }

  @Test func utf16() throws {
    let dir = makeTempDirectoryOrDie()
    defer { withExtendedLifetime(dir) {} }
    let text = "!Microsoft IME Dictionary Tool\r\nきょうと\t京都\t名詞\r\n\r\nすずき\t鈴木\t人名"
    var le: [UInt8] = [0xFF, 0xFE]
    var be: [UInt8] = [0xFE, 0xFF]
    for u in text.utf16 {
      le += [UInt8(u & 0xFF), UInt8(u >> 8)]
      be += [UInt8(u >> 8), UInt8(u & 0xFF)]
    }
    for (bytes, name) in [(le, "le.txt"), (be, "be.txt")] {
      let path = try write(bytes, name, in: dir)
      #expect(Importer.guessFileEncodingType(path) == .utf16)
      let iter = try #require(Importer.createTextLineIterator(.encodingAutoDetect, path))
      #expect(iter is UTF16TextLineIterator)
      // "\r\n" -> line, then the "\n" is skipped at the start of the next line.
      #expect(
        lines(iter) == ["!Microsoft IME Dictionary Tool", "きょうと\t京都\t名詞", "", "すずき\t鈴木\t人名"])
      iter.reset()
      var dic = UserDictionary()
      try Importer.importFromTextLineIterator(.msime, iter, &dic)
      #expect(dic.entries.map(\.value) == ["京都", "鈴木"])
    }
  }

  @Test func missingFile() {
    #expect(Importer.guessFileEncodingType("/nonexistent/file") == .numEncodings)
    let iter = Importer.createTextLineIterator(.encodingAutoDetect, "/nonexistent/file")
    #expect(iter is UTF16TextLineIterator)
    #expect(iter?.isAvailable == false)
    #expect(MultiByteTextLineIterator(.utf8, "/nonexistent/file").isAvailable == false)
  }
}
