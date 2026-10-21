// Port of mozc/src/dictionary/file/dictionary_file.{h,cc} (3.35.6354).

import GenmaiBase

/// `mozc::dictionary::DictionaryFile`: a set of named sections in one image.
///
/// Section images returned by `getSection` are zero-copy views; they keep the
/// mapped file (or the opened image's owner) alive.
public final class DictionaryFile: @unchecked Sendable {
  // @unchecked Sendable: open*() must not race with readers; after opening the
  // object is immutable.
  private let fileCodec: DictionaryFileCodec
  private var mapping: Mmap?
  private var sections: [DictionaryFileSection] = []

  public init(_ fileCodec: DictionaryFileCodec) {
    self.fileCodec = fileCodec
  }

  /// Opens from a file (memory-mapped).
  public func openFromFile(_ file: String) throws {
    let mapping = try Mmap.map(file)
    self.mapping = mapping
    try openFromImage(DataView(mapping))
  }

  /// Opens from a memory block.
  public func openFromImage(_ image: DataView) throws {
    sections.removeAll()
    sections = try fileCodec.readSections(image)
  }

  /// Gets a data image of the section having |section_name|.
  /// Returns nil when not found.
  public func getSection(_ sectionName: some StringProtocol) -> DataView? {
    let name = fileCodec.getSectionName(sectionName)
    for section in sections where section.name == name {
      return section.image
    }
    return nil
  }
}
