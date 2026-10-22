// Byte-level BPE tokenizer (GPT-2 style) read from a Hugging Face `tokenizer.json`.
//
// Reproduces the ids of the HF tokenizers pipeline used by the genmai model (subdiox/genmai):
//   added (special) tokens split out of the text  ->  ByteLevel pre-tokenizer (GPT-2 regex, add_prefix_space
//   false)  ->  byte-to-unicode mapping  ->  BPE merges (lowest rank first, leftmost on ties; characters missing
//   from the vocabulary are dropped, since the model has no unk token / byte fallback)  ->  ids.
// Decoding is the ByteLevel decoder (unicode -> bytes, lossy UTF-8) with special tokens skipped.
// GenmaiAITests compares it against ids produced by the Python tokenizer (Tests/Fixtures/genmai).

import Foundation

public struct GenmaiTokenizer: Sendable {
  public enum LoadError: Error, CustomStringConvertible {
    case malformed(String)

    public var description: String {
      switch self {
      case .malformed(let s): "malformed tokenizer.json: \(s)"
      }
    }
  }

  private struct AddedToken: Sendable {
    let content: [Unicode.Scalar]
    let id: Int32
    let special: Bool
  }

  private struct MergeKey: Hashable, Sendable {
    let a: Int32
    let b: Int32
  }

  private let vocab: [String: Int32]
  private let idToToken: [Int32: String]
  /// (left id, right id) -> (rank, merged id).
  private let merges: [MergeKey: (rank: Int32, id: Int32)]
  private let added: [AddedToken]
  private let specialIDs: Set<Int32>
  private let byteToChar: [Character]
  private let charToByte: [Character: UInt8]

  public let bosTokenID: Int32
  public let eosTokenID: Int32

  public init(url: URL, bosToken: String = "<s>", eosToken: String = "</s>") throws {
    let data = try Data(contentsOf: url)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let model = root["model"] as? [String: Any],
      let vocabAny = model["vocab"] as? [String: Any],
      let mergesAny = model["merges"] as? [Any]
    else { throw LoadError.malformed("missing model.vocab / model.merges") }
    if let type = model["type"] as? String, type != "BPE" { throw LoadError.malformed("model type \(type)") }

    var vocab: [String: Int32] = [:]
    for (k, v) in vocabAny {
      guard let n = v as? NSNumber else { throw LoadError.malformed("vocab value for \(k)") }
      vocab[k] = n.int32Value
    }
    var added: [AddedToken] = []
    var specialIDs = Set<Int32>()
    for case let t as [String: Any] in (root["added_tokens"] as? [Any]) ?? [] {
      guard let content = t["content"] as? String, let id = (t["id"] as? NSNumber)?.int32Value else { continue }
      let special = (t["special"] as? Bool) ?? false
      added.append(AddedToken(content: Array(content.unicodeScalars), id: id, special: special))
      if special { specialIDs.insert(id) }
      vocab[content] = vocab[content] ?? id
    }
    // leftmost-longest matching of added tokens
    added.sort { $0.content.count > $1.content.count }

    var merges: [MergeKey: (rank: Int32, id: Int32)] = [:]
    for (rank, m) in mergesAny.enumerated() {
      let a: String
      let b: String
      if let pair = m as? [String], pair.count == 2 {
        (a, b) = (pair[0], pair[1])
      } else if let s = m as? String, let sp = s.firstIndex(of: " ") {
        (a, b) = (String(s[..<sp]), String(s[s.index(after: sp)...]))
      } else {
        throw LoadError.malformed("merge \(rank)")
      }
      guard let ia = vocab[a], let ib = vocab[b], let im = vocab[a + b] else { continue }
      let key = MergeKey(a: ia, b: ib)
      if merges[key] == nil { merges[key] = (Int32(rank), im) }
    }

    var idToToken: [Int32: String] = [:]
    for (k, v) in vocab { idToToken[v] = k }

    // GPT-2 bytes_to_unicode
    var bs: [Int] = Array(33...126) + Array(161...172) + Array(174...255)
    var cs = bs
    var n = 0
    for b in 0..<256 where !bs.contains(b) {
      bs.append(b)
      cs.append(256 + n)
      n += 1
    }
    var byteToChar = [Character](repeating: " ", count: 256)
    var charToByte: [Character: UInt8] = [:]
    for (b, c) in zip(bs, cs) {
      guard let scalar = Unicode.Scalar(UInt32(c)) else { throw LoadError.malformed("byte map \(c)") }
      let ch = Character(scalar)
      byteToChar[b] = ch
      charToByte[ch] = UInt8(b)
    }

    guard let bos = vocab[bosToken], let eos = vocab[eosToken] else {
      throw LoadError.malformed("bos/eos tokens \(bosToken) \(eosToken)")
    }
    self.vocab = vocab
    self.idToToken = idToToken
    self.merges = merges
    self.added = added
    self.specialIDs = specialIDs
    self.byteToChar = byteToChar
    self.charToByte = charToByte
    self.bosTokenID = bos
    self.eosTokenID = eos
  }

