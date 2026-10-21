// Port of mozc/src/engine/engine_output_test.cc (3.35.6354).

import GenmaiBase
import GenmaiProtocol
import Testing

@testable import GenmaiCore

private struct DummySegment {
  let value: String
  let usageId: Int32
  let usageTitle: String
  let usageDescription: String
  init(_ value: String, _ usageId: Int32, _ usageTitle: String, _ usageDescription: String) {
    self.value = value
    self.usageId = usageId
    self.usageTitle = usageTitle
    self.usageDescription = usageDescription
  }
}

private func fillDummySegment(
  _ dummySegments: [DummySegment], _ num: Int, _ segment: Segment, _ candidateList: CandidateList
) {
  for i in 0..<num {
    let cand = segment.pushBackCandidate()
    candidateList.addCandidate(i, dummySegments[i].value)
    cand.value = dummySegments[i].value
    cand.usageId = dummySegments[i].usageId
    cand.usageTitle = dummySegments[i].usageTitle
    cand.usageDescription = dummySegments[i].usageDescription
  }
}

struct EngineOutputTests {
  @Test func fillCandidate() {
    let segment = Segment()
    var candidate = CandidateList.Candidate()
    var candidateProto = Genmai_Commands_CandidateWindow.Candidate()

    let kValue13 = "Value only"
    let kValue42 = "The answer"
    let kPrefix42 = "prefix"
    let kSuffix42 = "suffix"
    let kDescription42 = "description"
    let kDisplayValue42 = "display_value"
    let kSubcandidateList = "Subcandidates"

    // Make 100 candidates
    for _ in 0..<100 {
      segment.pushBackCandidate()
    }
    segment.mutableCandidate(13).value = kValue13
    segment.mutableCandidate(42).value = kValue42
    segment.mutableCandidate(42).prefix = kPrefix42
    segment.mutableCandidate(42).suffix = kSuffix42
    segment.mutableCandidate(42).description = kDescription42
    segment.mutableCandidate(42).displayValue = kDisplayValue42

    candidate.setId(13)
    EngineOutput.fillCandidate(segment, candidate, &candidateProto)
    #expect(candidateProto.id == 13)
    #expect(candidateProto.value == kValue13)
    #expect(!candidateProto.hasAnnotation)

    candidate.clear()
    candidateProto = Genmai_Commands_CandidateWindow.Candidate()
    candidate.setId(42)
    EngineOutput.fillCandidate(segment, candidate, &candidateProto)
    #expect(candidateProto.id == 42)
    #expect(candidateProto.value == kValue42)
    #expect(candidateProto.hasAnnotation)
    #expect(candidateProto.annotation.prefix == kPrefix42)
    #expect(candidateProto.annotation.suffix == kSuffix42)
    #expect(candidateProto.annotation.description_p == kDescription42)
    #expect(candidateProto.annotation.displayValue == kDisplayValue42)

    candidate.clear()
    candidateProto = Genmai_Commands_CandidateWindow.Candidate()
    let candidateList = candidate.mutableSubcandidateList()
    candidateList.rotate = true
    candidateList.name = kSubcandidateList
    let kFirstIdInSubList = -123
    candidateList.addCandidate(kFirstIdInSubList, "minus 123")
    candidateList.addCandidate(-456, "minus 456")
    candidateList.addCandidate(-789, "minus 789")
    EngineOutput.fillCandidate(segment, candidate, &candidateProto)
    #expect(candidateProto.hasID)
    #expect(candidateProto.id == Int32(kFirstIdInSubList))
    #expect(candidateProto.value == kSubcandidateList)
    #expect(!candidateProto.hasAnnotation)
  }

