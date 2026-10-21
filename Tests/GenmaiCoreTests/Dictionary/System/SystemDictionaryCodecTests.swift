// Port of mozc/src/dictionary/system/codec_test.cc (3.35.6354).
//
// Note: ValueCodecTest round-trips every code point U+0001..U+10FFFF on raw
// bytes (the byte APIs), so surrogates (which a Swift String cannot hold) are
// covered as in C++.

import GenmaiBase
import Testing

@testable import GenmaiCore

private func isExpectedEncodedSize(_ c: UInt32, _ encoded: [UInt8]) -> (Bool, String) {
  let size = encoded.count
  if c == 0x00 {
    return (false, "NUL is not supported.")
  }
  if c <= 0xff {
    return (size == 2, "U+00?? (ASCII) should be encoded into 2 bytes.")
  }
  if 0x10000 <= c && c <= 0x10ffff {
    if (c & 0xffff) == 0 {
      return (size == 2, "U+?0000 and U+100000 are encoded into 2 bytes.")
    }
    if (c & 0xff) == 0 {
      return (size == 3, "U+???00 and U+10??00 are encoded into 3 bytes.")
    }
    if ((c & 0xff00) >> 8) == 0 {
      return (size == 3, "U+?00?? and U+1000?? are encoded into 3 bytes.")
    }
    return (
      size == 4,
      "[U+10000, U+10FFFF] except for U+???00, U+?00??, U+10??00 and U+1000?? should be encoded into 4 bytes."
    )
  }
  if 0x10ffff < c {
    return (false, "U+110000 and greater are not supported.")
  }
  if 0xffff < c {
    return (false, "Should not reach here.")
  }

  // Hereafter, |c| should be represented as 0x????
  let s = UInt16(c)
  if (s & 0xff) == 0 {
    return (size == 2, "U+??00 are encoded into 2 bytes.")
  }
  if 0x3041 <= s && s < 0x3095 {
    return (size == 1, "Hiragana(85 characters) are encoded into 1 byte.")
  }
  if 0x30a1 <= s && s < 0x30fd {
    return (size == 1, "Katakana (92 characters) are encoded into 1 byte.")
  }
  if 0x4e00 <= s && s < 0x9800 {
    return (size == 2, "Frequent Kanji and others (74*256 characters) are encoded into 2 bytes.")
  }
  return (size == 3, "Other characters should be encoded into 3bytes.")
}

/// Fixture of SystemDictionaryCodecTest.
private struct CodecFixture {
  var sourceTokens: [TokenInfo] = []
  var decodedTokens: [TokenInfo] = []
  var random = Random()

  mutating func initTokens(_ size: Int) {
    for _ in 0..<size {
      var tokenInfo = TokenInfo(Token())
      tokenInfo.idInValueTrie = 0
      sourceTokens.append(tokenInfo)
    }
  }

  mutating func reset() {
    sourceTokens.removeAll()
    decodedTokens.removeAll()
  }

  mutating func setDefaultPos(_ i: Int) {
    sourceTokens[i].posType = .defaultPos
    // set id randomly
    let id = UInt16(Int.random(in: 0..<50, using: &random))
    sourceTokens[i].token.lid = id
    sourceTokens[i].token.rid = Bool.random(using: &random) ? id : id + 1
  }

  mutating func setFrequentPos(_ i: Int) {
    sourceTokens[i].posType = .frequentPos
    // set id randomly
    sourceTokens[i].idInFrequentPosMap = Int.random(in: 0..<256, using: &random)
  }

  mutating func setSamePos(_ i: Int) {
    sourceTokens[i].posType = .sameAsPrevPos
  }

  mutating func setRandPos() {
    for i in sourceTokens.indices {
      var n = Int.random(in: 0..<TokenInfo.PosType.posTypeSize, using: &random)
      if i == 0 && n == 2 {
        // First token cannot be the same pos.
        n = 0
      }
      switch n {
      case 0: setDefaultPos(i)
      case 1: setFrequentPos(i)
      default: setSamePos(i)
      }
    }
  }

