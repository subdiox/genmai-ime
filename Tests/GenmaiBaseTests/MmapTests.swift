// Port of mozc/src/base/mmap_test.cc (3.35.6354).

import Foundation
import Testing

@testable import GenmaiBase

private func getRandomContents(_ size: Int) -> [UInt8] {
  var r = Random()
  return r.byteString(size)
}

@Suite struct MmapTest {
  @Test func defaultCtor() {
    let mmap = Mmap()  // Nothing is mapped.
    #expect(mmap.isEmpty)
  }

  // MoveCtor / MoveAssign: Swift's Mmap is a reference type; moving is
  // sharing the reference. The test checks that the contents stay valid.
  @Test func moveCtor() throws {
    let kTestContents = Array("mmap test".utf8)
    let tempFile = try TempDirectory.default().createTempFile()
    defer { withExtendedLifetime(tempFile) {} }
    try FileUtil.setContents(tempFile.path, kTestContents)
    var mmap: Mmap? = try Mmap.map(tempFile.path)
    let moved = try #require(mmap)
    #expect(Array(moved.data) == kTestContents)
    mmap = nil
    #expect(mmap == nil)
    #expect(Array(moved.data) == kTestContents)
  }

  @Test func moveAssign() throws {
    let kTestContents = [Array("mmap test 1".utf8), Array("mmap test 2".utf8)]
    let tempFiles = [
      try TempDirectory.default().createTempFile(),
      try TempDirectory.default().createTempFile(),
    ]
    defer { withExtendedLifetime(tempFiles) {} }
    for i in 0..<2 {
      try FileUtil.setContents(tempFiles[i].path, kTestContents[i])
    }
    var mmap1 = try Mmap.map(tempFiles[0].path)
    #expect(Array(mmap1.data) == kTestContents[0])
    let mmap2 = try Mmap.map(tempFiles[1].path)
    #expect(Array(mmap2.data) == kTestContents[1])
    mmap1 = mmap2
    #expect(Array(mmap1.data) == kTestContents[1])
  }

  @Test func failsIfFileDoesNotExist() {
    #expect(throws: (any Error).self) { try Mmap.map("") }
  }