  @Test func fillCandidateWindow() {
    let segment = Segment()
    let candidateList = CandidateList(rotate: true)
    var candidateWindowProto = Genmai_Commands_CandidateWindow()

    let kSubcandidateList = "Subcandidates"
    let kValues = ["0", "1", "2:sub0", "3:sub1", "4:sub2"]

    // Make 5 candidates
    for i in 0..<5 {
      segment.pushBackCandidate().value = kValues[i]
    }

    candidateList.focused = true
    candidateList.pageSize = 9
    candidateList.addCandidate(0, "0")
    candidateList.addCandidate(1, "1")
    let subcandidateList = candidateList.addSubCandidateList()
    subcandidateList.focused = true
    subcandidateList.rotate = true
    subcandidateList.name = kSubcandidateList
    subcandidateList.addCandidate(2, "2")
    subcandidateList.addCandidate(3, "3")
    subcandidateList.addCandidate(4, "4")

    // Focused index = 0. page_size = 9.
    EngineOutput.fillCandidateWindow(segment, candidateList, 0, &candidateWindowProto)
    #expect(candidateWindowProto.pageSize == 9)
    #expect(candidateWindowProto.candidate.count == 3)
    #expect(candidateWindowProto.position == 0)
    #expect(candidateWindowProto.hasFocusedIndex)
    #expect(candidateWindowProto.focusedIndex == 0)
    #expect(candidateWindowProto.candidate[0].value == kValues[0])
    #expect(candidateWindowProto.candidate[1].value == kValues[1])
    #expect(candidateWindowProto.candidate[2].value == kSubcandidateList)
    #expect(!candidateWindowProto.hasSubCandidateWindow)

    // Focused index = 2 with a subcandidate list. page_size = 5.
    candidateWindowProto = Genmai_Commands_CandidateWindow()
    candidateList.moveToId(3)
    candidateList.pageSize = 5
    EngineOutput.fillCandidateWindow(segment, candidateList, 1, &candidateWindowProto)
    #expect(candidateWindowProto.pageSize == 5)
    #expect(candidateWindowProto.candidate.count == 3)
    #expect(candidateWindowProto.position == 1)
    #expect(candidateWindowProto.hasFocusedIndex)
    #expect(candidateWindowProto.focusedIndex == 2)
    #expect(candidateWindowProto.candidate[0].value == kValues[0])
    #expect(candidateWindowProto.candidate[1].value == kValues[1])
    #expect(candidateWindowProto.candidate[2].value == kSubcandidateList)
    #expect(candidateWindowProto.candidate[0].index == 0)
    #expect(candidateWindowProto.candidate[1].index == 1)
    #expect(candidateWindowProto.candidate[2].index == 2)

    // Check the values of the subcandidate list.
    #expect(candidateWindowProto.hasSubCandidateWindow)
    #expect(candidateWindowProto.subCandidateWindow.candidate.count == 3)
    #expect(candidateWindowProto.subCandidateWindow.position == 2)
    #expect(candidateWindowProto.subCandidateWindow.hasFocusedIndex)
    #expect(candidateWindowProto.subCandidateWindow.focusedIndex == 1)
    #expect(candidateWindowProto.subCandidateWindow.candidate[0].value == kValues[2])
    #expect(candidateWindowProto.subCandidateWindow.candidate[1].value == kValues[3])
    #expect(candidateWindowProto.subCandidateWindow.candidate[2].value == kValues[4])

    // Check focused_index.
    candidateWindowProto = Genmai_Commands_CandidateWindow()
    candidateList.focused = false
    subcandidateList.focused = true
    EngineOutput.fillCandidateWindow(segment, candidateList, 0, &candidateWindowProto)
    #expect(!candidateWindowProto.hasFocusedIndex)
    #expect(candidateWindowProto.subCandidateWindow.hasFocusedIndex)

    candidateWindowProto = Genmai_Commands_CandidateWindow()
    candidateList.focused = false
    subcandidateList.focused = false
    EngineOutput.fillCandidateWindow(segment, candidateList, 0, &candidateWindowProto)
    #expect(!candidateWindowProto.hasFocusedIndex)
    #expect(!candidateWindowProto.subCandidateWindow.hasFocusedIndex)

    candidateWindowProto = Genmai_Commands_CandidateWindow()
    candidateList.focused = true
    subcandidateList.focused = false
    EngineOutput.fillCandidateWindow(segment, candidateList, 0, &candidateWindowProto)
    #expect(candidateWindowProto.hasFocusedIndex)
    #expect(!candidateWindowProto.subCandidateWindow.hasFocusedIndex)
  }

