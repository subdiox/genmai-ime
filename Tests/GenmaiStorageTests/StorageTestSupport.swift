// Test helpers for GenmaiStorageTests (not a port of a C++ file).

/// The UTF-8 bytes of `s`.
func bytes(_ s: some StringProtocol) -> [UInt8] {
  Array(s.utf8)
}
