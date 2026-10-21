// Port of mozc/src/data_manager/connection_file_reader.{h,cc} (3.35.6354).
//
// Reads data/dictionary_oss/connection_single_column.txt (first line: the POS
// size; then one cost per line for the square matrix in row-major order).
// Used by DataManager tests to cross-check the compiled connection data.

import GenmaiBase

public final class ConnectionFileReader {
  private let stream: InputFileStream
  public private(set) var done = false
  private var posSize = 0
  private var arrayIndex: Int32 = -1
  public private(set) var cost: Int32 = 0

  public init(_ filename: String) {
    GenmaiLog.info("Loading \(filename)")
    stream = InputFileStream(filename)
    guard let header = stream.getline() else {
      preconditionFailure("\(filename) is empty.")
    }
    posSize = NumberUtil.simpleAtoi(header)
    next()
  }

  // Currently the matrix is square.
  public var leftSize: Int { posSize }
  public var rightSize: Int { posSize }
  public var ridOfLeftNode: Int32 { arrayIndex / Int32(posSize) }
  public var lidOfRightNode: Int32 { arrayIndex % Int32(posSize) }

  public func next() {
    if done {
      return
    }
    guard let line = stream.getline() else {
      done = true
      return
    }
    arrayIndex += 1
    cost = Int32(NumberUtil.simpleAtoi(line))
  }
}
