// Port of mozc/src/rewriter/calculator/calculator.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The tokenizer works on the UTF-8 bytes of the expression (as the C++
//   string_view code does); `operator_map_` is keyed by byte arrays.
// - `absl::StrFormat("%.8g", ...)` is `String(format: "%.8g", ...)`.

import Foundation
import GenmaiBase

public final class Calculator: Sendable {
  /// Represents the type of calculation token.
  public enum TokenType: Int, Sendable {
    case plus = 1  // "+"
    case minus  // "-"
    case times  // "*"
    case divide  // "/"
    case mod  // "%"
    case pow  // "^"
    case lp  // "("
    case rp  // ")"
    case integer  // Numbers (e.g. "123", "45.6")
    case funcLog  // "log" (base 10)
    case funcLn  // "ln" (natural logarithm)
    case funcExp  // "exp"
    case funcSqrt  // "sqrt"
    case funcSin  // "sin"
    case funcCos  // "cos"
    case funcTan  // "tan"
    case funcAbs  // "abs"
  }

  /// Represents a token in the expression.
  public struct Token: Sendable {
    public var type: TokenType
    public var value: Double
  }

  typealias TokenSequence = [Token]

  /// Max byte length of operator character
  private static let kMaxLengthOfOperator = 4

  /// Mapping from operator character such as '+' or "log" to the
  /// corresponding token type.
  private let operatorMap: [[UInt8]: TokenType]

  public init() {
    var m: [[UInt8]: TokenType] = [:]
    func set(_ s: String, _ t: TokenType) { m[Array(s.utf8)] = t }
    set("+", .plus)
    set("-", .minus)
    // "ー". It is called cho-ompu, onbiki, bobiki, or "nobashi-bou" casually.
    // It is not a full-width hyphen, and may appear in conversion segments by
    // typing '-' more than one time continuously.
    set("ー", .minus)
    set("*", .times)
    set("/", .divide)
    set("・", .divide)  // "･". Consider it as "/".
    set("%", .mod)
    set("^", .pow)
    set("(", .lp)
    set(")", .rp)
    set("log", .funcLog)
    set("ln", .funcLn)
    set("exp", .funcExp)
    set("sqrt", .funcSqrt)
    set("sin", .funcSin)
    set("cos", .funcCos)
    set("tan", .funcTan)
    set("abs", .funcAbs)
    operatorMap = m
  }

  public func calculateString(_ key: some StringProtocol) -> String? {
    if key.utf8.isEmpty || key.utf8.count > kMaxInputLength {
      // LOG(ERROR) << "Key is empty or too long.";
      return nil
    }
    let normalizedKey = Array(Japanese.fullWidthAsciiToHalfWidthAscii(key).utf8)
    let eq = UInt8(ascii: "=")

    if normalizedKey.first == eq && normalizedKey.last == eq {
      return nil
    }
    var expressionBody = normalizedKey[...]
    if expressionBody.first == eq {
      expressionBody = expressionBody.dropFirst()
    } else if expressionBody.last == eq {
      expressionBody = expressionBody.dropLast()
    } else {
      return nil
    }

    guard let tokens = tokenize(expressionBody) else {
      // normalized_key is not valid sequence of tokens
      return nil
    }

    guard let resultValue = calculateTokens(tokens) else {
      // Calculation is failed. Syntax error or arithmetic error such as
      // overflow, divide-by-zero, etc.
      return nil
    }
    return String(format: "%.8g", resultValue)
  }

