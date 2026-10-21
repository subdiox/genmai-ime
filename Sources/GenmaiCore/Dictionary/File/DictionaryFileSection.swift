// Port of mozc/src/dictionary/file/section.h (3.35.6354).
//
// Named DictionaryFileSection.swift (not Section.swift) to avoid file name
// clashes inside the GenmaiCore target.

/// `mozc::dictionary::DictionaryFileSection`.
///
/// `image` is a view (C++ `absl::string_view`) into memory owned elsewhere
/// (the memory-mapped dictionary file, or a buffer kept alive through
/// `DataView.owner`). `name` is the 8-byte encoded section name (fingerprint).
public struct DictionaryFileSection: Sendable {
  public var image: DataView
  public var name: [UInt8]

  public init(image: DataView, name: [UInt8]) {
    self.image = image
    self.name = name
  }
}