  @Test func failsIfOffsetExceedsFileSize() throws {
    let kFileSize = 128
    let tempFile = try TempDirectory.default().createTempFile()
    defer { withExtendedLifetime(tempFile) {} }
    try FileUtil.setContents(tempFile.path, String(repeating: "a", count: kFileSize))
    #expect(throws: (any Error).self) {
      try Mmap.map(tempFile.path, offset: 512, size: nil, .readOnly)
    }
  }

  @Test func failsIfMapSizeIsZero() throws {
    let kFileSize = 128
    let tempFile = try TempDirectory.default().createTempFile()
    defer { withExtendedLifetime(tempFile) {} }
    try FileUtil.setContents(tempFile.path, String(repeating: "a", count: kFileSize))
    #expect(throws: (any Error).self) { try Mmap.map(tempFile.path, offset: 0, size: 0, .readOnly) }
    #expect(throws: (any Error).self) {
      try Mmap.map(tempFile.path, offset: 100, size: 0, .readOnly)
    }
    // If offset is at the end of file, the resulting size is zero.
    #expect(throws: (any Error).self) {
      try Mmap.map(tempFile.path, offset: kFileSize, size: nil, .readOnly)
    }
  }

  // The C++ test mlocks a malloc()ed block; this one mlocks a mapped file.
  @Test func maybeMLockTest() throws {
    let kDataLen = 32
    let tempFile = try TempDirectory.default().createTempFile()
    defer { withExtendedLifetime(tempFile) {} }
    try FileUtil.setContents(tempFile.path, String(repeating: "a", count: kDataLen))
    let mmap = try Mmap.map(tempFile.path)
    if Mmap.isMLockSupported() {
      #expect(mmap.maybeMLock() == 0)
      #expect(mmap.maybeMUnlock() == 0)
    } else {
      #expect(mmap.maybeMLock() == -1)
      #expect(mmap.maybeMUnlock() == -1)
    }
  }

  // MmapEntireFileTest
  @Test(arguments: [1, 8, 1024, 4096, 7777, 8192])
  func entireFileRead(_ filesize: Int) throws {
    // Create a file with random contents.
    let data = getRandomContents(filesize)
    let tempFile = try TempDirectory.default().createTempFile()
    defer { withExtendedLifetime(tempFile) {} }
    try FileUtil.setContents(tempFile.path, data)

    // Mmap the file and check its contents.
    let mmap = try Mmap.map(tempFile.path, .readOnly)
    #expect(Array(mmap.data) == data)
  }

  @Test(arguments: [1, 8, 1024, 4096, 7777, 8192])
  func entireFileWrite(_ filesize: Int) throws {
    // Create a file with full of a's.
    let tempFile = try TempDirectory.default().createTempFile()
    defer { withExtendedLifetime(tempFile) {} }
    try FileUtil.setContents(tempFile.path, String(repeating: "a", count: filesize))

    // Mmap the file and writes random contents.
    let data = getRandomContents(filesize)
    do {
      let mmap = try Mmap.map(tempFile.path, .readWrite)
      #expect(mmap.size == data.count)
      mmap.write(data, at: 0)
    }

    // Read the file and check its contents.
    #expect(try FileUtil.getContentBytes(tempFile.path) == data)
  }

  // File size, offset, and length to mmap.
  static let partialParams: [(Int, Int, Int?)] = [
    (1, 0, 1),
    (1024, 0, 1024),
    (1024, 0, 321),
    (1024, 1000, nil),
    (1024, 1000, 24),
    (1024, 321, 567),
    (4096, 0, 4096),
    (4096, 3000, 1096),
    (4096, 500, nil),
    (4096, 500, 3000),
    (7777, 0, 7777),
    (7777, 2500, 5000),
    (7777, 5000, nil),
    (7777, 5000, 2000),
    (8192, 0, 8192),
    (8192, 1000, 3000),
    (8192, 1000, 7000),
    (8192, 5000, nil),
    (8192, 5000, 2000),
    (8192, 5000, 3192),
  ]

  // MmapPartialFileTest.Read
  @Test(arguments: partialParams)
  func partialFileRead(_ params: (Int, Int, Int?)) throws {
    let (filesize, offset, size) = params
    let data = getRandomContents(filesize)
    let tempFile = try TempDirectory.default().createTempFile()
    defer { withExtendedLifetime(tempFile) {} }
    try FileUtil.setContents(tempFile.path, data)

    let expected = Array(data[offset..<offset + (size ?? (filesize - offset))])
    let mmap = try Mmap.map(tempFile.path, offset: offset, size: size, .readOnly)
    #expect(Array(mmap.data) == expected)

    // Test "move" operations for partial mmap (reference sharing).
    let mmap2 = mmap
    #expect(Array(mmap2.data) == expected)
    var mmap3 = Mmap()
    #expect(mmap3.isEmpty)
    mmap3 = mmap2
    #expect(Array(mmap3.data) == expected)
  }

  // MmapPartialFileTest.Write
  @Test(arguments: partialParams)
  func partialFileWrite(_ params: (Int, Int, Int?)) throws {
    let (filesize, offset, size) = params
    let mapSize = size ?? (filesize - offset)
    let tempFile = try TempDirectory.default().createTempFile()
    defer { withExtendedLifetime(tempFile) {} }
    try FileUtil.setContents(tempFile.path, String(repeating: "a", count: filesize))

    let data = getRandomContents(mapSize)
    do {
      let mmap = try Mmap.map(tempFile.path, offset: offset, size: mapSize, .readWrite)
      #expect(mmap.size == data.count)
      mmap.write(data, at: 0)
    }

    let contents = try FileUtil.getContentBytes(tempFile.path)
    let a = UInt8(ascii: "a")
    #expect(Array(contents[0..<offset]) == [UInt8](repeating: a, count: offset))
    #expect(Array(contents[offset..<offset + mapSize]) == data)
    #expect(
      Array(contents[(offset + mapSize)...])
        == [UInt8](repeating: a, count: filesize - offset - mapSize))
  }
}
