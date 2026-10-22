// Port of mozc/src/storage/existence_filter_test.cc (3.35.6354).

import GenmaiBase
import Testing

@testable import GenmaiStorage

private func checkValues(_ filter: ExistenceFilter, _ m: Int, _ n: Int) {
  var falsePositives = 0
  var missing: [Int] = []
  for i in 0..<(2 * n) {
    let shouldExist = (i % 2) == 0
    let actual = filter.exists(String(i))
    if shouldExist {
      if !actual { missing.append(i) }
    } else {
      if actual {
        falsePositives += 1
      }
    }
  }
  // CHECK(actual) << " Value = " << i;
  #expect(missing.isEmpty, "Values = \(missing.prefix(10))")

  GenmaiLog.info("false_positives: \(falsePositives)")
}

private func runTest(_ m: Int, _ n: Int) throws {
  GenmaiLog.info("Test \(m) \(n)")
  var builder = ExistenceFilterBuilder.createOptimal(m, UInt32(n))

  for i in 0..<n {
    let val = i * 2
    builder.insert(String(val))
  }

  let filter = builder.build()
  checkValues(filter, m, n)

  let buf = builder.serializeAsString()
  GenmaiLog.info("write size: \(buf.count)")
  let alignedBuf = ImageBuffer(buf)
  let filter2 = try ExistenceFilter.read(alignedBuf.raw)
  checkValues(filter2, m, n)
  withExtendedLifetime(alignedBuf) {}
}

@Suite struct ExistenceFilterTest {
  @Test func runTest() throws {
    let n = 50000
    let m = ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(0.01, 50000)
    try GenmaiStorageTests.runTest(m, n)
  }

  @Test func minFilterSizeEstimateTest() {
    #expect(ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(0.1, 100) == 61)
    #expect(ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(0.01, 100) == 120)
    #expect(ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(0.05, 100) == 79)
    #expect(ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(0.05, 1000) == 781)
  }

  @Test func readWriteTest() throws {
    let kWords = ["a", "b", "c"]

    let kErrorRate: Float = 0.0001
    let numBytes = ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(kErrorRate, kWords.count)

    var builder = ExistenceFilterBuilder.createOptimal(numBytes, UInt32(kWords.count))

    // If we change the default FpType, we also need to update the data FP.
    #expect(cityFingerprintOf(builder.serializeAsString()) == 0x1dcb_e481_17d0_106c)

    for word in kWords {
      builder.insert(word)
    }

    let buf = builder.serializeAsString()

    // If we change the default FpType, we also need to update the data FP.
    #expect(cityFingerprintOf(buf) == 0x877b_3260_08d5_246a)

    let alignedBuf = ImageBuffer(buf)
    let filterRead = try ExistenceFilter.read(alignedBuf.raw)

    for word in kWords {
      #expect(filterRead.exists(word))
    }
    withExtendedLifetime(alignedBuf) {}
  }

  @Test func insertAndExistsTest() {
    let kWords = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]

    let kErrorRate: Float = 0.0001
    let numBytes = ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(kErrorRate, kWords.count)

    var builder = ExistenceFilterBuilder.createOptimal(numBytes, UInt32(kWords.count))

    for word in kWords {
      builder.insert(word)
    }

    let filter = builder.build()

    // If we change the default FpType, we also need to update the data FP.
    #expect(cityFingerprintOf(builder.serializeAsString()) == 0x549d_8930_8d01_3f39)

    for word in kWords {
      #expect(filter.exists(word))
    }
  }

  @Test func insertAndExistsStringTest() {
    let kWords = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]

    let kErrorRate: Float = 0.0001
    let numBytes = ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(
      kErrorRate, kWords.count * 2)

    for fpType: UInt16 in [0, 1] {
      var builder = ExistenceFilterBuilder.createOptimal(numBytes, UInt32(kWords.count), fpType)
      for word in kWords {
        builder.insert(word)
        builder.insert([word, "\t", word])
      }

      let filter = builder.build()
      #expect(filter.params.fpType == fpType)

      for word in kWords {
        #expect(filter.exists(word))
        #expect(filter.exists([word, "\t", word]))
      }
    }
  }

  @Test func fpTypeTest() throws {
    let kWords = ["a", "b", "c"]

    let kErrorRate: Float = 0.0001
    let numBytes = ExistenceFilterBuilder.minFilterSizeInBytesForErrorRate(kErrorRate, kWords.count)

    for fpType in 0..<ExistenceFilterParams.FpType.FP_TYPE_SIZE {
      var builder = ExistenceFilterBuilder.createOptimal(numBytes, UInt32(kWords.count), fpType)

      for word in kWords {
        builder.insert(word)
      }

      let buf = builder.serializeAsString()
      let alignedBuf = ImageBuffer(buf)
      let filterRead = try ExistenceFilter.read(alignedBuf.raw)

      #expect(filterRead.params.fpType == fpType)
      withExtendedLifetime(alignedBuf) {}
    }
  }
}

private func cityFingerprintOf(_ bytes: [UInt8]) -> UInt64 {
  bytes.withUnsafeBytes { cityFingerprint(bytes: $0) }
}