  // MARK: - Encoding

  /// `tokenizer.encode(text, add_special_tokens=False)`.
  public func encode(_ text: String) -> [Int32] {
    let scalars = Array(text.unicodeScalars)
    var ids: [Int32] = []
    var segStart = 0
    var i = 0
    while i < scalars.count {
      if let tok = matchAdded(scalars, at: i) {
        encodeSegment(scalars[segStart..<i], into: &ids)
        ids.append(tok.id)
        i += tok.content.count
        segStart = i
      } else {
        i += 1
      }
    }
    encodeSegment(scalars[segStart..<scalars.count], into: &ids)
    return ids
  }

  private func matchAdded(_ s: [Unicode.Scalar], at i: Int) -> AddedToken? {
    for t in added where i + t.content.count <= s.count {
      var ok = true
      for (j, c) in t.content.enumerated() where s[i + j] != c {
        ok = false
        break
      }
      if ok { return t }
    }
    return nil
  }

  private func encodeSegment(_ s: ArraySlice<Unicode.Scalar>, into ids: inout [Int32]) {
    guard !s.isEmpty else { return }
    for word in Self.preTokenize(Array(s)) {
      var mapped: [String] = []
      for scalar in word {
        for b in String(String.UnicodeScalarView([scalar])).utf8 {
          mapped.append(String(byteToChar[Int(b)]))
        }
      }
      bpe(mapped, into: &ids)
    }
  }

  private enum Cls { case letter, number, space, other }