  mutating func setDefaultCost(_ i: Int) {
    sourceTokens[i].costType = .defaultCost
    // set cost randomly
    sourceTokens[i].token.cost = Int.random(in: 0..<8000, using: &random)
  }

  mutating func setSmallCost(_ i: Int) {
    sourceTokens[i].costType = .canUseSmallEncoding
    // set cost randomly
    sourceTokens[i].token.cost = Int.random(in: 0..<8000, using: &random)
  }

  mutating func setRandCost() {
    for i in sourceTokens.indices {
      let n = Int.random(in: 0..<TokenInfo.CostType.costTypeSize, using: &random)
      if n == 0 {
        setDefaultCost(i)
      } else {
        setSmallCost(i)
      }
    }
  }

  mutating func setDefaultValue(_ i: Int) {
    sourceTokens[i].valueType = .defaultValue
    // set id randomly
    sourceTokens[i].idInValueTrie = Int.random(in: 0..<50000, using: &random)
  }

  mutating func setSameValue(_ i: Int) {
    sourceTokens[i].valueType = .sameAsPrevValue
  }

  mutating func setRandValue() {
    for i in sourceTokens.indices {
      var n = Int.random(in: 0..<TokenInfo.ValueType.valueTypeSize, using: &random)
      if i == 0 && n == 1 {
        // first token cannot be the same as before.
        n = 0
      }
      switch n {
      case 0: setDefaultValue(i)
      case 1: setSameValue(i)
      case 2: sourceTokens[i].valueType = .asIsHiragana
      default: sourceTokens[i].valueType = .asIsKatakana
      }
    }
  }

  mutating func setRandLabel() {
    for i in sourceTokens.indices {
      let n = Int.random(in: 0..<Int(Token.Attribute.labelSize), using: &random)
      if n == 0 {
        sourceTokens[i].token.attributes = Token.Attribute.none
      } else {
        sourceTokens[i].token.attributes = Token.Attribute.spellingCorrection
      }
    }
  }

  func checkDecoded() {
    #expect(decodedTokens.count == sourceTokens.count)
    for i in sourceTokens.indices where i < decodedTokens.count {
      let s = sourceTokens[i]
      let d = decodedTokens[i]
      #expect(s.token.attributes == d.token.attributes)

      #expect(d.posType == s.posType)
      if s.posType == .defaultPos {
        #expect(d.token.lid == s.token.lid)
        #expect(d.token.rid == s.token.rid)
      } else if s.posType == .frequentPos {
        #expect(d.idInFrequentPosMap == s.idInFrequentPosMap)
      }

      if s.costType == .defaultCost {
        #expect(d.token.cost == s.token.cost)
      } else {  // small cost
        #expect(abs(s.token.cost - d.token.cost) <= 256)
      }

      #expect(d.valueType == s.valueType)
      if s.valueType == .defaultValue {
        #expect(d.idInValueTrie == s.idInValueTrie)
      }
    }
  }

  func decodeTokens(_ codec: SystemDictionaryCodec, _ image: [UInt8]) -> [TokenInfo] {
    var tokens: [TokenInfo] = []
    var offset = 0
    image.withUnsafeBufferPointer { ptr in
      while offset < image.count {
        var readBytes = 0
        var tokenInfo = TokenInfo(Token())
        let more = codec.decodeToken(ptr.baseAddress! + offset, &tokenInfo, &readBytes)
        tokens.append(tokenInfo)
        if !more {
          break
        }
        offset += readBytes
      }
    }
    return tokens
  }

  /// Encodes `sourceTokens` and checks the decoded result.
  mutating func encodeAndCheck(_ codec: SystemDictionaryCodec) -> [UInt8] {
    let encoded = codec.encodeTokens(sourceTokens)
    #expect(encoded.count > 0)
    decodedTokens = decodeTokens(codec, encoded)
    checkDecoded()
    return encoded
  }

