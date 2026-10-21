// Port of mozc/src/client/user_dictionary/user_dictionary_storage.{h,cc} (3.35.6354).
//
// UserDicStorageInterface provides interface for accessing data
// storage of the user dictionary. Subclasses determine how to save
// dictionary data on a disk.
//
// The following are not responsibility of UserDicStorageInterface
// and supposed to be performed by its client.
//
// (1) Validation of input values.
//   Subclasses that implement the interface of
//   UserDicStorageInterface are supposed to perform only minimal
//   validation of input value, for example a subclass that saves
//   dictionary data in a tab-separated text file usually doesn't
//   accept input with a tab or new line character and should check
//   input for them. However, UserDicStorageInterface and its
//   subclasses don't care about any more complicated
//   application-level validity of data like an acceptable POS set,
//   character encoding and so on. The class takes input value as it
//   is.
//
// (2) Duplicate entry elimination.
//   UserDicStorageInterface treats an entry in it with a unique
//   integer key. This means it doesn't take into account any actual
//   attribute of the entry when distinguishing it from another. If
//   any kind of duplicate elimination is necessary, it should be done
//   before the value is passed to the class.
//
// (3) Importing a dictionary file of Mozc or third party IMEs.
//   UserDicStorageInterface provides CreateDictionary() and
//   AddEntry(). Clients of the class can import an external
//   dictionary file using the two member functions.
//
// Errors: functions returning absl::Status / absl::StatusOr in C++ throw.
// The thrown error is either a `StatusError` (plain absl status codes) or a
// `UserDictionaryUtil.ExtendedErrorCode` (C++ `ToStatus(ExtendedErrorCode)`,
// read back with `status.raw_code()`); `extendedErrorCode(of:)` maps both.

import GenmaiBase
import GenmaiProtocol

public final class UserDictionaryStorage {
  public typealias UserDictionary = Genmai_UserDictionary_UserDictionary
  public typealias UserDictionaryEntry = Genmai_UserDictionary_UserDictionary.Entry
  public typealias ExtendedErrorCode = UserDictionaryUtil.ExtendedErrorCode

  // 512MByte
  // We expand the limit of serialized message from 64MB(default) to 512MB
  private static let kDefaultTotalBytesLimit = 512 << 20

  // If the last file size exceeds kDefaultWarningTotalBytesLimit,
  // we show a warning dialog saying that "All words will not be
  // saved correctly. Please make the dictionary size smaller"
  private static let kDefaultWarningTotalBytesLimit = 256 << 20

  // The limits of dictionary/entry size.
  private static let kMaxDictionarySize = 100
  private static let kMaxEntrySize = 1_000_000

  /// The storage proto (`GetProto()`).
  public var proto = Genmai_UserDictionary_UserDictionaryStorage()
  /// return the filename of user dictionary
  public let filename: String
  private let processMutex: ProcessMutex

  /// Returns the default user dictionary filename.
  public static func getDefaultUserDictionaryFileName() -> String {
    UserDictionaryUtil.getUserDictionaryFileName()
  }

  /// Uses the default file name.
  public convenience init() {
    self.init(UserDictionaryStorage.getDefaultUserDictionaryFileName())
  }

  public init(_ filename: String) {
    self.filename = filename
    processMutex = ProcessMutex(FileUtil.basename(filename))
  }

  deinit {
    unlock()
  }

  /// maximum number of dictionaries this storage can hold
  public static func maxDictionarySize() -> Int { kMaxDictionarySize }

  /// maximum number of entries one dictionary can hold
  public static func maxEntrySize() -> Int { kMaxEntrySize }

  /// Maps an error thrown by this class (or by the importer) to the C++
  /// `status.raw_code()` when it is an ExtendedErrorCode, else nil.
  public static func extendedErrorCode(of error: any Error) -> ExtendedErrorCode? {
    error as? ExtendedErrorCode
  }

  /// Succeeds (returns) if data tied with this object already exists.
  /// Otherwise (throws), it means that the space for the data is used for
  /// the first time.
  public func exists() throws {
    try FileUtil.fileExists(filename)
  }

  /// Load the data from filename actually.
  private func loadInternal() throws {
    let bytes: [UInt8]
    do {
      bytes = try FileUtil.getContentBytes(filename)
    } catch {
      do {
        try exists()
      } catch {
        throw error  // kNotFound error.
      }
      throw StatusError.unknown("\(filename) exists but cannot open it: OK")
    }

    // Increase the maximum capacity of file size
    // from 64MB (default) to 512MB.
    // This is a tentative bug fix for http://b/2498675
    // TODO(taku): we have to introduce a restriction to
    // the file size and let user know "import failure" if user
    // wants to use more than 512MB.
    // NOTE: SwiftProtobuf rejects string fields with invalid UTF-8, which C++
    // proto2 accepts; such a file fails to load here.
    if bytes.count > UserDictionaryStorage.kDefaultTotalBytesLimit {
      proto = Genmai_UserDictionary_UserDictionaryStorage()
      throw StatusError.dataLoss("ParseFromCodedStream failed. File seems broken")
    }
    do {
      proto = try Genmai_UserDictionary_UserDictionaryStorage(serializedBytes: bytes)
    } catch {
      // ParseFromCodedStream clears the message before parsing.
      proto = Genmai_UserDictionary_UserDictionaryStorage()
      throw StatusError.dataLoss("ParseFromCodedStream failed. File seems broken")
    }
  }