  @Test func fillAllCandidateWords() {
    // IDs are ordered by BFS.
    //
    //  ID|Idx| Candidate list tree
    //   1| 0 | [1:[sub1_1,
    //   5| 1 |    sub1_2:[subsub1_1,
    //   6| 2 |            subsub1_2],
    //   2| 3 |    sub1_3],
    //   0| 4 |  2,
    //   3| 5 |  3:[sub2_1,
    //   4| 6 |     sub2_2]]
    let mainList = CandidateList(rotate: true)
    var candidatesProto = Genmai_Commands_CandidateList()

    // Initialize Segment
    let segment = Segment()
    let kNormalKey = "key"
    segment.setKey(kNormalKey)
    let kDescription = "desc"

    let kValues = ["2", "sub1_1", "sub1_3", "sub2_1", "sub2_2", "subsub1_1", "subsub1_2"]
    let kValueSize = kValues.count
    for i in 0..<kValueSize {
      let candidate = segment.pushBackCandidate()
      candidate.contentKey = kNormalKey
      candidate.value = kValues[i]
      candidate.description = kDescription
      for _ in 0..<i {
        // Puts placeholder lengths.
        // This field is used to determine the size of inner segments.
        // TODO(taku): Stop exposing internal data structure.
        candidate.innerSegmentBoundary.append(1)
      }
    }
    // Set special key to ID:4 / Index:6
    let kSpecialKey = "Special Key"
    segment.mutableCandidate(4).contentKey = kSpecialKey

    // Main
    let sub1 = mainList.addSubCandidateList()
    sub1.rotate = true
    mainList.addCandidate(0, kValues[0])
    let sub2 = mainList.addSubCandidateList()
    sub2.rotate = true

    // Sub1
    sub1.addCandidate(1, kValues[1])
    let subsub1 = sub1.addSubCandidateList()
    subsub1.rotate = true
    sub1.addCandidate(2, kValues[2])

    // Sub2
    sub2.addCandidate(3, kValues[3])
    sub2.addCandidate(4, kValues[4])

    // SubSub1
    subsub1.addCandidate(5, kValues[5])
    subsub1.addCandidate(6, kValues[6])

    // Set focus to ID:5 / Index:1
    mainList.focused = true
    sub1.focused = true
    subsub1.focused = true
    mainList.moveToId(5)
    #expect(mainList.focusedId == 5)
    #expect(mainList.focusedIndex == 0)
    #expect(sub1.focusedIndex == 1)
    #expect(subsub1.focusedIndex == 0)
    // End of Initialization

    // Execute FillAllCandidateWords
    let kCategory = Genmai_Commands_Category.prediction
    EngineOutput.fillAllCandidateWords(segment, mainList, kCategory, &candidatesProto)

    // Varidation
    #expect(candidatesProto.focusedIndex == 1)
    #expect(candidatesProto.category == kCategory)
    #expect(candidatesProto.candidates.count == kValueSize)

    let c = candidatesProto.candidates
    #expect(c.map(\.id) == [1, 5, 6, 2, 0, 3, 4])
    #expect(c.map(\.index) == [0, 1, 2, 3, 4, 5, 6])

    #expect(!c[0].hasKey)
    #expect(!c[1].hasKey)
    #expect(!c[2].hasKey)
    #expect(!c[3].hasKey)
    #expect(!c[4].hasKey)
    #expect(!c[5].hasKey)
    #expect(c[6].hasKey)
    #expect(c[6].key == kSpecialKey)

    #expect(c[0].value == kValues[1])
    #expect(c[1].value == kValues[5])
    #expect(c[2].value == kValues[6])
    #expect(c[3].value == kValues[2])
    #expect(c[4].value == kValues[0])
    #expect(c[5].value == kValues[3])
    #expect(c[6].value == kValues[4])

    for i in 0..<7 {
      #expect(c[i].hasAnnotation)
    }

    #expect(c.map(\.numSegmentsInCandidate) == [1, 5, 6, 2, 1, 3, 4])
  }

  @Test func fillAllCandidateWords_Attributes() {
    let candidateList = CandidateList(rotate: true)
    var candidatesProto = Genmai_Commands_CandidateList()

    // Initialize Segment
    let segment = Segment()
    let kKey = "key"
    segment.setKey(kKey)

    let kValues = ["value_0", "value_1", "value_2", "value_3", "value_4", "value_5"]
    let kValueSize = kValues.count
    for i in 0..<kValueSize {
      let candidate = segment.pushBackCandidate()
      candidate.contentKey = kKey
      candidate.value = kValues[i]

      candidateList.addCandidate(i, kValues[i])
    }

    segment.mutableCandidate(1).attributes = Attribute.userDictionary
    segment.mutableCandidate(2).attributes =
      Attribute.userHistoryPrediction | Attribute.noVariantsExpansion
    segment.mutableCandidate(3).attributes =
      Attribute.spellingCorrection | Attribute.noExtraDescription
    segment.mutableCandidate(4).attributes = Attribute.typingCorrection | Attribute.bestCandidate
    segment.mutableCandidate(5).attributes =
      Attribute.userHistoryPrediction | Attribute.noDeletable

    candidateList.focused = true
    candidateList.moveToId(0)
    #expect(candidateList.focusedId == 0)
    #expect(candidateList.focusedIndex == 0)
    // End of Initialization

    // Execute FillAllCandidateWords
    let kCategory = Genmai_Commands_Category.prediction
    EngineOutput.fillAllCandidateWords(segment, candidateList, kCategory, &candidatesProto)

    // Varidation
    #expect(candidatesProto.focusedIndex == 0)
    #expect(candidatesProto.category == kCategory)
    #expect(candidatesProto.candidates.count == kValueSize)

    let c = candidatesProto.candidates
    #expect(c[0].attributes.isEmpty)
    #expect(c[1].attributes == [.userDictionary])
    #expect(c[2].attributes == [.userHistory, .deletable])
    #expect(c[3].attributes == [.spellingCorrection])
    #expect(c[4].attributes == [.typingCorrection])
    #expect(c[5].attributes == [.userHistory])
  }

