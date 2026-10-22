// Port of mozc/src/storage/encrypted_string_storage.{h,cc} (3.35.6354).
//
// Binary strings (std::string) are [UInt8]. `Load(std::string*) -> bool`
// becomes `load() -> [UInt8]?`. The file format is the same as C++:
// [salt: 32 bytes][Encryptor::EncryptString(body)].

import Foundation
import GenmaiBase

public protocol StringStorageInterface: AnyObject, Sendable {
  func load() -> [UInt8]?
  func save(_ input: [UInt8]) -> Bool
}

/// A final class (the C++ virtual methods are only overridden by an
/// Android-only test mock, which is not ported); other storages implement
/// StringStorageInterface.
public final class EncryptedStringStorage: StringStorageInterface, Sendable {
  // Salt size for encryption
  private static let kSaltSize = 32

  // Maximum file size (64Mbyte)
  private static let kMaxFileSize = 64 * 1024 * 1024

  public let filename: String

  public init(_ filename: String) {
    self.filename = filename
  }

  public func load() -> [UInt8]? {
    var salt: [UInt8]
    var output: [UInt8]

    // Reads encrypted message and salt from local file
    do {
      let buf: Data
      do {
        buf = try Data(contentsOf: URL(filePath: filename), options: .alwaysMapped)
      } catch {
        GenmaiLog.error("cannot open user history file: \(error)")
        return nil
      }

      if buf.count < Self.kSaltSize {
        GenmaiLog.error("file size is too small")
        return nil
      }

      if buf.count > Self.kMaxFileSize {
        GenmaiLog.error("file size is too big.")
        return nil
      }

      // copy salt
      salt = Array(buf.prefix(Self.kSaltSize))

      // copy body
      output = Array(buf.dropFirst(Self.kSaltSize))
    }

    if !decrypt(salt, &output) {
      return nil
    }
    return output
  }

  public func save(_ input: [UInt8]) -> Bool {
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

  public func encrypt(_ salt: [UInt8], _ data: inout [UInt8]) -> Bool {
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

  public func decrypt(_ salt: [UInt8], _ data: inout [UInt8]) -> Bool {
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
