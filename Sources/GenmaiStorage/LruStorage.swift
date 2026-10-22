// Port of mozc/src/storage/lru_storage.{h,cc} (3.35.6354).
//
// The file format is byte-compatible with C++ (little endian):
//   [value_size: u32][size: u32][seed: u32]
//   size * ([fingerprint: u64][last access time: u32][value: value_size bytes])
//
// Deviations:
// - The C++ code memory-maps the file read-write and modifies the mapping.
//   Here the file image is a `[UInt8]` read when the storage is opened, and
//   every modified byte range is written back to the file at once (the same
//   bytes at the same offsets), so the file is updated like the mapping.
// - C++ `char*` item pointers become byte offsets into the image, and
//   std::list<char*> becomes an index-based doubly linked list (`ItemList`)
//   whose node handles are stable like std::list iterators.
// - lookupBytes returns a copy of the value_size bytes (C++ returns a pointer
//   into the mapping), or nil.
// - Values passed to insert/tryInsert/write are byte arrays; insert copies
//   value_size bytes (shorter inputs are zero padded instead of reading past
//   the end as the C++ code would).

import Foundation
import GenmaiBase

public final class LruStorage {
  /// The byte length used to store fingerprint and timestamp for each item.
  /// * 8 bytes for fingerprint
  /// * 4 bytes for timestamp.
  public static let kItemHeaderSize = 12

  private static let kMaxLruSize = 1_000_000  // 1M
  private static let kMaxValueSize = 1024  // 1024 byte

  /// The byte length used to store LRU properties.
  /// * 4 bytes for user specified value size
  /// * 4 bytes for LRU capacity
  /// * 4 bytes for fingerprint seed
  private static let kFileHeaderSize = 12

  private var valueSizeStorage = 0
  private var sizeStorage = 0
  private var seedStorage: UInt32 = 0
  // Offsets into `image`.
  private var nextItem = 0
  private var begin = 0
  private var end = 0
  private var filenameStorage = ""
  private var lruList = ItemList()  // Front is the most recently used data.
  private var lruMap: [UInt64: Int] = [:]  // fp -> lruList node handle
  /// The file contents (C++: the read-write mapping of the file).
  private var image: [UInt8] = []
  /// The open file, to which modified ranges of `image` are written.
  private var file: FileHandle?

  public init() {}

  deinit {
    close()
  }

  // MARK: - Factories

  /// Creates Instance from file. Call open internally
  public static func create(_ filename: String) -> LruStorage? {
    let result = LruStorage()
    if !result.open(filename) {
      GenmaiLog.error("could not open LruStorage")
      return nil
    }
    return result
  }

  /// Creates Instance from file. Call openOrCreate internally
  public static func create(
    _ filename: String, _ valueSize: Int, _ size: Int, _ seed: UInt32
  ) -> LruStorage? {
    let result = LruStorage()
    if !result.openOrCreate(filename, valueSize, size, seed) {
      GenmaiLog.error("could not open LruStorage")
      return nil
    }
    return result
  }

  /// Creates an empty LRU db file
  @discardableResult
  public static func createStorageFile(
    _ filename: String, _ valueSize: Int, _ size: Int, _ seed: UInt32
  ) -> Bool {
    if valueSize == 0 || valueSize > kMaxValueSize {
      GenmaiLog.error("value_size is out of range")
      return false
    }

    if size == 0 || size > kMaxLruSize {
      GenmaiLog.error("size is out of range")
      return false
    }

    if valueSize % 4 != 0 {
      GenmaiLog.error("value_size_ must be 4 byte alignment")
      return false
    }

    let ofs = OutputFileStream(filename)
    if !ofs.good {
      GenmaiLog.error("cannot open \(filename)")
      return false
    }

    var image: [UInt8] = []
    image.reserveCapacity(kFileHeaderSize + (kItemHeaderSize + valueSize) * size)
    image.appendLittleEndian(UInt32(valueSize))
    image.appendLittleEndian(UInt32(size))
    image.appendLittleEndian(seed)
    // Each item: fp = 0, last_access_time = 0, value = '\0' * value_size.
    image.append(contentsOf: repeatElement(0, count: (kItemHeaderSize + valueSize) * size))
    ofs.write(image)
    ofs.close()

    return true
  }

