// Port of mozc/src/base/encryptor_test.cc (3.35.6354).

import Testing

@testable import GenmaiBase

private struct TestData {
  let password: String
  let salt: String
  let iv: String
  let input: [UInt8]
  let encrypted: [UInt8]
}

private let kTestData: [TestData] = [
  TestData(
    password: "foohoge", salt: "salt", iv: "1111111111111111", input: Array("foo".utf8),
    encrypted: [
      0x27, 0x32, 0x66, 0x88, 0x82, 0x33, 0x78, 0x80, 0x58, 0x29, 0xBF, 0xDD, 0x46, 0x9A, 0xCC,
      0x87,
    ]),
  TestData(
    password: "password", salt: "salt", iv: "1111111111111111", input: Array("a".utf8),
    encrypted: [
      0x2A, 0xA1, 0x73, 0xB0, 0x91, 0x1C, 0x22, 0x40, 0x55, 0xDB, 0xAB, 0xC0, 0x77, 0x39, 0xE6,
      0x57,
    ]),
  TestData(
    password: "password", salt: "salt", iv: "1111111111111111", input: Array("test".utf8),
    encrypted: [
      0x13, 0x16, 0x0A, 0xA4, 0x2B, 0xA3, 0x02, 0xC4, 0xEF, 0x47, 0x98, 0x6D, 0x9F, 0xC9, 0xAD,
      0x43,
    ]),
  TestData(
    password: "password", salt: "salt", iv: "0123456789abcdef",
    input: Array(
      ("dhoifasoifaoishd" + "oifahsoifdhaoish" + "fioashdoifahisod" + "fhaioshdfioa").utf8),
    encrypted: [
      0x27, 0x92, 0xD1, 0x4F, 0xCE, 0x71, 0xFF, 0xA0, 0x9E, 0x52, 0xAB, 0x96, 0xB4, 0x5D, 0x1A,
      0x2F, 0xE0, 0xC7, 0xB3, 0x92, 0xD7, 0xB8, 0x29, 0xB0, 0xEF, 0xD3, 0x51, 0x9F, 0xBD, 0x87,
      0xE0, 0xB4, 0x0A, 0x06, 0xE0, 0x9A, 0x03, 0x72, 0x48, 0xB3, 0x8F, 0x9A, 0x5E, 0xAC, 0xCD,
      0x5D, 0xB8, 0x0B, 0x01, 0x1D, 0x2C, 0xD7, 0xAA, 0x55, 0x05, 0x0F, 0x4E, 0xD5, 0x73, 0xC0,
      0xCB, 0xE2, 0x10, 0x69,
    ]),
]

@Suite struct EncryptorTest {
  @Test func verificationTest() {
    SystemUtil.withTempUserProfile { _ in
      for data in kTestData {
        var key1 = Encryptor.Key()
        var key2 = Encryptor.Key()
        let derived1 = key1.deriveFromPassword(data.password, data.salt, Array(data.iv.utf8))
        #expect(derived1)
        #expect(key1.isAvailable)
        let derived2 = key2.deriveFromPassword(data.password, data.salt, Array(data.iv.utf8))
        #expect(derived2)
        #expect(key2.isAvailable)

        var input = data.input
        let decrypted = data.input
        #expect(Encryptor.encryptString(key1, &input))
        #expect(input == data.encrypted)
        #expect(Encryptor.decryptString(key2, &input))
        #expect(input == decrypted)
      }
    }
  }

  @Test func basicTest() {
    var key = Encryptor.Key()
    let derived3 = key.deriveFromPassword("")
    #expect(!derived3)
    #expect(!key.isAvailable)
    let derived4 = key.deriveFromPassword("test")
    #expect(derived4)
    #expect(key.isAvailable)
    #expect(key.blockSize == 16)
    #expect(key.keySize == 256)
    #expect(key.ivSize == 16)
  }

  @Test func encryptBatch() {
    let kSizeTable = [1, 10, 16, 32, 100, 1000, 1600, 10000, 16000, 100000]
    var random = Random()
    for size in kSizeTable {
      let original = random.byteString(size)

      var key1 = Encryptor.Key()
      var key2 = Encryptor.Key()
      var key3 = Encryptor.Key()
      var key4 = Encryptor.Key()
      let derived5 = key1.deriveFromPassword("test", "salt")
      #expect(derived5)
      let derived6 = key2.deriveFromPassword("test", "salt")
      #expect(derived6)
      let derived7 = key3.deriveFromPassword("test", "salt2")
      #expect(derived7)  // wrong salt
      let derived8 = key4.deriveFromPassword("test2", "salt")
      #expect(derived8)  // wrong key
      #expect(key1.isAvailable)
      #expect(key2.isAvailable)
      #expect(key3.isAvailable)
      #expect(key4.isAvailable)

      var encrypted = original
      #expect(Encryptor.encryptString(key1, &encrypted))
      #expect(encrypted.count % key1.blockSize == 0)
      #expect(encrypted != original)

      var encrypted3 = encrypted
      var encrypted4 = encrypted

      #expect(Encryptor.decryptString(key2, &encrypted))
      #expect(encrypted.count == original.count)
      #expect(encrypted == original)

      // wrong key
      _ = Encryptor.decryptString(key3, &encrypted3)
      _ = Encryptor.decryptString(key4, &encrypted4)
      #expect(original != encrypted3)
      #expect(original != encrypted4)

      // empty string
      var emptyString: [UInt8] = []
      #expect(!Encryptor.encryptString(key1, &emptyString))
      #expect(!Encryptor.decryptString(key1, &emptyString))
    }
  }

  @Test(.enabled(if: !MacUtil.getSerialNumber().isEmpty, "needs the Mac serial number"))
  func protectData() {
    let kSizeTable = [1, 10, 100, 1000, 10000, 100000]
    var random = Random()
    for size in kSizeTable {
      let input = random.byteString(size)
      let output = Encryptor.protectData(input)
      #expect(output != nil)
      #expect(output != input)
      let result = output.flatMap { Encryptor.unprotectData($0) }
      #expect(result == input)
    }
  }
}