  @Test func shouldShowUsages() throws {
    do {
      let segment = Segment()
      let candidateList = CandidateList(rotate: true)
      let dummySegments = [
        DummySegment("val0", 0, "", ""), DummySegment("val1", 0, "", ""),
        DummySegment("val2", 0, "", ""), DummySegment("val3", 0, "", ""),
        DummySegment("val4", 0, "", ""),
      ]
      fillDummySegment(dummySegments, 5, segment, candidateList)
      candidateList.addSubCandidateList().rotate = true
      candidateList.focused = true
      try #require(candidateList.moveToId(0))
      try #require(!EngineOutput.shouldShowUsages(segment, candidateList))
    }
    do {
      let segment = Segment()
      let candidateList = CandidateList(rotate: true)
      let dummySegments = [
        DummySegment("val0", 0, "", ""), DummySegment("val1", 10, "title1", ""),
        DummySegment("val2", 0, "", ""), DummySegment("val3", 0, "", ""),
        DummySegment("val4", 0, "", ""),
      ]
      fillDummySegment(dummySegments, 5, segment, candidateList)
      candidateList.addSubCandidateList().rotate = true
      candidateList.focused = true
      try #require(candidateList.moveToId(0))
      try #require(EngineOutput.shouldShowUsages(segment, candidateList))
    }
    do {
      let segment = Segment()
      let candidateList = CandidateList(rotate: true)
      var dummySegments: [DummySegment] = []
      for i in 0..<30 {
        let value = "val" + (i < 10 ? "0" : "") + String(i)
        switch i {
        case 0: dummySegments.append(DummySegment(value, 10, "title00", ""))
        case 10: dummySegments.append(DummySegment(value, 20, "title10", ""))
        case 13: dummySegments.append(DummySegment(value, 30, "title13", ""))
        default: dummySegments.append(DummySegment(value, 0, "", ""))
        }
      }
      fillDummySegment(dummySegments, 30, segment, candidateList)
      candidateList.addSubCandidateList().rotate = true
      // pages of candidate_list:
      //  [00-08],[09-17],[18-26],[27-29]+subcandidate
      candidateList.focused = true
      try #require(candidateList.moveToId(0))
      try #require(EngineOutput.shouldShowUsages(segment, candidateList))
      try #require(candidateList.moveToId(8))
      try #require(EngineOutput.shouldShowUsages(segment, candidateList))
      try #require(candidateList.moveToId(9))
      try #require(EngineOutput.shouldShowUsages(segment, candidateList))
      try #require(candidateList.moveToId(17))
      try #require(EngineOutput.shouldShowUsages(segment, candidateList))
      try #require(candidateList.moveToId(18))
      try #require(!EngineOutput.shouldShowUsages(segment, candidateList))
      try #require(candidateList.moveToId(26))
      try #require(!EngineOutput.shouldShowUsages(segment, candidateList))
      try #require(candidateList.moveToId(27))
      try #require(!EngineOutput.shouldShowUsages(segment, candidateList))
    }
  }