  // MARK: - Open / Close

  @discardableResult
  public func open(_ filename: String) -> Bool {
    close()
    let opened: FileHandle
    let contents: Data
    do {
      opened = try FileHandle(forUpdating: URL(filePath: filename))
      contents = try opened.readToEnd() ?? Data()
    } catch {
      GenmaiLog.error("Cannot open \(filename) with read+write mode: \(error)")
      return false
    }
    if contents.isEmpty {
      // Mapping of zero byte is invalid.
      try? opened.close()
      GenmaiLog.error("Cannot open \(filename) with read+write mode: the file is empty")
      return false
    }
    file = opened
    image = Array(contents)

    if image.count < 8 {
      GenmaiLog.error("file size is too small")
      return false
    }

    filenameStorage = filename
    return openRegion()
  }

  public func close() {
    filenameStorage = ""
    if let file {
      do {
        try file.close()
      } catch {
        GenmaiLog.error("Cannot close the LRU file: \(error)")
      }
    }
    file = nil
    image = []
    lruList.clear()
    lruMap.removeAll()
  }

  /// Try to open existing database
  /// If the file is broken or cannot open, tries to recreate
  /// new file
  @discardableResult
  public func openOrCreate(
    _ filename: String, _ newValueSize: Int, _ newSize: Int, _ newSeed: UInt32
  ) -> Bool {
    if !FileUtil.fileExistsOK(filename) {
      // This is also an expected scenario. Let's create a new data file.
      GenmaiLog.info("\(filename) does not exist. Creating a new one.")
      if !LruStorage.createStorageFile(filename, newValueSize, newSize, newSeed) {
        GenmaiLog.error("CreateStorageFile failed against \(filename)")
        return false
      }
    }

    if !open(filename) {
      close()
      GenmaiLog.error(
        "Failed to open the file or the data is corrupted. So try to recreate new file. filename: \(filename)"
      )
      // If the file exists but is corrupted, the following operation may
      // may fix some problem. However, if the file was temporarily locked
      // by some processes and now no longer locked, the following operation
      // is likely to result in a simple permanent data loss.
      // TODO(yukawa, team): Do not clear the data whenever we can open the
      //     data file and the content is actually valid.
      if !LruStorage.createStorageFile(filename, newValueSize, newSize, newSeed) {
        GenmaiLog.error("CreateStorageFile failed")
        return false
      }
      if !open(filename) {
        close()
        GenmaiLog.error("Open failed after CreateStorageFile. Give up...")
        return false
      }
    }

    // File format has changed
    if newValueSize != valueSize || newSize != size {
      close()
      if !LruStorage.createStorageFile(filename, newValueSize, newSize, newSeed) {
        GenmaiLog.error("CreateStorageFile failed")
        return false
      }
      if !open(filename) {
        close()
        GenmaiLog.error("Open failed after CreateStorageFile")
        return false
      }
    }

    if newValueSize != valueSize || newSize != size {
      close()
      GenmaiLog.error("file is broken")
      return false
    }

    return true
  }

  // MARK: - Accessors

  /// Returns the byte length of each item, which is the user specified value
  /// size + 12 bytes.  Here, 12 bytes is used for fingerprint (8 bytes) and
  /// timestamp (4 bytes).
  public var itemSize: Int { valueSizeStorage + Self.kItemHeaderSize }

  /// Returns the user specified value size.
  public var valueSize: Int { valueSizeStorage }

  /// Returns the maximum number of item (capacity).
  public var size: Int { sizeStorage }

  /// Returns the number of items in LRU.
  public var usedSize: Int { lruList.count }

  /// Returns the seed used for fingerprinting.
  public var seed: UInt32 { seedStorage }

  public var filename: String { filenameStorage }

  // MARK: - Lookup

  /// Looks up elements by key. Returns the value_size bytes of the value.
  public func lookup(_ key: some StringProtocol, lastAccessTime: inout UInt32) -> [UInt8]? {
    guard let ptr = find(key) else {
      return nil
    }
    lastAccessTime = getTimeStamp(ptr)
    return getValue(ptr)
  }