  /// Loads a user dictionary from the file.
  /// NOTE: If the file is not existent, nothing is updated.
  ///       Therefore if the file is deleted after first load(),
  ///       second load() does nothing so the content loaded by first load()
  ///       is kept as is.
  public func load() throws {
    var loadError: (any Error)?
    do {
      try loadInternal()
    } catch {
      loadError = error
    }

    // Check dictionary id here. if id is 0, assign random ID.
    for i in proto.dictionaries.indices where proto.dictionaries[i].id == 0 {
      proto.dictionaries[i].id = createNewDictionaryId()
    }

    if let loadError {
      throw loadError
    }
  }

  /// Serialize user dictionary to local file.
  /// Need to call Lock() the dictionary before calling Save().
  /// A `.resourceExhausted` error (TOO_BIG_FILE_BYTES) means the file was
  /// saved but exceeds the warning size.
  public func save() throws {
    if !processMutex.locked {
      throw StatusError.failedPrecondition(
        "Must be locked before saving the dictionary (SYNC_FAILURE)")
    }

    let tmpFilename = filename + ".tmp"
    var sizeErrorMsg = ""
    var tooBigFileBytes = false
    do {
      let ofs = OutputFileStream(tmpFilename)
      if !ofs.good {
        throw StatusError.permissionDenied(
          "Cannot open \(tmpFilename) for write (SYNC_FAILURE)")
      }

      let serialized: [UInt8]
      do {
        serialized = try proto.serializedBytes()
      } catch {
        throw StatusError.permissionDenied(
          "SerializeToOstream failed (SYNC_FAILURE); path = \(tmpFilename)")
      }
      ofs.write(serialized)
      if !ofs.good {
        throw StatusError.permissionDenied(
          "SerializeToOstream failed (SYNC_FAILURE); path = \(tmpFilename)")
      }

      let fileSize = serialized.count

      ofs.close()
      if ofs.fail {
        throw StatusError.permissionDenied("Failed to close \(tmpFilename) (SYNC_FAILURE)")
      }

      if fileSize >= UserDictionaryStorage.kDefaultWarningTotalBytesLimit {
        sizeErrorMsg =
          "The file size exceeds the limit: size = \(fileSize), limit = \(UserDictionaryStorage.kDefaultWarningTotalBytesLimit)"
        // Perform "AtomicRename" even if the size exceeded.
        tooBigFileBytes = true
      }
    }

    do {
      try FileUtil.atomicRename(tmpFilename, filename)
    } catch {
      let message = (error as? StatusError)?.message ?? "\(error)"
      var msg =
        "\(message); Atomic rename from \(tmpFilename) to \(filename) failed (SYNC_FAILURE)"
      if tooBigFileBytes {
        msg += "; " + sizeErrorMsg
      }
      throw StatusError.permissionDenied(msg)
    }

    if tooBigFileBytes {
      throw StatusError(
        .resourceExhausted, "Save was successful with error (TOO_BIG_FILE_BYTES): \(sizeErrorMsg)")
    }
  }

  /// Lock the dictionary so that other processes/threads cannot
  /// execute mutable operations on this dictionary.
  public func lock() -> Bool {
    let locked = processMutex.lock()
    if !locked {
      GenmaiLog.error("Lock() failed")
    }
    return locked
  }

  /// release the lock
  @discardableResult
  public func unlock() -> Bool {
    processMutex.unlock()
  }

  /// Export a dictionary to a file in TSV format.
  public func exportDictionary(_ dictionaryId: UInt64, _ filename: String) throws {
    let index = getUserDictionaryIndex(dictionaryId)
    if index < 0 {
      throw ExtendedErrorCode.unknownDictionaryId
    }

    let ofs = OutputFileStream(filename)
    if !ofs.good {
      throw StatusError.permissionDenied("Cannot open export file: \(filename)")
    }

    let dic = proto.dictionaries[index]
    for entry in dic.entries {
      ofs.write(entry.key)
      ofs.write("\t")
      ofs.write(entry.value)
      ofs.write("\t")
      ofs.write(UserPos.getStringPosType(entry.pos))
      ofs.write("\t")
      ofs.writeLine(entry.comment)
    }
    ofs.close()
  }

  /// Returns true if the given storage hits the limit for the number of
  /// dictionaries.
  public func isStorageFull() -> Bool {
    proto.dictionaries.count >= UserDictionaryStorage.maxDictionarySize()
  }

