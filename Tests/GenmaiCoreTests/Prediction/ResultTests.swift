// Port of mozc/src/prediction/result_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

struct ResultTests {
  @Test func resultCostLessTest() {
    let costLess = resultCostLess

    do {
      var r1 = PredictionResult()
      var r2 = PredictionResult()
      r1.cost = 100
      r2.cost = 200
      #expect(costLess(r1, r2))
      #expect(!costLess(r2, r1))
    }

    do {
      var r1 = PredictionResult()
      var r2 = PredictionResult()
      r1.cost = 100
      r2.cost = 100
      r1.value = "a"
      r2.value = "b"
      #expect(costLess(r1, r2))
      #expect(!costLess(r2, r1))
    }

    // Same cost and value, but different types (prediction-specific
    // attributes).
    do {
      var r1 = PredictionResult()
      var r2 = PredictionResult()
      r1.cost = 100
      r2.cost = 100
      r1.value = "value"
      r2.value = "value"
      r1.attributes = Attribute.unigram
      r2.attributes = Attribute.bigram
      // Now distinguish them.
      #expect(costLess(r1, r2))
      #expect(!costLess(r2, r1))
    }

    // Same cost and value, but different candidate_attributes (behavioral
    // attributes).
    do {
      var r1 = PredictionResult()
      var r2 = PredictionResult()
      r1.cost = 100
      r2.cost = 100
      r1.value = "value"
      r2.value = "value"
      r1.attributes = Attribute.bestCandidate
      r2.attributes = Attribute.reranked
      #expect(costLess(r1, r2))
      #expect(!costLess(r2, r1))
    }

    // Same cost and value, but one of different candidate_attributes is 0.
    do {
      var r1 = PredictionResult()
      var r2 = PredictionResult()
      r1.cost = 100
      r2.cost = 100
      r1.value = "value"
      r2.value = "value"
      r1.attributes = Attribute.bestCandidate
      r2.attributes = Attribute.defaultAttribute
      #expect(costLess(r1, r2))
      #expect(!costLess(r2, r1))
    }

    // Same cost, value, attributes, but different lid.
    do {
      var r1 = PredictionResult()
      var r2 = PredictionResult()
      r1.cost = 100
      r1.value = "v"
      r1.attributes = Attribute.unigram | Attribute.bestCandidate
      r2.cost = 100
      r2.value = "v"
      r2.attributes = Attribute.unigram | Attribute.bestCandidate
      r1.lid = 10
      r2.lid = 20
      #expect(costLess(r1, r2))
      #expect(!costLess(r2, r1))
    }

    // Same cost, value, attributes, lid, but different rid.
    do {
      var r1 = PredictionResult()
      var r2 = PredictionResult()
      r1.cost = 100
      r1.value = "v"
      r1.attributes = Attribute.unigram | Attribute.bestCandidate
      r1.lid = 10
      r2.cost = 100
      r2.value = "v"
      r2.attributes = Attribute.unigram | Attribute.bestCandidate
      r2.lid = 10
      r1.rid = 10
      r2.rid = 20
      #expect(costLess(r1, r2))
      #expect(!costLess(r2, r1))
    }

    // Same but different description.
    do {
      var r1 = PredictionResult()
      var r2 = PredictionResult()
      r1.cost = 100
      r1.value = "v"
      r1.attributes = Attribute.unigram | Attribute.bestCandidate
      r2.cost = 100
      r2.value = "v"
      r2.attributes = Attribute.unigram | Attribute.bestCandidate
      r1.description = "a"
      r2.description = "b"
      #expect(costLess(r1, r2))
      #expect(!costLess(r2, r1))
    }
  }

  @Test func resultWCostLessTest() {
    let wcostLess = resultWCostLess

    do {
      var r1 = PredictionResult()
      var r2 = PredictionResult()
      r1.wcost = 100
      r2.wcost = 200
      #expect(wcostLess(r1, r2))
      #expect(!wcostLess(r2, r1))
    }

    do {
      var r1 = PredictionResult()
      var r2 = PredictionResult()
      r1.wcost = 100
      r2.wcost = 100
      r1.value = "a"
      r2.value = "b"
      #expect(wcostLess(r1, r2))
      #expect(!wcostLess(r2, r1))
    }
  }

  // Not in the C++ test: ValueLess examples from result.h.
  @Test func valueLess() {
    #expect(ResultInternal.valueLess("ん", "あいうえお"))
    #expect(ResultInternal.valueLess("あいうえお", "かきくけこ"))
    #expect(ResultInternal.valueLess("テスト1", "テスト00"))
    #expect(!ResultInternal.valueLess("テスト00", "テスト1"))
  }

  // Not in the C++ test: GetPredictionTypeDebugString.
  @Test func predictionTypeDebugString() {
    #expect(getPredictionTypeDebugString(Attribute.unigram | Attribute.bigram) == "UB")
    #expect(
      getPredictionTypeDebugString(Attribute.realtimeConversion | Attribute.realtimeTop) == "R1")
    #expect(getPredictionTypeDebugString(Attribute.realtimeConversion) == "R")
    #expect(
      getPredictionTypeDebugString(
        Attribute.suffixDictionary | Attribute.english | Attribute.typingCorrection
          | Attribute.typingCompletion | Attribute.supplementalModel
          | Attribute.keyExpandedInDictionary) == "SETCXK")
  }
}