  /// Tokenizes |expression_body| and returns the tokens if the tokenization
  /// is successful.
  /// It returns nil if |expression_body| includes an invalid token or
  /// does not include both of a number token and an operator token.
  /// Parenthesis is not considered as an operator.
  func tokenize(_ expressionBody: ArraySlice<UInt8>) -> TokenSequence? {
    var numOperator = 0  // Number of operators or functions appeared
    var numValue = 0  // Number of values appeared

    var tokens: TokenSequence = []
    var rest = expressionBody

    func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
    func isAlpha(_ b: UInt8) -> Bool { (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) }

    while !rest.isEmpty {
      // Skip spaces
      while let f = rest.first, f == 0x20 || f == 0x09 {
        rest = rest.dropFirst()
      }
      if rest.isEmpty {
        break
      }

      // Read value token
      var valueLen = 0
      while valueLen < rest.count {
        let b = rest[rest.startIndex + valueLen]
        if !(isDigit(b) || b == UInt8(ascii: ".")) { break }
        valueLen += 1
      }
      if valueLen > 0 {
        let numberToken = String(decoding: rest.prefix(valueLen), as: UTF8.self)
        guard let value = NumberUtil.safeStrToDouble(numberToken) else {
          return nil
        }
        tokens.append(Token(type: .integer, value: value))
        numValue += 1
        rest = rest.dropFirst(valueLen)
        continue
      }

      // Read alphabetical function name token
      if let first = rest.first, isAlpha(first) {
        var funcLen = 0
        while funcLen < rest.count && isAlpha(rest[rest.startIndex + funcLen]) {
          funcLen += 1
        }
        let name = rest.prefix(funcLen).map { b -> UInt8 in
          (b >= 0x41 && b <= 0x5A) ? b + 0x20 : b
        }
        if let t = operatorMap[name] {
          tokens.append(Token(type: t, value: 0.0))
          rest = rest.dropFirst(funcLen)
          numOperator += 1
          continue
        }
        return nil
      }

      // Read operator token
      var matchedOperator = false
      for length in 1...Calculator.kMaxLengthOfOperator {
        if length > rest.count {
          break
        }
        let window = Array(rest.prefix(length))
        guard let op = operatorMap[window] else {
          continue
        }
        tokens.append(Token(type: op, value: 0.0))
        rest = rest.dropFirst(length)
        matchedOperator = true
        // Does not count parenthesis as an operator.
        if op != .lp && op != .rp {
          numOperator += 1
        }
        break
      }
      if matchedOperator {
        continue
      }

      // Invalid token
      return nil
    }

    if numOperator == 0 || numValue == 0 {
      // Must contain at least one operator and one value.
      return nil
    }
    return tokens
  }

  /// Perform calculation with a given sequence of token.
  func calculateTokens(_ tokens: TokenSequence) -> Double? {
    var ctx = ParserContext(tokens: tokens)
    guard let result = parseExpression(&ctx) else {
      return nil
    }
    if ctx.pos != ctx.tokens.count {
      return nil
    }
    return result
  }
}

// Security and performance limits for the calculator.
// Set to 2048 bytes and 256 operations to pass the existing stress test suite
// which contains extremely long and complex automatically generated
// expressions.
private let kMaxInputLength = 2048
private let kMaxOperations = 256

// Context holding the current state of parsing.
// It groups the tokens array and the processing index to simplify arguments.
private struct ParserContext {
  let tokens: [Calculator.Token]
  var pos = 0
  var operationCount = 0
}

// Detailed Grammar & Association Rules:
//
// -----------------------------------------------------------------------------
// 1. Precedence (from lowest to highest):
//    Expression : '+' | '-'               (Left-associative)
//    Term       : '*' | '/' | '%'         (Left-associative)
//    Factor     : '^'                     (Right-associative)
//    Unary      : '+' | '-'               (Prefix, right-associative)
//    Primary    : Integer | Function | '(' Expression ')'
//
// -----------------------------------------------------------------------------
// 2. Behavior of right-associativity vs left-associativity:
//    - '+' and '-' (binary) are parsed using loop evaluation:
//        A + B + C is processed as (A + B) + C.
//    - '^' is right-associative:
//        A ^ B ^ C is processed as A ^ (B ^ C) via direct recursive calls.
//
// -----------------------------------------------------------------------------
// 3. Mutual Recursion:
//    - ParsePrimary handles parentheses '( Expression )' and functions.
//    - Recursive calls are guarded by the operation count limit
//      (kMaxOperations) to prevent stack overflow.
// -----------------------------------------------------------------------------

