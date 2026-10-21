// Port of mozc/src/storage/louds/bit_vector_based_array_builder.{h,cc}
// (3.35.6354).

public final class BitVectorBasedArrayBuilder {
  private var built = false
  private var elements: [[UInt8]] = []
  // Initial values of base_length_ and step_length_ is (4, 1) bytes.
  private var baseLength = 4
  private var stepLength = 1
  private var imageBytes: [UInt8] = []

  public init() {}

  /// Adds the element to the builder.
  /// The length of the element would be ceiling by padding '\x00' bytes to
  /// the end. Please see also comments for setSize below.
  public func add(_ element: [UInt8]) {
    precondition(!built)
    elements.append(element)
  }

  /// Sets size related parameters. The size of each element will be ceiling
  /// (when the image is built) as follows:
  /// - if the length of a element is less than or equal to base_length,
  ///   the length in the image should be base_length.
  /// - otherwise, the length in the image should be
  ///   "base_length + N * step_length", where N is a positive integer.
  /// For example, let base_length be '4' and step_length be '2';
  /// - "" would be stored as "\x00\x00\x00\x00".
  /// - "a" would be stored as "a\x00\x00\x00"
  /// - "abcd" would be stored as "abcd"
  /// - "abcde" would be stored as "abcde\x00"
  /// Note that the '\0' terminator should *NOT* be stored in the image.
  public func setSize(_ baseLength: Int, _ stepLength: Int) {
    precondition(!built)
    self.baseLength = baseLength
    self.stepLength = stepLength
  }

  public func build() {
    precondition(!built)

    var bitStream = BitStream()
    var data: [UInt8] = []

    // Output to the bit_stream and the data.
    for element in elements {
      // Counts how many steps is needed.
      var numSteps = 0
      var length = element.count
      while length > baseLength {
        numSteps += 1
        length -= stepLength
      }

      // Output '0' as a beginning bit, followed by the num_steps of '1'-bits.
      let outputLength = baseLength + numSteps * stepLength
      assert(outputLength >= element.count)
      bitStream.pushBit(0)
      for _ in 0..<numSteps {
        bitStream.pushBit(1)
      }

      // Output word data (excluding '\0' termination) and then padding by
      // '\0' to align to the output length.
      data.append(contentsOf: element)
      data.append(contentsOf: repeatElement(0, count: outputLength - element.count))
    }

    // Output a sentinel, and align to 32 bits.
    bitStream.pushBit(0)
    bitStream.fillPadding32()

    // Output the image.
    pushInt32(bitStream.byteSize, &imageBytes)
    pushInt32(baseLength, &imageBytes)
    pushInt32(stepLength, &imageBytes)
    pushInt32(0, &imageBytes)

    imageBytes.append(contentsOf: bitStream.image)
    imageBytes.append(contentsOf: data)

    built = true
  }

  public var image: [UInt8] {
    precondition(built)
    return imageBytes
  }
}
