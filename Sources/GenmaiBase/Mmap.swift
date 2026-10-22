// Port of mozc/src/base/mmap.{h,cc} (3.35.6354). POSIX code path.
//
// `Mmap` (alias `MappedFile`) memory-maps a file and exposes the mapped range
// as UnsafeRawBufferPointer. It unmaps in deinit. The C++ move operations are
// replaced by reference semantics (final class).

#if canImport(Darwin)
  import Darwin
#endif

/// The mapped memory is immutable for READ_ONLY maps and never re-mapped
/// after initialization, so sharing it across threads is safe as long as
/// READ_WRITE users synchronize their own writes. Hence @unchecked Sendable.
public final class Mmap: @unchecked Sendable {
  public enum Mode: Sendable {
    case readOnly
    case readWrite
  }

  private let base: UnsafeMutableRawPointer?
  private let count: Int
  private let adjust: Int

  /// An empty map (`Mmap()` in C++: nothing is mapped).
  public init() {
    base = nil
    count = 0
    adjust = 0
  }

  private init(base: UnsafeMutableRawPointer, count: Int, adjust: Int) {
    self.base = base
    self.count = count
    self.adjust = adjust
  }

  deinit {
    if let base {
      let ptr = base - adjust
      let mapSize = count + adjust
      _ = Mmap.maybeMUnlock(ptr, mapSize)
      if munmap(ptr, mapSize) == -1 {
        GenmaiLog.error("munmap() failed: errno=\(errno)")
      }
    }
  }

  public static func map(_ filename: String, _ mode: Mode = .readOnly) throws -> Mmap {
    try map(filename, offset: 0, size: nil, mode)
  }

  public static func map(
    _ filename: String, offset: Int, size: Int?, _ mode: Mode = .readOnly
  ) throws -> Mmap {
    let flags: Int32
    let prot: Int32
    switch mode {
    case .readOnly:
      flags = O_RDONLY
      prot = PROT_READ
    case .readWrite:
      flags = O_RDWR
      prot = PROT_READ | PROT_WRITE
    }
    let fd = open(filename, flags)
    if fd == -1 {
      throw StatusError.errno(errno, "Failed to open \(filename) with flags \(flags)")
    }
    defer { close(fd) }

    var size = size
    if size == nil {
      var st = stat()
      if fstat(fd, &st) == -1 {
        throw StatusError.errno(errno, "fstat failed")
      }
      let fileSize = Int(st.st_size)
      if offset > fileSize {
        throw StatusError.invalidArgument("offset \(offset) exceeds the file size \(fileSize)")
      }
      size = fileSize - offset
    }
    let mappedSize = size!
    if mappedSize == 0 {
      throw StatusError.invalidArgument("Mapping of zero byte is invalid")
    }
    let pageSize = sysconf(_SC_PAGESIZE)
    if pageSize == -1 {
      throw StatusError.errno(errno, "sysconf(_SC_PAGESIZE) failed")
    }
    let adjust = offset % pageSize
    let mapOffset = offset - adjust
    let mapSize = mappedSize + adjust
    guard let ptr = mmap(nil, mapSize, prot, MAP_SHARED, fd, off_t(mapOffset)),
      ptr != MAP_FAILED
    else {
      throw StatusError.errno(errno, "mmap() failed")
    }
    _ = maybeMLock(ptr, mapSize)
    return Mmap(base: ptr + adjust, count: mappedSize, adjust: adjust)
  }

  public static func isMLockSupported() -> Bool { true }

  @discardableResult
  public static func maybeMLock(_ addr: UnsafeRawPointer, _ len: Int) -> Int32 {
    mlock(addr, len)
  }

  @discardableResult
  public static func maybeMUnlock(_ addr: UnsafeRawPointer, _ len: Int) -> Int32 {
    munlock(addr, len)
  }

  /// The mapped bytes.
  public var buffer: UnsafeRawBufferPointer {
    UnsafeRawBufferPointer(start: base, count: count)
  }

  /// The mapped bytes for writing (only valid for `.readWrite` maps).
  public var mutableBuffer: UnsafeMutableRawBufferPointer {
    UnsafeMutableRawBufferPointer(start: base, count: count)
  }

  public subscript(i: Int) -> UInt8 {
    get { buffer[i] }
    set { mutableBuffer[i] = newValue }
  }

  public var isEmpty: Bool { count == 0 }
  public var size: Int { count }
}

public typealias MappedFile = Mmap
