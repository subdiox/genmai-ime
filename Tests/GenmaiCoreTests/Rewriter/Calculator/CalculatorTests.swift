// Port of mozc/src/rewriter/calculator/calculator_test.cc (3.35.6354).

import Foundation
import Testing
@testable import GenmaiCore

@Suite struct CalculatorTests {
  /// EXPECT_DOUBLE_EQ: within 4 ULPs.
  private static func doubleEq(_ a: Double, _ b: Double) -> Bool {
    if a == b { return true }
    if a.isNaN || b.isNaN { return false }
    func biased(_ x: Double) -> UInt64 {
      let bits = x.bitPattern
      let sign: UInt64 = 1 << 63
      return bits & sign != 0 ? ~bits &+ 1 : bits | sign
    }
    let ba = biased(a)
    let bb = biased(b)
    return (ba >= bb ? ba - bb : bb - ba) <= 4
  }

  /// Runs calculation with |expression| and compares the result and |expected|.
  private static func verifyCalculation(
    _ calculator: Calculator, _ expression: String, _ expected: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let result = calculator.calculateString(expression)
    #expect(result != nil, "\(expression)  expected = \(expected)", sourceLocation: sourceLocation)
    guard let result else { return }
    let resultVal = Double(result)
    let expectedVal = Double(expected)
    #expect(resultVal != nil, sourceLocation: sourceLocation)
    #expect(expectedVal != nil, sourceLocation: sourceLocation)
    guard let resultVal, let expectedVal else { return }
    #expect(
      doubleEq(expectedVal, resultVal),
      "comparison: \(resultVal) vs \(expectedVal), expr = \(expression), result = \(result)",
      sourceLocation: sourceLocation)
  }

  /// Runs calculation and compare results in PRINTED string.
  private static func verifyCalculationInString(
    _ calculator: Calculator, _ expression: String, _ expected: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      calculator.calculateString(expression) == expected, "expr = \(expression)",
      sourceLocation: sourceLocation)
  }

  /// Tries to calculate |wrong_key| and expects it fails.
  private static func verifyRejection(
    _ calculator: Calculator, _ wrongKey: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      calculator.calculateString(wrongKey) == nil, "expression: \(wrongKey)",
      sourceLocation: sourceLocation)
  }

  @Test func basicTest() {
    let calculator = Calculator()

    // These are not expressions
    // apparently
    Self.verifyRejection(calculator, "test")
    // Expression must be ended with equal '='.
    Self.verifyRejection(calculator, "5+4")
    // Expression must include at least one operator other than parentheses.
    Self.verifyRejection(calculator, "111=")
    Self.verifyRejection(calculator, "(5)=")
    // Expression must include at least one number.
    Self.verifyRejection(calculator, "()=")
    // Expression with both heading and tailing '='s should be rejected.
    Self.verifyRejection(calculator, "=(0-0)=")

    // Test for each operators
    Self.verifyCalculation(calculator, "38+2.5=", "40.5")
    Self.verifyCalculation(calculator, "5.5-21=", "-15.5")
    Self.verifyCalculation(calculator, "4*2.1=", "8.4")
    Self.verifyCalculation(calculator, "8/2=", "4")
    Self.verifyCalculation(calculator, "15・3=", "5")
    Self.verifyCalculation(calculator, "100%6=", "4")
    Self.verifyCalculation(calculator, "2^10=", "1024")
    Self.verifyCalculation(calculator, "4*-2=", "-8")
    Self.verifyCalculation(calculator, "-10.3+3.5=", "-6.8")
    // Expression can starts with '=' instead of ending with '='.
    Self.verifyCalculation(calculator, "=-10.3+3.5", "-6.8")

    // Full width cases (some operators may appear as full width character).
    Self.verifyCalculation(calculator, "１２３４５＋６７８９０＝", "80235")
    Self.verifyCalculation(calculator, "5−1=", "4")  // − is U+2212
    Self.verifyCalculation(calculator, "-ー3+5=", "8")  // ー is U+30FC
    Self.verifyCalculation(calculator, "1．5＊2=", "3")
    Self.verifyCalculation(calculator, "10／2=", "5")
    Self.verifyCalculation(calculator, "2＾ー2=", "0.25")
    Self.verifyCalculation(calculator, "13％3=", "1")
    Self.verifyCalculation(calculator, "（1+1）*2=", "4")

    // Expressions with more than one operator.
    Self.verifyCalculation(calculator, "(1+2)-4=", "-1")
    Self.verifyCalculation(calculator, "5*(2+3)=", "25")
    Self.verifyCalculation(calculator, "(70-((3+2)*4))%8=", "2")

    // Issue 3082576: 7472.4 - 7465.6 = 6.7999999999993 is not expected.
    Self.verifyCalculationInString(calculator, "7472.4-7465.6=", "6.8")

    // Additional coverage for syntax errors and invalid token sequences.
    Self.verifyRejection(calculator, "++=")
    Self.verifyRejection(calculator, "(1+)=")
    Self.verifyRejection(calculator, "+=")

    // Full-width and half-width space mix cases.
    Self.verifyCalculation(calculator, "1 ＋　1=", "2")

    // Overflow and extreme values.
    Self.verifyRejection(calculator, "1e1000=")

    // Mathematical functions support.
    Self.verifyCalculation(calculator, "log(10)=", "1")
    Self.verifyCalculation(calculator, "ln(1)=", "0")
    Self.verifyCalculation(calculator, "sin(0)=", "0")
    Self.verifyCalculation(calculator, "cos(0)=", "1")
    Self.verifyCalculation(calculator, "abs(-4.5)=", "4.5")
    Self.verifyCalculation(calculator, "sqrt(16)=", "4")

    // Complex function combinations, floating-point args.
    Self.verifyCalculation(calculator, "sin(3.141592653589793/2)=", "1")
    Self.verifyCalculation(calculator, "log(2*50)=", "2")
    Self.verifyCalculation(calculator, "sqrt(abs(-16))=", "4")
    Self.verifyCalculation(calculator, "1+log(10)=", "2")
    Self.verifyCalculation(calculator, "2*sin(0)+10=", "10")
    Self.verifyCalculation(calculator, "(1+log(10))*3=", "6")

    // Negative test cases.
    Self.verifyRejection(calculator, "sqrt(-1)=")
    Self.verifyRejection(calculator, "log(1+)=")
    Self.verifyRejection(calculator, "sin(3=")
  }

  /// Vendor/mozc/src/data/test/calculator/testset.txt.
  private static var testsetPath: String {
    var url = URL(fileURLWithPath: #filePath)
    // Tests/GenmaiCoreTests/Rewriter/Calculator/CalculatorTests.swift -> root.
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url.appendingPathComponent("Vendor/mozc/src/data/test/calculator/testset.txt").path
  }

  // Test large number of queries.  Test data is located at
  // data/test/calculator/testset.txt.
  // In this file, each test case is written in one line in the format
  // "expression=answer".  Answer is suppressed if the expression is invalid,
  // i.e. it is a false test.
  @Test func stressTest() throws {
    let calculator = Calculator()
    let contents = try String(contentsOfFile: Self.testsetPath, encoding: .utf8)
    var lineno = 0
    for lineSub in contents.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(lineSub)
      if line.isEmpty && lineno > 0 { continue }  // trailing newline
      lineno += 1

      // |line| is of format "expression=answer".
      let bytes = Array(line.utf8)
      guard let indexOfEqual = bytes.firstIndex(of: UInt8(ascii: "=")) else {
        Issue.record("no '=' in line \(lineno)")
        continue
      }
      let queryLength = indexOfEqual + 1
      let query = String(decoding: bytes[0..<queryLength], as: UTF8.self)

      // Smoke test.
      _ = calculator.calculateString(query)
      if bytes.count == queryLength {
        // False test
        Self.verifyRejection(calculator, line)
        continue
      }
      let answer = String(decoding: bytes[queryLength...], as: UTF8.self)
      Self.verifyCalculation(calculator, query, answer)
    }
    #expect(lineno == 5000)
  }

  @Test func limitAndValidationTest() {
    let calculator = Calculator()

    // Large but valid operations under limit (e.g. 100 unary operations).
    let validCase = String(repeating: "+", count: 100) + "1="
    #expect(calculator.calculateString(validCase) != nil)

    // Directly violating input length limit (e.g. 2100 bytes).
    let overLengthCase = String(repeating: "+", count: 2100) + "1="
    #expect(calculator.calculateString(overLengthCase) == nil)
  }
}
