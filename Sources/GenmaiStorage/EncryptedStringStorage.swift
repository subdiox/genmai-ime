// Port of mozc/src/storage/encrypted_string_storage.{h,cc} (3.35.6354).
//
// Binary strings (std::string) are [UInt8]. `Load(std::string*) -> bool`
// becomes `load() -> [UInt8]?`. The file format is the same as C++:
// [salt: 32 bytes][Encryptor::EncryptString(body)].

import GenmaiBase

public protocol StringStorageInterface: AnyObject, Sendable {
  func load() -> [UInt8]?
  func save(_ input: [UInt8]) -> Bool
}

/// `open` so that tests (and platforms without the encryptor) can override
/// encrypt/decrypt, like the C++ virtual methods.
open class EncryptedStringStorage: StringStorageInterface, @unchecked Sendable {
  // @unchecked Sendable: the base class only holds an immutable filename;
  // subclasses with mutable state are responsible for their own safety.

  // Salt size for encryption
  private static let kSaltSize = 32

  // Maximum file size (64Mbyte)
  private static let kMaxFileSize = 64 * 1024 * 1024

  public let filename: String

  public init(_ filename: String) {
    self.filename = filename
  }

  open func load() -> [UInt8]? {
    var salt: [UInt8]
    var output: [UInt8]

    // Reads encrypted message and salt from local file
    do {
      let mmap: Mmap
      do {
        mmap = try Mmap.map(filename, .readOnly)
      } catch {
        GenmaiLog.error("cannot open user history file: \(error)")
        return nil
      }

      if mmap.size < Self.kSaltSize {
        GenmaiLog.error("file size is too small")
        return nil
      }

      if mmap.size > Self.kMaxFileSize {
        GenmaiLog.error("file size is too big.")
        return nil
      }

      let buf = mmap.buffer
      // copy salt
      salt = Array(buf[0..<Self.kSaltSize])

      // copy body
      output = Array(buf[Self.kSaltSize...])
    }

    if !decrypt(salt, &output) {
      return nil
    }
    return output
  }

  open func save(_ input: [UInt8]) -> Bool {
    // Generate salt.
    var random = Random()
    let salt = random.byteString(Self.kSaltSize)

    var output = input
    if !encrypt(salt, &output) {
      return false
    }

    // Even if histoy is empty, save to them into a file to
    // make the file empty
    let tmpFilename = filename + ".tmp"
    do {
      let ofs = OutputFileStream(tmpFilename)
      if !ofs.good {
        GenmaiLog.error("failed to write: \(tmpFilename)")
        return false
      }

      GenmaiLog.info("Syncing user history to: \(filename)")
      ofs.write(salt)
      ofs.write(output)
      ofs.close()
    }

    do {
      try FileUtil.atomicRename(tmpFilename, filename)
    } catch {
      GenmaiLog.error("AtomicRename failed: \(error); from: \(tmpFilename), to: \(filename)")
      return false
    }

    return true
  }

  public func save(_ input: String) -> Bool {
    save(Array(input.utf8))
  }

  open func encrypt(_ salt: [UInt8], _ data: inout [UInt8]) -> Bool {
    guard let password = PasswordManager.getPassword() else {
      GenmaiLog.error("PasswordManager::GetPassword() failed")
      return false
    }

    if password.isEmpty {
      GenmaiLog.error("password is empty")
      return false
    }

    var key = Encryptor.Key()
    if !key.deriveFromPassword(password, salt) {
      GenmaiLog.error("Encryptor::Key::DeriveFromPassword() failed")
      return false
    }

    if !Encryptor.encryptString(key, &data) {
      GenmaiLog.error("Encryptor::EncryptString() failed")
      return false
    }

    return true
  }

  open func decrypt(_ salt: [UInt8], _ data: inout [UInt8]) -> Bool {
    guard let password = PasswordManager.getPassword() else {
      GenmaiLog.error("PasswordManager::GetPassword() failed")
      return false
    }

    if password.isEmpty {
      GenmaiLog.error("password is empty")
      return false
    }

    // Decrypt message
    var key = Encryptor.Key()
    if !key.deriveFromPassword(password, salt) {
      GenmaiLog.error("Encryptor::Key::DeriveFromPassword failed")
      return false
    }

    if !Encryptor.decryptString(key, &data) {
      GenmaiLog.error("Encryptor::DecryptString() failed")
      return false
    }

    return true
  }
}
