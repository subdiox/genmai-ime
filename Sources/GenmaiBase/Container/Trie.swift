// Port of mozc/src/base/container/trie.h (3.35.6354).
//
// Trie tree library. Keys are split by UTF-8 characters (code points).
// Note: the children are kept in a `Dictionary` like the C++
// `absl::flat_hash_map`, so the order of `lookUpPredictiveAll` results is
// unspecified (as in C++).

public final class Trie<T> {
  private var trie: [Char32: Trie<T>] = [:]
  private var data: T?

  public init() {}

  public func addEntry(_ key: some StringProtocol, _ data: T) {
    addEntry(Strings.toSubstring(key), data)
  }

  private func addEntry(_ key: Substring, _ data: T) {
    if key.isEmpty {
      self.data = data
      return
    }
    let res = findSubTrie(key)
    let subTrie: Trie<T>
    if let t = res.trie {
      subTrie = t
    } else {
      subTrie = Trie<T>()
      trie[res.firstChar] = subTrie
    }
    subTrie.addEntry(res.rest, data)
  }

  /// Returns true if this node became empty (and may be removed).
  @discardableResult
  public func deleteEntry(_ key: some StringProtocol) -> Bool {
    deleteEntry(Strings.toSubstring(key))
  }

  private func deleteEntry(_ key: Substring) -> Bool {
    if key.isEmpty {
      if trie.isEmpty {
        return true
      }
      data = nil
      return false
    }
    let res = findSubTrie(key)
    if let sub = res.trie, sub.deleteEntry(res.rest) {
      trie.removeValue(forKey: res.firstChar)
      return trie.isEmpty
    }
    return false
  }

  /// Returns the data of the exact `key`.
  public func lookUp(_ key: some StringProtocol) -> T? {
    lookUp(Strings.toSubstring(key))
  }

  private func lookUp(_ key: Substring) -> T? {
    if key.isEmpty {
      return data
    }
    let res = findSubTrie(key)
    return res.trie?.lookUp(res.rest)
  }

  /// If key's prefix matches to trie with data, return true and set data
  /// For example, if a trie has data for 'abc', 'abd', and 'a';
  ///  - Return true for the key, 'abc'
  ///  -- Matches in exact
  ///  - Return true for the key, 'abcd'
  ///  -- Matches in prefix
  ///  - Return FALSE for the key, 'abe'
  ///  -- Matches in prefix by 'ab', and 'ab' does not have data in trie tree
  ///  -- Do not refer 'a' here.
  ///  - Return true for the key, 'ac'
  ///  -- Matches in prefix by 'a', and 'a' have data
  /// `keyLength` is in bytes. `data` is set only when found.
  public func lookUpPrefix(
    _ key: some StringProtocol, _ data: inout T?, _ keyLength: inout Int, _ fixed: inout Bool
  ) -> Bool {
    lookUpPrefix(Strings.toSubstring(key), &data, &keyLength, &fixed)
  }

  private func lookUpPrefix(
    _ key: Substring, _ data: inout T?, _ keyLength: inout Int, _ fixed: inout Bool
  ) -> Bool {
    let res = findSubTrie(key)
    guard let sub = res.trie else {
      keyLength = 0
      if let d = self.data {
        data = d
        fixed = trie.isEmpty
        return true
      }
      fixed = true
      return false
    }
    let found = sub.lookUpPrefix(res.rest, &data, &keyLength, &fixed)
    let firstCharLen = key.utf8.count - res.rest.utf8.count
    keyLength += firstCharLen
    return found
  }

  /// If key's prefix matches to trie with data, return true and set data
  /// For example, if a trie has data for 'abc', 'abd', and 'a';
  ///  - Return true for the key, 'abc'
  ///  -- Matches in exact
  ///  - Return true for the key, 'abcd'
  ///  -- Matches in prefix
  ///  - Return TRUE for the key, 'abe'
  ///  -- Matches in prefix by 'a'.
  ///  - Return true for the key, 'ac'
  ///  -- Matches in prefix by 'a', and 'a' have data
  /// `keyLength` is in bytes.
  public func longestMatch(_ key: some StringProtocol, _ data: inout T?, _ keyLength: inout Int)
    -> Bool
  {
    longestMatch(Strings.toSubstring(key), &data, &keyLength)
  }

  private func longestMatch(_ key: Substring, _ data: inout T?, _ keyLength: inout Int) -> Bool {
    let res = findSubTrie(key)
    guard let sub = res.trie else {
      keyLength = 0
      if let d = self.data {
        data = d
        return true
      }
      return false
    }

    var found = false
    if let d = self.data {
      data = d
      found = true
    }

    if sub.longestMatch(res.rest, &data, &keyLength) {
      let firstCharLen = key.utf8.count - res.rest.utf8.count
      keyLength += firstCharLen
      return true
    }
    return found
  }

  /// Return all result starts with key
  /// For example, if a trie has data for 'abc', 'abd', and 'a';
  ///  - Return 'abc', 'abd', 'a', for the key 'a'
  ///  - Return 'abc', 'abd' for the key 'ab'
  ///  - Return nothing for the key 'b'
  public func lookUpPredictiveAll(_ key: some StringProtocol, _ dataList: inout [T]) {
    lookUpPredictiveAll(Strings.toSubstring(key), &dataList)
  }

  private func lookUpPredictiveAll(_ key: Substring, _ dataList: inout [T]) {
    if !key.isEmpty {
      let res = findSubTrie(key)
      if let sub = res.trie {
        sub.lookUpPredictiveAll(res.rest, &dataList)
      }
      return
    }

    if let d = data {
      dataList.append(d)
    }

    for (_, sub) in trie {
      sub.lookUpPredictiveAll(Substring(), &dataList)
    }
  }

  public func hasSubTrie(_ key: some StringProtocol) -> Bool {
    hasSubTrie(Strings.toSubstring(key))
  }

  private func hasSubTrie(_ key: Substring) -> Bool {
    let res = findSubTrie(key)
    guard let sub = res.trie else {
      return false
    }
    return res.rest.isEmpty || sub.hasSubTrie(res.rest)
  }

  public func swap(_ other: Trie<T>) {
    Swift.swap(&trie, &other.trie)
    Swift.swap(&data, &other.data)
  }

  private struct FindResult {
    var trie: Trie<T>?
    var firstChar: Char32 = 0
    var rest = Substring()
  }

  // Finds the subtrie that is reachable by the first UTF8 character of `key`.
  // If `key` is empty or no such trie exists, `FindResult::trie` is set to
  // nullptr. If `key` is nonempty, this method also sets the value of char32
  // for the first character and the rest of strings regardless of the find
  // result.
  private func findSubTrie(_ key: Substring) -> FindResult {
    var res = FindResult()
    if let first = key.unicodeScalars.first {
      res.firstChar = first.value
      res.rest = key[key.unicodeScalars.index(after: key.startIndex)...]
      res.trie = trie[res.firstChar]
    }
    return res
  }
}