  private static func cls(_ c: Unicode.Scalar) -> Cls {
    if c.properties.isWhitespace { return .space }
    switch c.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return .letter
    case .decimalNumber, .letterNumber, .otherNumber: return .number
    default: return .other
    }
  }

  /// The GPT-2 pattern `'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+`
  /// (leftmost-first alternation), as a hand-written scanner over Unicode scalars.
  static func preTokenize(_ s: [Unicode.Scalar]) -> [ArraySlice<Unicode.Scalar>] {
    var out: [ArraySlice<Unicode.Scalar>] = []
    let n = s.count
    let k = s.map(cls)
    var i = 0
    func run(_ from: Int, _ c: Cls) -> Int {
      var j = from
      while j < n && k[j] == c { j += 1 }
      return j
    }
    while i < n {
      // contractions
      if s[i] == "'" && i + 1 < n {
        let c1 = s[i + 1]
        if c1 == "s" || c1 == "t" || c1 == "m" || c1 == "d" {
          out.append(s[i..<i + 2])
          i += 2
          continue
        }
        if i + 2 < n {
          let c2 = s[i + 2]
          if (c1 == "r" && c2 == "e") || (c1 == "v" && c2 == "e") || (c1 == "l" && c2 == "l") {
            out.append(s[i..<i + 3])
            i += 3
            continue
          }
        }
      }
      // optional ' ' + letters / numbers / others
      let hasSpace = s[i] == " " && i + 1 < n
      let first = hasSpace ? i + 1 : i
      if first < n && k[first] != .space && (hasSpace || s[i] != " ") {
        let j = run(first, k[first])
        out.append(s[i..<j])
        i = j
        continue
      }
      // whitespace
      let j = run(i, .space)
      if j < n && j - i >= 2 {
        // \s+(?!\S): leave the last whitespace for the next token
        out.append(s[i..<j - 1])
        i = j - 1
      } else {
        // \s+ (either up to the end, or a single whitespace before a non-space)
        out.append(s[i..<j])
        i = j
      }
    }
    return out
  }

  private func bpe(_ chars: [String], into ids: inout [Int32]) {
    // symbols for characters in the vocabulary (others are dropped: no unk token, no byte fallback)
    var sym: [Int32] = chars.compactMap { vocab[$0] }
    guard sym.count > 1 else {
      ids.append(contentsOf: sym)
      return
    }
    let n = sym.count
    var prev = Array(-1..<(n - 1))
    var next = Array(1...n)
    next[n - 1] = -1
    var alive = [Bool](repeating: true, count: n)
    var heap = MergeHeap()
    for p in 0..<(n - 1) {
      if let m = merges[MergeKey(a: sym[p], b: sym[p + 1])] {
        heap.push(.init(rank: m.rank, pos: p, left: sym[p], right: sym[p + 1]))
      }
    }
    while let top = heap.pop() {
      let p = top.pos
      guard alive[p], sym[p] == top.left else { continue }
      let q = next[p]
      guard q >= 0, sym[q] == top.right, let m = merges[MergeKey(a: sym[p], b: sym[q])], m.rank == top.rank
      else { continue }
      sym[p] = m.id
      alive[q] = false
      let r = next[q]
      next[p] = r
      if r >= 0 { prev[r] = p }
      if prev[p] >= 0, let m2 = merges[MergeKey(a: sym[prev[p]], b: sym[p])] {
        heap.push(.init(rank: m2.rank, pos: prev[p], left: sym[prev[p]], right: sym[p]))
      }
      if r >= 0, let m2 = merges[MergeKey(a: sym[p], b: sym[r])] {
        heap.push(.init(rank: m2.rank, pos: p, left: sym[p], right: sym[r]))
      }
    }
    var p = 0
    while p >= 0 {
      ids.append(sym[p])
      p = next[p]
    }
  }

  // MARK: - Decoding

  /// `tokenizer.decode(ids, skip_special_tokens=True)`.
  public func decode(_ ids: [Int32]) -> String {
    var bytes: [UInt8] = []
    for id in ids where !specialIDs.contains(id) {
      guard let t = idToToken[id] else { continue }
      for ch in t {
        if let b = charToByte[ch] {
          bytes.append(b)
        } else {
          bytes.append(contentsOf: Array(String(ch).utf8))
        }
      }
    }
    return String(decoding: bytes, as: UTF8.self)
  }
}

/// Binary min-heap ordered by (rank, position), like the priority queue of tokenizers' `Word::merge_all`.
private struct MergeHeap {
  struct Entry {
    let rank: Int32
    let pos: Int
    let left: Int32
    let right: Int32

    func less(_ o: Entry) -> Bool { rank != o.rank ? rank < o.rank : pos < o.pos }
  }

  private var a: [Entry] = []

  mutating func push(_ e: Entry) {
    a.append(e)
    var i = a.count - 1
    while i > 0 {
      let p = (i - 1) / 2
      guard a[i].less(a[p]) else { break }
      a.swapAt(i, p)
      i = p
    }
  }

  mutating func pop() -> Entry? {
    guard let top = a.first else { return nil }
    let last = a.removeLast()
    if !a.isEmpty {
      a[0] = last
      var i = 0
      while true {
        let l = 2 * i + 1
        let r = l + 1
        var m = i
        if l < a.count && a[l].less(a[m]) { m = l }
        if r < a.count && a[r].less(a[m]) { m = r }
        if m == i { break }
        a.swapAt(i, m)
        i = m
      }
    }
    return top
  }
}