  public func lookup(_ key: some StringProtocol) -> [UInt8]? {
    find(key).map(getValue)
  }

  /// A safer lookup for string values (the buffers returned by above
  /// lookup()'s are not null terminated.) Returns empty if not found.
  public func lookupAsString(_ key: some StringProtocol) -> [UInt8] {
    lookup(key) ?? []
  }

  /// Returns all the values.  The order is new to old (first is the most
  /// recently used one).
  public func getAllValues() -> [[UInt8]] {
    var values: [[UInt8]] = []
    // Iterate data from the most recently used element to the least recently
    // used element.
    for ptr in lruList {
      values.append(getValue(ptr))
    }
    return values
  }

  // MARK: - Mutation

  /// Clears all LRU cache.  The file is also initialized
  @discardableResult
  public func clear() -> Bool {
    // Don't need to clear the page if the lru list is empty
    guard file != nil, !image.isEmpty, !lruList.isEmpty else {
      return true
    }
    let offset = 4 + 4 + 4  // sizeof(value_size_) + sizeof(size_) + sizeof(seed_)
    if offset >= image.count {  // should not happen
      return false
    }
    fill(offset..<image.count)
    lruList.clear()
    lruMap.removeAll()
    openRegion()
    return true
  }

  /// Merges other data into this LRU.
  @discardableResult
  public func merge(_ filename: String) -> Bool {
    let targetStorage = LruStorage()
    if !targetStorage.open(filename) {
      return false
    }
    return merge(targetStorage)
  }

  @discardableResult
  public func merge(_ storage: LruStorage) -> Bool {
    if storage.valueSize != valueSize {
      return false
    }

    if seedStorage != storage.seedStorage {
      return false
    }

    guard file != nil, storage.file != nil else {
      return false
    }
    let otherImage = storage.image

    // (image, offset) of every item.
    var ary: [(image: [UInt8], offset: Int)] = []

    // this file
    do {
      var p = begin
      while p < end {
        ary.append((image, p))
        p += itemSize
      }
    }

    // target file
    do {
      var p = storage.begin
      while p < storage.end {
        ary.append((otherImage, p))
        p += itemSize
      }
    }

    ary = Self.stableSortByTimeStamp(ary) { $0.image.loadLittleEndian(UInt32.self, at: $0.offset + 8) }

    var buf: [UInt8] = []
    var seen = Set<UInt64>()  // remove duplicated entries.
    for item in ary {
      if !seen.insert(item.image.loadLittleEndian(UInt64.self, at: item.offset)).inserted {
        continue
      }
      buf.append(contentsOf: item.image[item.offset..<(item.offset + itemSize)])
    }
    ary = []

    let oldSize = end - begin
    let newSize = min(buf.count, oldSize)

    // TODO(taku): this part is not atomic.
    // If the converter process is killed while memcpy or memset is running,
    // the storage data will be broken.
    image.replaceSubrange(begin..<(begin + newSize), with: buf[0..<newSize])
    if newSize < oldSize {
      image.replaceSubrange((begin + newSize)..<(begin + oldSize), with: repeatElement(0, count: oldSize - newSize))
    }
    persist(begin..<(begin + oldSize))

    return openRegion()
  }

  /// Updates timestamp.
  @discardableResult
  public func touch(_ key: some StringProtocol) -> Bool {
    let fp = legacyFingerprintWithSeed(key, seedStorage)
    guard let node = lruMap[fp] else {
      return false
    }
    update(lruList[node])
    // Move the node pointed to by it->second to the front.
    lruList.moveToFront(node)
    return true
  }

