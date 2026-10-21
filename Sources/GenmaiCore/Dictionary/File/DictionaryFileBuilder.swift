// Port of mozc/src/dictionary/file/dictionary_file_builder.{h,cc} (3.35.6354).
//
// Deviation: WriteImageToFile throws on I/O failure (C++ logs / CHECKs).

import GenmaiBase

/// `mozc::dictionary::DictionaryFileBuilder`.
public final class DictionaryFileBuilder {
  // DictionaryFileBuilder does not take the ownership of |file_codec_|.
  private let fileCodec: DictionaryFileCodec
  private var sections: [DictionaryFileSection] = []
  private var added: Set<[UInt8]> = []

  public init(_ fileCodec: DictionaryFileCodec) {
    self.fileCodec = fileCodec
  }

  /// Adds a section from a file. Returns false if |section_name| has already
  /// been added.
  @discardableResult
  public func addSectionFromFile(_ sectionName: String, _ fileName: String) -> Bool {
    let nameBytes = Array(sectionName.utf8)
    if added.contains(nameBytes) {
      // DLOG(INFO) << "Already added: " << section_name;
      return false
    }
    added.insert(nameBytes)

    guard let data = try? FileUtil.getContentBytes(fileName) else {
      fatalError("Failed to read\(fileName)")
    }
    sections.append(
      DictionaryFileSection(
        image: DataView(copying: data), name: fileCodec.getSectionName(sectionName)))
    return true
  }

  /// Writes the image of dictionary file to a file.
  public func writeImageToFile(_ fileName: String) throws {
    GenmaiLog.info("Start writing dictionary file to \(fileName)")
    let image = fileCodec.writeSections(sections)
    try FileUtil.setContents(fileName, image)
    GenmaiLog.info("Generated")
  }
}
