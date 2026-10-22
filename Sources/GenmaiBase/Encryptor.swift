// Port of mozc/src/base/encryptor.{h,cc} (3.35.6354). macOS code path for
// ProtectData / UnprotectData.
//
// Binary strings (std::string) are represented as [UInt8].

#if canImport(Darwin)
  import Darwin
#endif

public enum Encryptor {
  public static let kBlockSize = 16  // 128 bit
  public static let kKeySize = 32  // 256 bit key length

  /// Internal type for representing a key.
  public struct Key: Sendable {
    fileprivate var key = [UInt8](repeating: 0, count: Encryptor.kKeySize)
    fileprivate var ivBytes = [UInt8](repeating: 0, count: Encryptor.kBlockSize)
    private var isAvailableFlag = false

    public init() {}

    /// Make a session key from password and salt.
    /// You can also set an initialization vector whose size must be ivSize.
    /// If iv is nil, default iv (all zero) is used.
    public mutating func deriveFromPassword(
      _ password: some Collection<UInt8>, _ salt: some Collection<UInt8> = [UInt8](),
      _ iv: [UInt8]? = nil
    ) -> Bool {
      if isAvailable {
        GenmaiLog.warning("key is already set")
        return false
      }
      if password.isEmpty {
        GenmaiLog.warning("password is empty")
        return false
      }
      if let iv {
        precondition(iv.count >= ivSize)
        ivBytes = Array(iv.prefix(ivSize))
      } else {
        ivBytes = [UInt8](repeating: 0, count: ivSize)
      }
      let derived = Encryptor.getMSCryptDeriveKeyWithSHA1(Array(password), Array(salt))
      // SHA1 is 160bit hash, so 160*2/8 = 40byte
      // Store the session key.
      // NOTE: keySize returns size in bit for historical reasons.
      key = Array(derived.prefix(keySize / 8))
      isAvailableFlag = true
      return true
    }

    public mutating func deriveFromPassword(
      _ password: String, _ salt: String = "", _ iv: [UInt8]? = nil
    ) -> Bool {
      deriveFromPassword(Array(password.utf8), Array(salt.utf8), iv)
    }

    /// return block size. the result should be 16byte with AES
    public var blockSize: Int { Encryptor.kBlockSize }
    /// return initialization vector
    public var iv: [UInt8] { ivBytes }
    /// return the size of initialization vector
    public var ivSize: Int { Encryptor.kBlockSize }
    /// key length (bit)
    public var keySize: Int { Encryptor.kKeySize * 8 }
    /// return true if the key is ready
    public var isAvailable: Bool { isAvailableFlag }

    /// return the size required to encrypt the buffer of size |size|.
    public func getEncryptedSize(_ size: Int) -> Int {
      // Even when given size is already multples of 16, we add
      // an extra block_size as a padding.
      // The extra padding can allow us to know that the message decrypted
      // is invalid or broken.
      (size / blockSize + 1) * blockSize
    }
  }

  // By using SHA1, emulate Microsoft's CryptDerivePassword API
  // http://msdn.microsoft.com/en-us/library/aa379916.aspx
  // (see encryptor.cc for the description of the algorithm).
  static func getMSCryptDeriveKeyWithSHA1(_ password: [UInt8], _ salt: [UInt8]) -> [UInt8] {
    // Step1.
    var buf1 = [UInt8](repeating: 0x36, count: 64)
    // Step2.
    var buf2 = [UInt8](repeating: 0x5c, count: 64)
    // Step 3 & 4
    let hash = UnverifiedSHA1.makeDigest(password + salt)
    for i in 0..<hash.count {
      buf1[i] ^= hash[i]
      buf2[i] ^= hash[i]
    }
    // Step 5 & 6
    return UnverifiedSHA1.makeDigest(buf1) + UnverifiedSHA1.makeDigest(buf2)
  }

  /// Encrypt byte buffer in place (EncryptArray + resize). Fails if `data`
  /// is empty.
  public static func encryptString(_ key: Key, _ data: inout [UInt8]) -> Bool {
    if data.isEmpty {
      GenmaiLog.error("data is nullptr or empty")
      return false
    }
    let size = data.count
    data += [UInt8](repeating: 0, count: key.getEncryptedSize(size) - size)
    if !encryptArray(key, &data, size) {
      GenmaiLog.error("EncryptArray() failed")
      return false
    }
    return true
  }