  /// Returns true if the given dictionary hits the limit for the number of
  /// entries.
  public static func isDictionaryFull(_ dictionary: UserDictionary) -> Bool {
    dictionary.entries.count >= maxEntrySize()
  }

  /// return the index of dictionary_id.
  /// returns -1 if no dictionary is found.
  public func getUserDictionaryIndex(_ dictionaryId: UInt64) -> Int {
    for i in proto.dictionaries.indices where proto.dictionaries[i].id == dictionaryId {
      return i
    }
    return -1
  }

  /// returns (a copy of) the UserDictionary corresponding to dictionary_id.
  /// returns nil when no dictionary is found. Use `withUserDictionary` to
  /// mutate it in place (the C++ returns a mutable pointer).
  public func getUserDictionary(_ dictionaryId: UInt64) -> UserDictionary? {
    let index = getUserDictionaryIndex(dictionaryId)
    return index < 0 ? nil : proto.dictionaries[index]
  }

  /// Mutates the UserDictionary corresponding to dictionary_id in place.
  /// Returns nil (without calling `body`) when no dictionary is found.
  @discardableResult
  public func withUserDictionary<R>(
    _ dictionaryId: UInt64, _ body: (inout UserDictionary) throws -> R
  ) rethrows -> R? {
    let index = getUserDictionaryIndex(dictionaryId)
    if index < 0 {
      return nil
    }
    return try body(&proto.dictionaries[index])
  }

  /// returns the dictionary id associated with the "dictionary_name".
  public func getUserDictionaryId(_ dictionaryName: String) throws -> UInt64 {
    for dictionary in proto.dictionaries where dictionaryName.utf8.elementsEqual(dictionary.name.utf8) {
      return dictionary.id
    }
    throw StatusError.notFound("Dictionary id is not found for \(dictionaryName)")
  }

  /// Return true if this object can accept the given dictionary name.
  /// Throws an ExtendedErrorCode otherwise.
  private func isValidDictionaryName(_ dictionaryName: String) throws {
    try UserDictionaryUtil.validateDictionaryName(dictionaryName)

    for dictionary in proto.dictionaries where dictionary.name.utf8.elementsEqual(dictionaryName.utf8) {
      GenmaiLog.error("duplicated dictionary name")
      throw ExtendedErrorCode.dictionaryNameDuplicated
    }
  }

  /// Generates a new dictionary id, i.e. id which is not in the storage.
  public func createNewDictionaryId() -> UInt64 {
    let kInvalidDictionaryId: UInt64 = 0

    var id = kInvalidDictionaryId
    while id == kInvalidDictionaryId {
      id = UInt64.random(in: UInt64.min...UInt64.max)

      // Duplication check.
      for dictionary in proto.dictionaries where dictionary.id == id {
        // Duplicated id is found. So invalidate it to retry the generating.
        id = kInvalidDictionaryId
        break
      }
    }
    return id
  }

  /// Create a new dictionary with a specified name. Returns the id of
  /// the new instance. Throws an ExtendedErrorCode on failure.
  @discardableResult
  public func createDictionary(_ dictionaryName: String) throws -> UInt64 {
    do {
      try isValidDictionaryName(dictionaryName)
    } catch {
      GenmaiLog.error("Invalid dictionary name is passed")
      throw error
    }

    if isStorageFull() {
      GenmaiLog.error("too many dictionaries")
      throw ExtendedErrorCode.dictionarySizeLimitExceeded
    }

    let newDictionaryId = createNewDictionaryId()
    var dictionary = UserDictionary()
    dictionary.id = newDictionaryId
    dictionary.name = dictionaryName
    proto.dictionaries.append(dictionary)

    return newDictionaryId
  }

  /// Rename a dictionary.
  public func renameDictionary(_ dictionaryId: UInt64, _ dictionaryName: String) throws {
    let index = getUserDictionaryIndex(dictionaryId)
    if index < 0 {
      throw ExtendedErrorCode.unknownDictionaryId
    }

    if proto.dictionaries[index].name.utf8.elementsEqual(dictionaryName.utf8) {
      return
    }

    do {
      try isValidDictionaryName(dictionaryName)
    } catch {
      GenmaiLog.error("Invalid dictionary name is passed")
      throw error
    }

    proto.dictionaries[index].name = dictionaryName
  }

  /// Delete a dictionary.
  public func deleteDictionary(_ dictionaryId: UInt64) throws {
    let index = getUserDictionaryIndex(dictionaryId)
    if index < 0 {
      throw ExtendedErrorCode.unknownDictionaryId
    }

    proto.dictionaries.remove(at: index)
  }

  public var dictionariesSize: Int { proto.dictionaries.count }

  public func dictionaries(_ i: Int) -> UserDictionary { proto.dictionaries[i] }
}