  /// Inserts a key value pair.
  @discardableResult
  public func insert(_ key: some StringProtocol, _ value: [UInt8]?) -> Bool {
    guard let value, file != nil else {
      return false
    }
    let fp = legacyFingerprintWithSeed(key, seedStorage)

    // If the data corresponding to |key| already exists in LRU, update it.
    if let node = lruMap[fp] {
      // Overwrite the data pointed to by it->second and move it to the front.
      update(lruList[node], fp, value)
      lruList.moveToFront(node)
      return true
    }

    // If the LRU is full or we run out of the region, drop the least
    // recently used element (actually, the least recently used element is
    // overwritten with new data).
    if lruMap.count >= sizeStorage || nextItem == end {
      let node = lruList.backNode  // Least recently used data.
      let oldFp = getFP(lruList[node])
      lruMap.removeValue(forKey: oldFp)
      lruList.moveToFront(node)  // Move to front.
      update(lruList[node], fp, value)
      lruMap[fp] = node
      return true
    }

    // A new item can be assigned in the region.
    if nextItem < end {
      update(nextItem, fp, value)
      let node = lruList.pushFront(nextItem)
      lruMap[fp] = node
      // Advance next_item_ for next item.
      nextItem += itemSize
      assert(nextItem <= end)
      return true
    }

    GenmaiLog.error("Insertion failed because no more mmap region is available.")
    return false
  }

  @discardableResult
  public func insert(_ key: some StringProtocol, _ value: String) -> Bool {
    insert(key, Array(value.utf8))
  }

  /// Inserts a key value pair only if |key| already exists.
  /// CAUTION: despite the name, it does nothing if there's no value of |key|.
  @discardableResult
  public func tryInsert(_ key: some StringProtocol, _ value: [UInt8]) -> Bool {
    let fp = legacyFingerprintWithSeed(key, seedStorage)
    if let node = lruMap[fp] {
      update(lruList[node], fp, value)
      lruList.moveToFront(node)
    }
    return true
  }

  /// Deletes the element if exists.  Returns false on failure (it's not
  /// failure if the element for |key| doesn't exist.)
  @discardableResult
  public func delete(_ key: some StringProtocol) -> Bool {
    let fp = legacyFingerprintWithSeed(key, seedStorage)
    return delete(fp: fp)
  }

  /// Deletes all the elements that have timestamp less than |timestamp|, i.e.,
  /// the last access is before |timestamp|.  Returns the number of deleted
  /// elements.
  @discardableResult
  public func deleteElementsBefore(_ timestamp: UInt32) -> Int {
    guard file != nil, !image.isEmpty, begin < end else {
      return 0
    }
    var numDeleted = 0
    while !lruList.isEmpty {
      let node = lruList.backNode
      let lastAccessTime = getTimeStamp(lruList[node])
      if lastAccessTime >= timestamp {
        break
      }
      if delete(node: node) {
        numDeleted += 1
        continue
      }
      GenmaiLog.error("Deletion failed for an item.  Abort deletion.")
      break
    }
    return numDeleted
  }

  /// Writes one entry at |i| th index.
  /// i must be 0 <= i < size.
  /// This data will not update the index of the storage.
  public func write(_ i: Int, _ fp: UInt64, _ value: [UInt8], _ lastAccessTime: UInt32) {
    assert(i < sizeStorage)
    let ptr = begin + i * itemSize
    image.storeLittleEndian(fp, at: ptr)
    image.storeLittleEndian(lastAccessTime, at: ptr + 8)
    if value.count == valueSizeStorage {
      let start = ptr + Self.kItemHeaderSize
      image.replaceSubrange(start..<(start + value.count), with: value)
      persist(ptr..<(ptr + itemSize))
    } else {
      persist(ptr..<(ptr + Self.kItemHeaderSize))
      GenmaiLog.error("value size is not \(valueSizeStorage) byte.")
    }
  }

  public func write(_ i: Int, _ fp: UInt64, _ value: String, _ lastAccessTime: UInt32) {
    write(i, fp, Array(value.utf8), lastAccessTime)
  }

  /// Reads one entry from |i| th index.
  /// i must be 0 <= i < size.
  public func read(_ i: Int) -> (fp: UInt64, value: [UInt8], lastAccessTime: UInt32) {
    assert(i < sizeStorage)
    let ptr = begin + i * itemSize
    return (getFP(ptr), getValue(ptr), getTimeStamp(ptr))
  }

  // MARK: - Private

  /// The offset of the item for `key`, if any.
  private func find(_ key: some StringProtocol) -> Int? {
    let fp = legacyFingerprintWithSeed(key, seedStorage)
    return lruMap[fp].map { lruList[$0] }
  }

  private func getFP(_ ptr: Int) -> UInt64 {
    image.loadLittleEndian(UInt64.self, at: ptr)
  }