  @Test func fillUsages() throws {
    let segment = Segment()
    let candidateList = CandidateList(rotate: true)
    var candidateWindowProto = Genmai_Commands_CandidateWindow()
    let usageEntries: [Int: (Int32, String, String)] = [
      0: (10, "title00", "desc00"),
      4: (20, "title04", "desc04"),
      10: (30, "title10", "desc10"),
      11: (40, "title11", "desc11"),
      12: (50, "title12", "desc12"),
      13: (60, "title13", "desc13"),
      19: (100, "title100", "desc100"),
      20: (110, "title110", "desc110"),
      21: (100, "title100", "desc100"),
      22: (110, "title110", "desc110"),
    ]
    var dummySegments: [DummySegment] = []
    for i in 0..<30 {
      let value = "val" + (i < 10 ? "0" : "") + String(i)
      if let (id, title, desc) = usageEntries[i] {
        dummySegments.append(DummySegment(value, id, title, desc))
      } else {
        dummySegments.append(DummySegment(value, 0, "", ""))
      }
    }
    fillDummySegment(dummySegments, 30, segment, candidateList)
    candidateList.addSubCandidateList().rotate = true

    // pages of candidate_list:
    //  [00-08],[09-17],[18-26],[27-29]+subcandidate

    candidateList.focused = true

    candidateList.moveToId(2)
    candidateWindowProto = Genmai_Commands_CandidateWindow()
    EngineOutput.fillUsages(segment, candidateList, &candidateWindowProto)
    try #require(candidateWindowProto.hasUsages)
    // There is no focused usage.
    #expect(!candidateWindowProto.usages.hasFocusedIndex)
    #expect(candidateWindowProto.usages.information.count == 2)
    #expect(candidateWindowProto.usages.information[0].id == 10)
    #expect(candidateWindowProto.usages.information[0].title == dummySegments[0].usageTitle)
    #expect(
      candidateWindowProto.usages.information[0].description_p
        == dummySegments[0].usageDescription)
    #expect(candidateWindowProto.usages.information[1].id == 20)
    #expect(candidateWindowProto.usages.information[1].title == dummySegments[4].usageTitle)
    #expect(
      candidateWindowProto.usages.information[1].description_p
        == dummySegments[4].usageDescription)

    candidateList.moveToId(12)
    candidateWindowProto = Genmai_Commands_CandidateWindow()
    EngineOutput.fillUsages(segment, candidateList, &candidateWindowProto)
    try #require(candidateWindowProto.hasUsages)
    // Focused usage index is 20
    #expect(candidateWindowProto.usages.hasFocusedIndex)
    #expect(candidateWindowProto.usages.focusedIndex == 2)
    #expect(candidateWindowProto.usages.information.count == 4)
    for (k, src) in [10, 11, 12, 13].enumerated() {
      #expect(candidateWindowProto.usages.information[k].id == dummySegments[src].usageId)
      #expect(candidateWindowProto.usages.information[k].title == dummySegments[src].usageTitle)
      #expect(
        candidateWindowProto.usages.information[k].description_p
          == dummySegments[src].usageDescription)
    }
    #expect(candidateWindowProto.usages.information.map(\.id) == [30, 40, 50, 60])

    candidateList.moveToId(19)
    candidateWindowProto = Genmai_Commands_CandidateWindow()
    EngineOutput.fillUsages(segment, candidateList, &candidateWindowProto)
    try #require(candidateWindowProto.hasUsages)
    #expect(candidateWindowProto.usages.hasFocusedIndex)
    #expect(candidateWindowProto.usages.focusedIndex == 0)
    // usages(id:100) of "val19" and "val21" are merged
    #expect(candidateWindowProto.usages.information.count == 2)
    #expect(candidateWindowProto.usages.information[0].id == 100)
    #expect(candidateWindowProto.usages.information[0].title == dummySegments[19].usageTitle)
    #expect(
      candidateWindowProto.usages.information[0].description_p
        == dummySegments[19].usageDescription)
    #expect(candidateWindowProto.usages.information[1].id == 110)
    #expect(candidateWindowProto.usages.information[1].title == dummySegments[20].usageTitle)
    #expect(
      candidateWindowProto.usages.information[1].description_p
        == dummySegments[20].usageDescription)

    candidateList.moveToId(20)
    candidateWindowProto = Genmai_Commands_CandidateWindow()
    EngineOutput.fillUsages(segment, candidateList, &candidateWindowProto)
    try #require(candidateWindowProto.hasUsages)
    #expect(candidateWindowProto.usages.hasFocusedIndex)
    #expect(candidateWindowProto.usages.focusedIndex == 1)

    // usages(id:100) of "val19" and "val21" are merged
    candidateList.moveToId(21)
    candidateWindowProto = Genmai_Commands_CandidateWindow()
    EngineOutput.fillUsages(segment, candidateList, &candidateWindowProto)
    try #require(candidateWindowProto.hasUsages)
    #expect(candidateWindowProto.usages.hasFocusedIndex)
    #expect(candidateWindowProto.usages.focusedIndex == 0)

    // usages(id:110) of "val20" and "val22" are merged
    candidateList.moveToId(22)
    candidateWindowProto = Genmai_Commands_CandidateWindow()
    EngineOutput.fillUsages(segment, candidateList, &candidateWindowProto)
    try #require(candidateWindowProto.hasUsages)
    #expect(candidateWindowProto.usages.hasFocusedIndex)
    #expect(candidateWindowProto.usages.focusedIndex == 1)

    candidateList.moveToId(28)
    candidateWindowProto = Genmai_Commands_CandidateWindow()
    EngineOutput.fillUsages(segment, candidateList, &candidateWindowProto)
    try #require(!candidateWindowProto.hasUsages)
  }

  @Test func fillCandidateWindowRange() throws {
    let segment = Segment()
    let candidateList = CandidateList(rotate: true)
    var candidateWindowProto = Genmai_Commands_CandidateWindow()
    var dummySegments: [DummySegment] = []
    for i in 0..<12 {
      let n = (i < 10 ? "0" : "") + String(i)
      dummySegments.append(DummySegment("val" + n, Int32(10 + i), "title" + n, "desc" + n))
    }
    fillDummySegment(dummySegments, dummySegments.count, segment, candidateList)
    candidateList.focused = true

    EngineOutput.fillCandidateWindow(segment, candidateList, 0, &candidateWindowProto)
    try #require(candidateWindowProto.focusedIndex == 0)
    try #require(candidateWindowProto.size == 12)
    try #require(candidateWindowProto.candidate.count == 9)
    try #require(candidateWindowProto.candidate[0].index == 0)
    try #require(candidateWindowProto.candidate[0].id == 0)
    try #require(candidateWindowProto.candidate[0].informationID == 10)
    try #require(candidateWindowProto.hasUsages)
    try #require(
      candidateWindowProto.usages.information.count == candidateWindowProto.candidate.count)
    try #require(candidateWindowProto.usages.information[0].id == 10)
    try #require(candidateWindowProto.usages.information[0].candidateID[0] == 0)

    candidateList.moveToId(11)
    candidateWindowProto = Genmai_Commands_CandidateWindow()
    EngineOutput.fillCandidateWindow(segment, candidateList, 0, &candidateWindowProto)
    try #require(candidateWindowProto.focusedIndex == 11)
    try #require(candidateWindowProto.size == 12)
    try #require(candidateWindowProto.candidate.count == 3)
    try #require(candidateWindowProto.candidate[0].index == 9)
    try #require(candidateWindowProto.candidate[0].id == 9)
    try #require(candidateWindowProto.candidate[0].informationID == 19)
    try #require(candidateWindowProto.hasUsages)
    try #require(
      candidateWindowProto.usages.information.count == candidateWindowProto.candidate.count)
    try #require(candidateWindowProto.usages.information[0].id == 19)
    try #require(candidateWindowProto.usages.information[0].candidateID[0] == 9)
  }

  @Test func fillShortcuts() throws {
    let kDigits = "123456789"

    var candidateWindowProto1 = Genmai_Commands_CandidateWindow()
    for _ in 0..<10 {
      candidateWindowProto1.candidate.append(Genmai_Commands_CandidateWindow.Candidate())
    }
    try #require(candidateWindowProto1.candidate.count == 10)

    EngineOutput.fillShortcuts(kDigits, &candidateWindowProto1)
    #expect(candidateWindowProto1.candidate[0].annotation.shortcut == "1")
    #expect(candidateWindowProto1.candidate[8].annotation.shortcut == "9")
    #expect(!candidateWindowProto1.candidate[9].annotation.hasShortcut)

    var candidateWindowProto2 = Genmai_Commands_CandidateWindow()
    for _ in 0..<3 {
      candidateWindowProto2.candidate.append(Genmai_Commands_CandidateWindow.Candidate())
    }
    try #require(candidateWindowProto2.candidate.count == 3)

    EngineOutput.fillShortcuts(kDigits, &candidateWindowProto2)
    #expect(candidateWindowProto2.candidate[0].annotation.shortcut == "1")
    #expect(candidateWindowProto2.candidate[2].annotation.shortcut == "3")
  }

  @Test func fillFooter() throws {
    var candidateWindow = Genmai_Commands_CandidateWindow()
    #expect(EngineOutput.fillFooter(.suggestion, &candidateWindow))
    #expect(candidateWindow.hasFooter)

    // !(CHANNEL_DEV && GOOGLE_JAPANESE_INPUT_BUILD)
    #expect(candidateWindow.footer.hasLabel)
    #expect(!candidateWindow.footer.hasSubLabel)
    let kLabel = "Tabキーで選択"
    #expect(candidateWindow.footer.label == kLabel)

    #expect(!candidateWindow.footer.indexVisible)
    #expect(!candidateWindow.footer.logoVisible)

    candidateWindow = Genmai_Commands_CandidateWindow()
    #expect(EngineOutput.fillFooter(.prediction, &candidateWindow))
    #expect(candidateWindow.hasFooter)
    #expect(!candidateWindow.footer.hasLabel)
    #expect(candidateWindow.footer.indexVisible)
    #expect(candidateWindow.footer.logoVisible)

    candidateWindow = Genmai_Commands_CandidateWindow()
    #expect(EngineOutput.fillFooter(.conversion, &candidateWindow))
    #expect(candidateWindow.hasFooter)
    #expect(!candidateWindow.footer.hasLabel)
    #expect(candidateWindow.footer.indexVisible)
    #expect(candidateWindow.footer.logoVisible)

    candidateWindow = Genmai_Commands_CandidateWindow()
    #expect(!EngineOutput.fillFooter(.transliteration, &candidateWindow))
    #expect(!candidateWindow.hasFooter)

    candidateWindow = Genmai_Commands_CandidateWindow()
    #expect(!EngineOutput.fillFooter(.usage, &candidateWindow))
    #expect(!candidateWindow.hasFooter)

    candidateWindow = Genmai_Commands_CandidateWindow()
    for i in 0..<20 {
      var c = Genmai_Commands_CandidateWindow.Candidate()
      c.index = UInt32(i)
      c.value = "dummy"
      c.id = Int32(i)
      // Candidates with even Id can be deleted.
      c.annotation.deletable = (i % 2 == 0)
      candidateWindow.candidate.append(c)
    }
    for i in 0..<20 {
      candidateWindow.clearFooter()
      candidateWindow.focusedIndex = UInt32(i)
      #expect(EngineOutput.fillFooter(.prediction, &candidateWindow))
      if i % 2 == 0 {
        try #require(candidateWindow.hasFooter)
        try #require(candidateWindow.footer.hasLabel)
        // __APPLE__
        let kDeleteInstruction = "control+fn+deleteで履歴から削除"
        #expect(candidateWindow.footer.label == kDeleteInstruction)
      }
    }
  }

  @Test func fillSubLabel() {
    var footer = Genmai_Commands_Footer()
    footer.label = "to be deleted"
    EngineOutput.fillSubLabel(&footer)
    #expect(footer.hasSubLabel)
    #expect(!footer.hasLabel)
    #expect(footer.subLabel.utf8.count > 6)  // 6 == strlen("build ")
    // sub_label should start with "build ".
    #expect(footer.subLabel.hasPrefix("build "))
  }

  @Test func addSegment() {
    var preedit = Genmai_Commands_Preedit()
    var index = 0
    do {
      // "〜" is a character to be processed by TextNormalizer::NormalizeText
      let kKey = "ゔ〜 preedit focused"
      let kValue = "ゔ〜 PREEDIT FOCUSED"
      let types = EngineOutput.SegmentType.preedit | EngineOutput.SegmentType.focused
      #expect(EngineOutput.addSegment(kKey, kValue, types, &preedit))
      #expect(preedit.segment.count == index + 1)
      let segment = preedit.segment[index]

      let normalizedKey = TextNormalizer.normalizeText(kKey)
      #expect(segment.key == normalizedKey)
      let normalizedValue = TextNormalizer.normalizeText(kValue)
      #expect(segment.value == normalizedValue)
      #expect(Int(segment.valueLength) == Util.charsLen(normalizedValue))
      #expect(segment.annotation == .underline)
      index += 1
    }

    do {
      let kKey = "ゔ〜 preedit"
      let kValue = "ゔ〜 PREEDIT"
      let types = EngineOutput.SegmentType.preedit
      #expect(EngineOutput.addSegment(kKey, kValue, types, &preedit))
      #expect(preedit.segment.count == index + 1)
      let segment = preedit.segment[index]

      let normalizedKey = TextNormalizer.normalizeText(kKey)
      #expect(segment.key == normalizedKey)
      let normalizedValue = TextNormalizer.normalizeText(kValue)
      #expect(segment.value == normalizedValue)
      #expect(Int(segment.valueLength) == Util.charsLen(normalizedValue))
      #expect(segment.annotation == .underline)
      index += 1
    }

    do {
      let kKey = "ゔ〜 conversion focused"
      let kValue = "ゔ〜 CONVERSION FOCUSED"
      let types = EngineOutput.SegmentType.conversion | EngineOutput.SegmentType.focused
      #expect(EngineOutput.addSegment(kKey, kValue, types, &preedit))
      #expect(preedit.segment.count == index + 1)
      let segment = preedit.segment[index]

      let normalizedKey = TextNormalizer.normalizeText(kKey)
      #expect(segment.key == normalizedKey)
      // Normalization is performed in Rewriter.
      let normalizedValue = kValue
      #expect(segment.value == normalizedValue)
      #expect(Int(segment.valueLength) == Util.charsLen(normalizedValue))
      #expect(segment.annotation == .highlight)
      index += 1
    }

    do {
      let kKey = "ゔ〜 conversion"
      let kValue = "ゔ〜 CONVERSION"
      let types = EngineOutput.SegmentType.conversion
      #expect(EngineOutput.addSegment(kKey, kValue, types, &preedit))
      #expect(preedit.segment.count == index + 1)
      let segment = preedit.segment[index]

      let normalizedKey = TextNormalizer.normalizeText(kKey)
      #expect(segment.key == normalizedKey)
      // Normalization is performed in Rewriter.
      let normalizedValue = kValue
      #expect(segment.value == normalizedValue)
      #expect(Int(segment.valueLength) == Util.charsLen(normalizedValue))
      #expect(segment.annotation == .underline)
      index += 1
    }

    do {
      let kKey = "abc"
      let kValue = ""  // empty value
      let types = EngineOutput.SegmentType.conversion
      #expect(!EngineOutput.addSegment(kKey, kValue, types, &preedit))
      #expect(preedit.segment.count == index)
    }
  }

  @Test func fillConversionResultWithoutNormalization() {
    let kInput = "ゔ"

    var result = Genmai_Commands_Result()
    EngineOutput.fillConversionResultWithoutNormalization(kInput, kInput, &result)
    #expect(result.type == .string)
    #expect(result.key == kInput)  // should not be normalized
    #expect(result.value == kInput)  // should not be normalized
  }

  @Test func fillConversionResult() {
    var result = Genmai_Commands_Result()
    EngineOutput.fillConversionResult("abc", "ABC", &result)
    #expect(result.type == .string)
    #expect(result.key == "abc")
    #expect(result.value == "ABC")
  }

  @Test func fillCursorOffsetResult() {
    var result = Genmai_Commands_Result()
    EngineOutput.fillCursorOffsetResult(-1, &result)
    #expect(result.cursorOffset == -1)
  }

  @Test func fillPreeditResult() {
    var result = Genmai_Commands_Result()
    EngineOutput.fillPreeditResult("ABC", &result)
    #expect(result.type == .string)
    #expect(result.key == "ABC")
    #expect(result.value == "ABC")
  }

  @Test func fillAllCandidateWords_NonFocused() {
    // Test against b/3059255
    // Even when no candidate was focused, all_candidate_words had focused_index.

    let mainList = CandidateList(rotate: true)
    var candidatesProto = Genmai_Commands_CandidateList()
    mainList.addCandidate(0, "key")

    // Initialize Segment
    let segment = Segment()
    let kNormalKey = "key"
    segment.setKey(kNormalKey)

    let candidate = segment.pushBackCandidate()
    candidate.contentKey = "key"
    candidate.value = "value"

    do {
      // Execute FillAllCandidateWords
      let kCategory = Genmai_Commands_Category.suggestion
      EngineOutput.fillAllCandidateWords(segment, mainList, kCategory, &candidatesProto)

      // Varidation
      #expect(!candidatesProto.hasFocusedIndex)
    }
    do {
      mainList.focused = true
      // Execute FillAllCandidateWords
      // When the category is SUGGESTION, has_focused_index never return true in
      // real usage. This is just a test case.
      let kCategory = Genmai_Commands_Category.suggestion
      EngineOutput.fillAllCandidateWords(segment, mainList, kCategory, &candidatesProto)

      // Validation
      // If a candidate is focused, true is expected.
      #expect(candidatesProto.hasFocusedIndex)
    }
  }

  @Test func fillRemovedCandidateWords() {
    var candidatesProto = Genmai_Commands_CandidateList()

    // Initialize Segment
    let segment = Segment()
    let kNormalKey = "key"
    segment.setKey(kNormalKey)

    let candidate = Candidate()
    candidate.contentKey = "key"
    candidate.value = "value"
    segment.removedCandidatesForDebug.append(candidate)

    // Execute FillAllCandidateWords
    EngineOutput.fillRemovedCandidates(segment, &candidatesProto)
  }

  @Test func fillConversion_MultiSegmentSpan() {
    let segments = Segments()
    let seg0 = segments.addSegment()
    seg0.setKey("わたしは")
    let cand0 = seg0.pushBackCandidate()
    cand0.value = "私"
    cand0.key = "わたし"

    let cand1 = seg0.pushBackCandidate()
    cand1.value = "私は"
    cand1.key = "わたしは"
    cand1.convertedSegmentCount = 2

    let seg1 = segments.addSegment()
    seg1.setKey("は")
    let cand2 = seg1.pushBackCandidate()
    cand2.value = "は"
    cand2.key = "は"

    // When candidate 0 (normal) is selected: 2 segments rendered
    do {
      var preedit = Genmai_Commands_Preedit()
      EngineOutput.fillConversion(segments, 0, 0, &preedit)
      #expect(preedit.segment.count == 2)
      #expect(preedit.segment[0].value == "私")
      #expect(preedit.segment[1].value == "は")
    }

    // When candidate 1 (converted_segment_count = 2) is selected: only 1 segment
    // rendered
    do {
      var preedit = Genmai_Commands_Preedit()
      EngineOutput.fillConversion(segments, 0, 1, &preedit)
      #expect(preedit.segment.count == 1)
      #expect(preedit.segment[0].value == "私は")
      #expect(preedit.segment[0].key == "わたしは")
      #expect(preedit.segment[0].annotation == .highlight)
      #expect(Int(preedit.cursor) == Util.charsLen("私は"))
    }

    // When candidate 1 (converted_segment_count = 2) is candidate(0) on seg0,
    // and focus is on seg1 (focused_segment_index = 1):
    // current_index (0) < focused_index (1) and current_index + count (2) >
    // focused_index (1), so span is truncated to 1.
    do {
      let segsWithMultiTop = Segments()
      let s0 = segsWithMultiTop.addSegment()
      s0.setKey("わたしは")
      let c0 = s0.pushBackCandidate()
      c0.value = "私は"
      c0.key = "わたしは"
      c0.convertedSegmentCount = 2

      let s1 = segsWithMultiTop.addSegment()
      s1.setKey("なかのです")
      let c1 = s1.pushBackCandidate()
      c1.value = "中野です"
      c1.key = "なかのです"

      var preedit = Genmai_Commands_Preedit()
      EngineOutput.fillConversion(segsWithMultiTop, 1, 0, &preedit)
      #expect(preedit.segment.count == 2)
      #expect(preedit.segment[0].value == "私は")
      #expect(preedit.segment[1].value == "中野です")
      #expect(preedit.segment[1].annotation == .highlight)
    }

    // Empty conversion segments returns early without error.
    do {
      let emptySegments = Segments()
      var preedit = Genmai_Commands_Preedit()
      EngineOutput.fillConversion(emptySegments, 0, 0, &preedit)
      #expect(preedit.segment.count == 0)
    }
  }
}