  func checkReadTokens(_ codec: SystemDictionaryCodec, _ encoded: [UInt8]) {
    var readNum = 0
    var offset = 0
    encoded.withUnsafeBufferPointer { ptr in
      while true {
        var readByte = 0
        var valueId = -1
        let isLastToken = !codec.readTokenForReverseLookup(ptr.baseAddress! + offset, &valueId, &readByte)
        if sourceTokens[readNum].valueType == .defaultValue {
          #expect(valueId == sourceTokens[readNum].idInValueTrie)
        } else {
          #expect(valueId == -1)
        }
        offset += readByte
        readNum += 1
        if isLastToken {
          break
        }
      }
    }
    #expect(readNum == sourceTokens.count)
  }
}

@Suite struct SystemDictionaryCodecTests {
  let codec = SystemDictionaryCodec()

  @Test func keyCodecKanaTest() {
    let original = "よみ"
    let encoded = codec.encodeKey(original)
    // hiragana should be encoded in 1 byte
    #expect(encoded.count == 2)
    #expect(codec.getEncodedKeyLength(original) == encoded.count)
    let decoded = codec.decodeKey(encoded)
    #expect(decoded == original)
    #expect(codec.getDecodedKeyLength(encoded) == decoded.utf8.count)
  }

  @Test func keyCodecSymbolTest() {
    let original = "・ー"
    let encoded = codec.encodeKey(original)
    // middle dot and prolonged sound should be encoded in 1 byte
    #expect(encoded.count == 2)
    #expect(codec.getEncodedKeyLength(original) == encoded.count)
    let decoded = codec.decodeKey(encoded)
    #expect(decoded == original)
    #expect(codec.getDecodedKeyLength(encoded) == decoded.utf8.count)
  }

  @Test func valueCodecTest() {
    // TODO(toshiyuki): Use 0x10ffff instead when UCS4 is supported.
    let kMaxUniChar: UInt32 = 0x10ffff
    var failures = 0
    for c in UInt32(0x01)...kMaxUniChar {
      let original = Util.codepointToUtf8Bytes(c)
      let encoded = codec.encodeValue(bytes: original)
      let (ok, message) = isExpectedEncodedSize(c, encoded)
      let decoded = codec.decodeValueBytes(encoded)
      if !ok || decoded != original {
        failures += 1
        if failures <= 10 {
          Issue.record("failed at: \(c) \(message)")
        }
      }
    }
    #expect(failures == 0)
  }

  @Test func valueCodecKanaTest() {
    let original = "もジ"
    let encoded = codec.encodeValue(original)
    // kana should be encoded in 1 byte
    #expect(encoded.count == 2)
    let decoded = codec.decodeValue(encoded)
    #expect(decoded == original)
  }

  @Test func valueCodecAsciiTest() {
    let original = "word"
    let encoded = codec.encodeValue(original)
    // ascii should be encoded in 2 bytes
    #expect(encoded.count == 8)
    let decoded = codec.decodeValue(encoded)
    #expect(decoded == original)
  }

  @Test func tokenDefaultPosTest() {
    var f = CodecFixture()
    f.initTokens(1)
    f.setDefaultPos(0)
    _ = f.encodeAndCheck(codec)
  }

  @Test func tokenFrequentPosTest() {
    var f = CodecFixture()
    f.initTokens(1)
    f.setFrequentPos(0)
    _ = f.encodeAndCheck(codec)
  }

  @Test func tokenSamePosTest() {
    var f = CodecFixture()
    do {
      f.initTokens(2)
      f.setDefaultPos(0)
      f.setSamePos(1)
      _ = f.encodeAndCheck(codec)
    }
    f.reset()
    do {
      f.initTokens(2)
      f.setFrequentPos(0)
      f.setSamePos(1)
      _ = f.encodeAndCheck(codec)
    }
  }

  @Test func tokenRandomPosTest() {
    var f = CodecFixture()
    f.initTokens(50)
    f.setRandPos()
    _ = f.encodeAndCheck(codec)
  }