  /// Decrypt byte buffer in place. Fails if `data` is empty or broken.
  public static func decryptString(_ key: Key, _ data: inout [UInt8]) -> Bool {
    if data.isEmpty {
      GenmaiLog.error("data is nullptr or empty")
      return false
    }
    guard let size = decryptArray(key, &data, data.count) else {
      GenmaiLog.error("DecryptArray() failed")
      return false
    }
    data.removeLast(data.count - size)
    return true
  }

  /// Encrypt `buf[0..<bufSize]` in place. `buf.count` must be at least
  /// key.getEncryptedSize(bufSize); the encrypted size is that value.
  public static func encryptArray(_ key: Key, _ buf: inout [UInt8], _ bufSize: Int) -> Bool {
    if !key.isAvailable {
      GenmaiLog.error("key is not available")
      return false
    }
    if bufSize == 0 {
      GenmaiLog.error("invalid buffer given")
      return false
    }
    let encSize = key.getEncryptedSize(bufSize)
    precondition(buf.count >= encSize)
    // perform PKCS#5 padding
    let paddingSize = encSize - bufSize
    let paddingValue = UInt8(truncatingIfNeeded: paddingSize)
    for i in bufSize..<encSize {
      buf[i] = paddingValue
    }
    // For historical reasons, we are using AES256/CBC for obfuscation.
    UnverifiedAES256.transformCBC(key: key.key, iv: key.ivBytes, block: &buf, blockCount: encSize / kBlockSize)
    return true
  }

  /// Decrypt `buf[0..<bufSize]` in place. Returns the decrypted size, or nil.
  public static func decryptArray(_ key: Key, _ buf: inout [UInt8], _ bufSize: Int) -> Int? {
    if !key.isAvailable {
      GenmaiLog.error("key is not available")
      return nil
    }
    if bufSize == 0 {
      GenmaiLog.error("invalid buffer given")
      return nil
    }
    if bufSize < key.blockSize || bufSize % key.blockSize != 0 {
      GenmaiLog.error("buf size is not multiples of \(key.blockSize)")
      return nil
    }
    let size = bufSize
    // For historical reasons, we are using AES256/CBC for obfuscation.
    UnverifiedAES256.inverseTransformCBC(key: key.key, iv: key.ivBytes, block: &buf, blockCount: size / kBlockSize)
    // perform PKCS#5 un-padding
    let paddingValue = buf[size - 1]
    let paddingSize = Int(paddingValue)
    if paddingValue == 0x00 || paddingSize > kBlockSize {
      GenmaiLog.error("Cannot find PKCS#5 padding values: ")
      return nil
    }
    if size <= paddingSize {
      GenmaiLog.error("padding size is no smaller than original message")
      return nil
    }
    for i in (size - paddingSize)..<size where buf[i] != paddingValue {
      GenmaiLog.error("invalid padding value. message is broken")
      return nil
    }
    return bufSize - paddingSize  // remove padding part
  }

  private static func macKey() -> Key? {
    var key = Key()
    let serialNumber = MacUtil.getSerialNumber()
    let salt = String(getuid(), radix: 16)
    if serialNumber.isEmpty {
      GenmaiLog.error("Cannot get the serial number")
      return nil
    }
    if !key.deriveFromPassword(serialNumber, salt) {
      GenmaiLog.error("Cannot prepare the internal key")
      return nil
    }
    return key
  }

  /// Encrypt data to protect plain_text which may contain sensitive data.
  /// ProtectData for Mac uses the serial number and the current uid as the
  /// key.
  public static func protectData(_ plainText: [UInt8]) -> [UInt8]? {
    guard let key = macKey() else { return nil }
    var cipherText = plainText
    if !encryptString(key, &cipherText) {
      GenmaiLog.error("Cannot encrypt the text")
      return nil
    }
    return cipherText
  }

  /// Same as protectData.
  public static func unprotectData(_ cipherText: [UInt8]) -> [UInt8]? {
    guard let key = macKey() else { return nil }
    var plainText = cipherText
    if !decryptString(key, &plainText) {
      GenmaiLog.error("Cannot encrypt the text")
      return nil
    }
    return plainText
  }
}