  private func getTimeStamp(_ ptr: Int) -> UInt32 {
    image.loadLittleEndian(UInt32.self, at: ptr + 8)
  }

  private func getValue(_ ptr: Int) -> [UInt8] {
    let start = ptr + Self.kItemHeaderSize
    return Array(image[start..<(start + valueSizeStorage)])
  }

  private static func currentTimeStamp() -> UInt32 {
    UInt32(truncatingIfNeeded: Clock.getUnixSeconds())
  }

  /// Writes `image[range]` to the file (C++: the mapping is modified).
  private func persist(_ range: Range<Int>) {
    guard let file, !range.isEmpty else { return }
    do {
      try file.seek(toOffset: UInt64(range.lowerBound))
      try file.write(contentsOf: image[range])
    } catch {
      GenmaiLog.error("Cannot write the LRU file \(filenameStorage): \(error)")
    }
  }

  /// Zero-fills `image[range]` and the file.
  private func fill(_ range: Range<Int>) {
    image.replaceSubrange(range, with: repeatElement(0, count: range.count))
    persist(range)
  }

  private func update(_ ptr: Int) {
    image.storeLittleEndian(Self.currentTimeStamp(), at: ptr + 8)
    persist((ptr + 8)..<(ptr + 12))
  }

  private func update(_ ptr: Int, _ fp: UInt64, _ value: [UInt8]) {
    image.storeLittleEndian(fp, at: ptr)
    image.storeLittleEndian(Self.currentTimeStamp(), at: ptr + 8)
    let dst = ptr + Self.kItemHeaderSize
    let n = min(value.count, valueSizeStorage)
    image.replaceSubrange(dst..<(dst + n), with: value[0..<n])
    if n < valueSizeStorage {
      image.replaceSubrange((dst + n)..<(dst + valueSizeStorage), with: repeatElement(0, count: valueSizeStorage - n))
    }
    persist(ptr..<(ptr + itemSize))
  }

  /// std::stable_sort with CompareByTimeStamp (newer first).
  private static func stableSortByTimeStamp<T>(_ ary: [T], _ timeStamp: (T) -> UInt32) -> [T] {
    let keyed = ary.enumerated().map { (offset: $0.offset, ts: timeStamp($0.element), item: $0.element) }
    return keyed.sorted { a, b in
      a.ts != b.ts ? a.ts > b.ts : a.offset < b.offset
    }.map(\.item)
  }

  /// Initializes this LRU from the file image (C++ Open(char*, size_t)).
  @discardableResult
  private func openRegion() -> Bool {
    guard file != nil else { return false }
    begin = 0
    end = image.count

    valueSizeStorage = Int(image.loadLittleEndian(UInt32.self, at: 0))
    sizeStorage = Int(image.loadLittleEndian(UInt32.self, at: 4))
    seedStorage = image.loadLittleEndian(UInt32.self, at: 8)
    begin = 12

    if valueSizeStorage % 4 != 0 {
      GenmaiLog.error("value_size_ must be 4 byte alignment")
      return false
    }

    if sizeStorage == 0 || sizeStorage > Self.kMaxLruSize {
      GenmaiLog.error("LRU size is invalid: \(sizeStorage)")
      return false
    }

    if valueSizeStorage == 0 || valueSizeStorage > Self.kMaxValueSize {
      GenmaiLog.error("value_size is invalid: \(valueSizeStorage)")
      return false
    }

    if image.count != Self.kFileHeaderSize + itemSize * sizeStorage {
      GenmaiLog.error("LRU file is broken")
      return false
    }

    var ary: [Int] = []
    var p = begin
    while p < end {
      ary.append(p)
      p += itemSize
    }
    ary = Self.stableSortByTimeStamp(ary, getTimeStamp)

    lruList.clear()
    lruMap.removeAll()
    var next: Int? = nil
    for offset in ary {
      if getTimeStamp(offset) != 0 {
        let node = lruList.pushBack(offset)
        lruMap[getFP(offset)] = node
      } else if next == nil {
        next = offset
      }
    }
    nextItem = next ?? end
    assert(nextItem <= end)

    return true
  }

  /// Deletes the element from |fp|.
  private func delete(fp: UInt64) -> Bool {
    guard let node = lruMap[fp] else { return true }
    return delete(fp, node)
  }