  @Test func tokenDefaultCostTest() {
    var f = CodecFixture()
    f.initTokens(1)
    f.setDefaultCost(0)
    _ = f.encodeAndCheck(codec)
  }

  @Test func tokenSmallCostTest() {
    var f = CodecFixture()
    f.initTokens(1)
    f.setSmallCost(0)
    _ = f.encodeAndCheck(codec)
  }

  @Test func tokenRandomCostTest() {
    var f = CodecFixture()
    f.initTokens(50)
    f.setRandCost()
    _ = f.encodeAndCheck(codec)
  }

  @Test func tokenDefaultValueTest() {
    var f = CodecFixture()
    f.initTokens(1)
    f.setDefaultValue(0)
    _ = f.encodeAndCheck(codec)
  }

  @Test func ucs4CharactersTest() {
    let codepointIncluding =
      "𠀋𡈽𡌛𡑮𡢽𠮟𡚴𡸴𣇄𣗄𣜿𣝣𣳾𤟱𥒎𥔎𥝱𥧄𥶡𦫿𦹀𧃴𧚄𨉷𨏍𪆐𠂉"
      + "𠂢𠂤𠆢𠈓𠌫𠎁𠍱𠏹𠑊𠔉𠗖𠘨𠝏𠠇𠠺𠢹𠥼𠦝𠫓𠬝𠵅𠷡𠺕𠹭𠹤𠽟𡈁"
      + "𡉕𡉻𡉴𡋤𡋗𡋽𡌶𡍄𡏄𡑭𡗗𦰩𡙇𡜆𡝂𡧃𡱖𡴭𡵅𡵸𡵢𡶡𡶜𡶒𡶷𡷠𡸳"
      + "𡼞𡽶𡿺𢅻𢌞𢎭𢛳𢡛𢢫𢦏𢪸𢭏𢭐𢭆𢰝𢮦𢰤𢷡𣇃𣇵𣆶𣍲𣏓𣏒𣏐𣏤𣏕"
      + "𣏚𣏟𣑊𣑑𣑋𣑥𣓤𣕚𣖔𣘹𣙇𣘸𣘺𣜜𣜌𣝤𣟿𣟧𣠤𣠽𣪘𣱿𣴀𣵀𣷺𣷹𣷓"
      + "𣽾𤂖𤄃𤇆𤇾𤎼𤘩𤚥𤢖𤩍𤭖𤭯𤰖𤴔𤸎𤸷𤹪𤺋𥁊𥁕𥄢𥆩𥇥𥇍𥈞𥉌𥐮"
      + "𥓙𥖧𥞩𥞴𥧔𥫤𥫣𥫱𥮲𥱋𥱤𥸮𥹖𥹥𥹢𥻘𥻂𥻨𥼣𥽜𥿠𥿔𦀌𥿻𦀗𦁠𦃭"
      + "𦉰𦊆𦍌𣴎𦐂𦙾𦚰𦜝𦣝𦣪𦥑𦥯𦧝𦨞𦩘𦪌𦪷𦱳𦳝𦹥𦾔𦿸𦿶𦿷𧄍𧄹𧏛"
      + "𧏚𧏾𧐐𧑉𧘕𧘔𧘱𧚓𧜎𧜣𧝒𧦅𧪄𧮳𧮾𧯇𧲸𧶠𧸐𧾷𨂊𨂻𨊂𨋳𨐌𨑕𨕫"
      + "𨗈𨗉𨛗𨛺𨥉𨥆𨥫𨦇𨦈𨦺𨦻𨨞𨨩𨩱𨩃𨪙𨫍𨫤𨫝𨯁𨯯𨴐𨵱𨷻𨸟𨸶𨺉"
      + "𨻫𨼲𨿸𩊠𩊱𩒐𩗏𩙿𩛰𩜙𩝐𩣆𩩲𩷛𩸽𩸕𩺊𩹉𩻄𩻩𩻛𩿎𪀯𪀚𪃹𪂂𢈘"
      + "𪎌𪐷𪗱𪘂𪘚𪚲"
    let encoded = codec.encodeValue(codepointIncluding)
    #expect(encoded.count > 0)
    let decoded = codec.decodeValue(encoded)
    #expect(decoded.bytesEqual(codepointIncluding))
  }

