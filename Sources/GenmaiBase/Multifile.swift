// Port of mozc/src/base/multifile.{h,cc} (3.35.6354).
//
// This is a minimum implementation of multifile, which enables us to
// treat multiple files like a single concatenated file.

public final class InputMultiFile {
  private let filenames: [String]
  private var nextIndex = 0
  private var ifs: InputFileStream?

  /// filenames must be separated by comma(s), e.g., "foo.txt,hoge.txt".
  public init(_ filenames: String) {
    self.filenames = filenames.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
    if !self.filenames.isEmpty {
      _ = openNext()
    } else {
      GenmaiLog.error("empty filenames")
    }
  }

  /// Reads one line. Returns nil after reading all the lines.
  public func readLine() -> String? {
    guard ifs != nil else { return nil }
    repeat {
      if let line = ifs?.getline() {
        return line
      }
    } while openNext()
    return nil
  }

  /// Bytes version of readLine.
  public func readLineBytes() -> ArraySlice<UInt8>? {
    guard ifs != nil else { return nil }
    repeat {
      if let line = ifs?.getlineBytes() {
        return line
      }
    } while openNext()
    return nil
  }

  private func openNext() -> Bool {
    while nextIndex < filenames.count {
      let name = filenames[nextIndex]
      nextIndex += 1
      let stream = InputFileStream(name)
      ifs = stream
      if !stream.fail {
        return true
      }
      GenmaiLog.error("Cannot open \(name)")
    }
    ifs = nil
    return false
  }
}