  /// Deletes the element from |node|.
  private func delete(node: Int) -> Bool {
    delete(getFP(lruList[node]), node)
  }

  /// Actual implementation of delete() methods.
  private func delete(_ fp: UInt64, _ node: Int) -> Bool {
    // Determine the last element in the region.
    if nextItem < begin + itemSize {
      GenmaiLog.error("next_item_ points to invalid location (broken?)")
      return false
    }
    nextItem -= itemSize

    // Backup the location of the region to which another element will be
    // moved.
    let deletedItemPos = lruList[node]

    // Erase the LRU structure for (fp, it).
    lruMap.removeValue(forKey: fp)
    lruList.erase(node)

    if nextItem != deletedItemPos {
      // Move the region for the last element to the deleted location.  Then,
      // update the LRU structure for the moved element (the offset in the
      // list node is updated.)
      let moved = Array(image[nextItem..<(nextItem + itemSize)])
      image.replaceSubrange(deletedItemPos..<(deletedItemPos + itemSize), with: moved)
      persist(deletedItemPos..<(deletedItemPos + itemSize))
      let movedFp = getFP(nextItem)
      if let movedNode = lruMap[movedFp] {
        lruList[movedNode] = deletedItemPos
      }
    }

    // Clear the region for the next_item_.
    fill(nextItem..<(nextItem + itemSize))

    return true
  }
}

/// An index-based doubly linked list of item offsets (std::list<char*>).
/// Node handles stay valid until the node is erased, like list iterators.
struct ItemList: Sequence {
  private var values: [Int] = []
  private var prevs: [Int] = []
  private var nexts: [Int] = []
  private var freeNodes: [Int] = []
  private var head = -1
  private var tail = -1
  private(set) var count = 0

  var isEmpty: Bool { count == 0 }

  subscript(node: Int) -> Int {
    get { values[node] }
    set { values[node] = newValue }
  }

  /// The node handle of the last element. REQUIRES: !isEmpty.
  var backNode: Int {
    precondition(tail >= 0)
    return tail
  }

  mutating func clear() {
    values.removeAll(keepingCapacity: true)
    prevs.removeAll(keepingCapacity: true)
    nexts.removeAll(keepingCapacity: true)
    freeNodes.removeAll(keepingCapacity: true)
    head = -1
    tail = -1
    count = 0
  }

  private mutating func allocate(_ value: Int) -> Int {
    if let node = freeNodes.popLast() {
      values[node] = value
      return node
    }
    values.append(value)
    prevs.append(-1)
    nexts.append(-1)
    return values.count - 1
  }

  @discardableResult
  mutating func pushBack(_ value: Int) -> Int {
    let node = allocate(value)
    prevs[node] = tail
    nexts[node] = -1
    if tail >= 0 { nexts[tail] = node } else { head = node }
    tail = node
    count += 1
    return node
  }

  @discardableResult
  mutating func pushFront(_ value: Int) -> Int {
    let node = allocate(value)
    linkFront(node)
    count += 1
    return node
  }

  private mutating func linkFront(_ node: Int) {
    prevs[node] = -1
    nexts[node] = head
    if head >= 0 { prevs[head] = node } else { tail = node }
    head = node
  }

  private mutating func unlink(_ node: Int) {
    let p = prevs[node]
    let n = nexts[node]
    if p >= 0 { nexts[p] = n } else { head = n }
    if n >= 0 { prevs[n] = p } else { tail = p }
  }

  /// lru_list_.splice(lru_list_.begin(), lru_list_, node).
  mutating func moveToFront(_ node: Int) {
    if head == node { return }
    unlink(node)
    linkFront(node)
  }

  mutating func erase(_ node: Int) {
    unlink(node)
    freeNodes.append(node)
    count -= 1
  }

  struct Iterator: IteratorProtocol {
    fileprivate let list: ItemList
    fileprivate var node: Int

    mutating func next() -> Int? {
      guard node >= 0 else { return nil }
      let value = list.values[node]
      node = list.nexts[node]
      return value
    }
  }

  func makeIterator() -> Iterator { Iterator(list: self, node: head) }
}