  @Test func tokenSameValueTest() {
    var f = CodecFixture()
    f.initTokens(2)
    f.setDefaultValue(0)
    f.setSameValue(1)
    _ = f.encodeAndCheck(codec)
  }

  @Test func tokenRandomValueTest() {
    var f = CodecFixture()
    f.initTokens(50)
    f.setRandValue()
    _ = f.encodeAndCheck(codec)
  }

  @Test func tokenRandomLabelTest() {
    var f = CodecFixture()
    f.initTokens(50)
    f.setRandLabel()
    _ = f.encodeAndCheck(codec)
  }

  @Test func tokenRandomTest() {
    var f = CodecFixture()
    f.initTokens(50)
    f.setRandPos()
    f.setRandCost()
    f.setRandValue()
    f.setRandLabel()
    _ = f.encodeAndCheck(codec)
  }

  @Test func readTokenRandomTest() {
    var f = CodecFixture()
    f.initTokens(50)
    f.setRandPos()
    f.setRandCost()
    f.setRandValue()
    f.setRandLabel()
    let encoded = codec.encodeTokens(f.sourceTokens)
    #expect(encoded.count > 0)
    f.checkReadTokens(codec, encoded)
  }

  @Test func codecTest() {
    var f = CodecFixture()
    do {  // Token
      f.initTokens(50)
      f.setRandPos()
      f.setRandCost()
      f.setRandValue()
      f.setRandLabel()
      let encoded = f.encodeAndCheck(codec)

      // ReadTokens
      f.checkReadTokens(codec, encoded)
    }
    do {
      // Value
      // U+4E00-9FFF CJK Unified Ideographs
      let aCodepoint: UInt32 = 0x21  // '!'
      let original = f.random.utf8String(10000, aCodepoint, aCodepoint + 0x9f00)
      let encoded = codec.encodeValue(original)
      let decoded = codec.decodeValue(encoded)
      #expect(decoded.bytesEqual(original))
    }
    do {
      // Key
      let aCodepoint: UInt32 = 0x3041  // "ぁ"
      let original = f.random.utf8String(1000, aCodepoint, aCodepoint + 1000)
      let encoded = codec.encodeKey(original)
      #expect(codec.getEncodedKeyLength(original) == encoded.count)
      let decoded = codec.decodeKey(encoded)
      #expect(decoded.bytesEqual(original))
      #expect(codec.getDecodedKeyLength(encoded) == decoded.utf8.count)
    }
  }

  // Swift-only: byte-exact encodings of a few characters.
  @Test func byteExactEncodings() {
    #expect(codec.encodeKey("あ") == [0x02])
    #expect(codec.encodeKey("だ") == [0x40])
    #expect(codec.encodeKey("ー") == [0x77])
    #expect(codec.encodeKey("a") == Array("め".utf8))
    #expect(codec.encodeValue("あ") == [0x4c])
    #expect(codec.encodeValue("ア") == [0x9f + 1])
    #expect(codec.encodeValue("a") == [0xfc, 0x61])
    #expect(codec.encodeValue("一") == [0xfd, 0x4e])  // U+4E00 is a U+??00 character.
    #expect(codec.encodeValue("丁") == [0x01, 0x01])
    #expect(codec.encodeValue("\u{3000}") == [0xfd, 0x30])
    #expect(codec.encodeValue("\u{9fa0}") == [0xfe, 0x9f, 0xa0])
    #expect(codec.encodeValue("\u{20000}") == [0xff, 0x02 | 0x80 | 0x40])
    #expect(codec.encodeValue("\u{2000B}") == [0xff, 0x02 | 0x80, 0x0b])
  }
}
