// Port of mozc/src/dictionary/file/dictionary_file.{h,cc} (3.35.6354).

import GenmaiBase
import Synchronization

/// `mozc::dictionary::DictionaryFile`: a set of named sections in one image.
///
/// Section images returned by `getSection` are zero-copy views; they keep the
/// mapped file (or the opened image's owner) alive.
public final class DictionaryFile: Sendable {
  private let fileCodec: DictionaryFileCodec
  /// The sections of the opened image (the images keep the mapped file
  /// alive).
  private let sections = Mutex<[DictionaryFileSection]>([])

  public init(_ fileCodec: DictionaryFileCodec) {
    self.fileCodec = fileCodec
  }

  /// Opens from a file (memory-mapped).
  public func openFromFile(_ file: String) throws {
    let mapping = try Mmap.map(file)
    try openFromImage(DataView(mapping))
  }

  /// Opens from a memory block.
  public func openFromImage(_ image: DataView) throws {
    sections.withLock { $0.removeAll() }
    let newSections = try fileCodec.readSections(image)
    sections.withLock { $0 = newSections }
  }

  /// Gets a data image of the section having |section_name|.
  /// Returns nil when not found.
  public func getSection(_ sectionName: some StringProtocol) -> DataView? {
    let name = fileCodec.getSectionName(sectionName)
    return sections.withLock { sections in
      sections.first { $0.name == name }?.image
    }
  }
}