private func parsePrimary(_ ctx: inout ParserContext) -> Double? {
  ctx.operationCount += 1
  if ctx.operationCount > kMaxOperations {
    return nil
  }
  if ctx.pos >= ctx.tokens.count {
    return nil
  }
  if ctx.tokens[ctx.pos].type == .integer {
    let val = ctx.tokens[ctx.pos].value
    ctx.pos += 1
    return val
  }
  if ctx.tokens[ctx.pos].type == .lp {
    ctx.pos += 1
    guard let val = parseExpression(&ctx) else {
      return nil
    }
    if ctx.pos >= ctx.tokens.count || ctx.tokens[ctx.pos].type != .rp {
      return nil
    }
    ctx.pos += 1
    return val
  }

  // Handle mathematical functions (e.g. log, sin, cos)
  let type = ctx.tokens[ctx.pos].type
  switch type {
  case .funcLog, .funcLn, .funcExp, .funcSqrt, .funcSin, .funcCos, .funcTan, .funcAbs:
    ctx.pos += 1
    // Require left parenthesis '('
    if ctx.pos >= ctx.tokens.count || ctx.tokens[ctx.pos].type != .lp {
      return nil
    }
    ctx.pos += 1
    guard let arg = parseExpression(&ctx) else {
      return nil
    }
    // Require right parenthesis ')'
    if ctx.pos >= ctx.tokens.count || ctx.tokens[ctx.pos].type != .rp {
      return nil
    }
    ctx.pos += 1

    switch type {
    case .funcLog: return Foundation.log10(arg)
    case .funcLn: return Foundation.log(arg)
    case .funcExp: return Foundation.exp(arg)
    case .funcSqrt:
      if arg < 0.0 {
        return nil
      }
      return arg.squareRoot()
    case .funcSin: return Foundation.sin(arg)
    case .funcCos: return Foundation.cos(arg)
    case .funcTan: return Foundation.tan(arg)
    case .funcAbs: return Swift.abs(arg)
    default:
      assertionFailure("Unreachable function type in ParsePrimary")
      return nil
    }
  default:
    return nil
  }
}

private func parseUnary(_ ctx: inout ParserContext) -> Double? {
  ctx.operationCount += 1
  if ctx.operationCount > kMaxOperations {
    return nil
  }
  if ctx.pos >= ctx.tokens.count {
    return nil
  }
  let op = ctx.tokens[ctx.pos].type
  if op == .plus {
    ctx.pos += 1
    return parseUnary(&ctx)
  }
  if op == .minus {
    ctx.pos += 1
    guard let rhs = parseUnary(&ctx) else {
      return nil
    }
    return -rhs
  }
  return parsePrimary(&ctx)
}

private func parseFactor(_ ctx: inout ParserContext) -> Double? {
  ctx.operationCount += 1
  if ctx.operationCount > kMaxOperations {
    return nil
  }
  guard var val = parseUnary(&ctx) else {
    return nil
  }
  // POW is right-associative: call ParseFactor recursively for the right side.
  if ctx.pos < ctx.tokens.count && ctx.tokens[ctx.pos].type == .pow {
    ctx.pos += 1
    guard let rhs = parseFactor(&ctx) else {
      return nil
    }
    val = Foundation.pow(val, rhs)
    if !val.isFinite {
      return nil
    }
  }
  return val
}

private func parseTerm(_ ctx: inout ParserContext) -> Double? {
  ctx.operationCount += 1
  if ctx.operationCount > kMaxOperations {
    return nil
  }
  guard var val = parseFactor(&ctx) else {
    return nil
  }
  while ctx.pos < ctx.tokens.count {
    let op = ctx.tokens[ctx.pos].type
    if op != .times && op != .divide && op != .mod {
      break
    }
    ctx.pos += 1
    guard let rhs = parseFactor(&ctx) else {
      return nil
    }
    if op == .times {
      val *= rhs
    } else if op == .divide {
      if rhs == 0.0 {
        return nil
      }
      val /= rhs
    } else {
      if rhs == 0.0 {
        return nil
      }
      val = Foundation.fmod(val, rhs)
    }
    if !val.isFinite {
      return nil
    }
  }
  return val
}

private func parseExpression(_ ctx: inout ParserContext) -> Double? {
  ctx.operationCount += 1
  if ctx.operationCount > kMaxOperations {
    return nil
  }
  guard var val = parseTerm(&ctx) else {
    return nil
  }
  while ctx.pos < ctx.tokens.count {
    let op = ctx.tokens[ctx.pos].type
    if op != .plus && op != .minus {
      break
    }
    ctx.pos += 1
    guard let rhs = parseTerm(&ctx) else {
      return nil
    }
    if op == .plus {
      val += rhs
    } else {
      val -= rhs
    }
    if !val.isFinite {
      return nil
    }
  }
  return val
}
