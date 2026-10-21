// Small helpers of mozc/src/gui/dictionary_tool/dictionary_tool.cc (3.35.6354): QString::arg and the
// IsReadableToImport / IsWritableToExport checks. The text line iterators used for importing are GenmaiCore's
// (UserDictionaryImporter.createTextLineIterator).

import Foundation

enum DictionaryToolText {
  /// QString::arg: each argument replaces all occurrences of the lowest-numbered remaining "%N" marker.
  static func arg(_ template: String, _ args: any CustomStringConvertible...) -> String {
    var result = template
    for arg in args {
      guard let n = (1...99).first(where: { replaceMarker(result, $0, "\u{0}") != result }) else {
        break
      }
      result = replaceMarker(result, n, arg.description)
    }
    return result
  }

  private static func replaceMarker(_ str: String, _ n: Int, _ value: String) -> String {
    let marker = Array("%\(n)")
    let chars = Array(str)
    var out = ""
    var i = 0
    while i < chars.count {
      if i + marker.count <= chars.count, Array(chars[i..<(i + marker.count)]) == marker,
        !(i + marker.count < chars.count && chars[i + marker.count].isASCII && chars[i + marker.count].isNumber)
      {
        out += value
        i += marker.count
      } else {
        out.append(chars[i])
        i += 1
      }
    }
    return out
  }
}

/// DictionaryTool::IsReadableToImport.
func isReadableToImport(_ fileName: String) -> Bool {
  var isDirectory: ObjCBool = false
  return FileManager.default.fileExists(atPath: fileName, isDirectory: &isDirectory) && !isDirectory.boolValue
    && FileManager.default.isReadableFile(atPath: fileName)
}

/// DictionaryTool::IsWritableToExport.
func isWritableToExport(_ fileName: String) -> Bool {
  let fileManager = FileManager.default
  var isDirectory: ObjCBool = false
  if fileManager.fileExists(atPath: fileName, isDirectory: &isDirectory) {
    return !isDirectory.boolValue && fileManager.isWritableFile(atPath: fileName)
  }
  let dir = (fileName as NSString).deletingLastPathComponent
  let dirPath = dir.isEmpty ? fileManager.currentDirectoryPath : dir
  return fileManager.isExecutableFile(atPath: dirPath) && fileManager.isWritableFile(atPath: dirPath)
}
