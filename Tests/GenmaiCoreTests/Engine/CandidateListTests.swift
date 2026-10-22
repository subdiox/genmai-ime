// Port of mozc/src/engine/candidate_list_test.cc (3.35.6354).

import Testing

@testable import GenmaiCore

private typealias A = CandidateList.Attribute

private struct Fixture {
  let mainList = CandidateList(rotate: true)
  let subList1: CandidateList
  let subList2: CandidateList
  let subSubList21: CandidateList

  init() {
    mainList.addCandidate(0, "0")  // main0
    mainList.addCandidate(1, "1")  // main1
    subList1 = mainList.addSubCandidateList()  // main2
    mainList.addCandidate(2, "2")  // main3
    mainList.addCandidate(3, "3")  // main4
    mainList.addCandidate(4, "4")  // main5
    mainList.addCandidate(5, "5")  // main6
    subList2 = mainList.addSubCandidateList()  // main7
    mainList.addCandidate(6, "6")  // main8
    mainList.addCandidate(7, "7")  // main9
    mainList.addCandidate(8, "8")  // main10
    mainList.addCandidate(9, "9")  // main11
    mainList.addCandidate(10, "10")  // main12

    subList1.addCandidate(-1, "-1")  // sub10
    subList1.addCandidate(-2, "-2")  // sub11
    subList1.addCandidate(-3, "-3")  // sub12
    subList1.addCandidate(-4, "-4")  // sub13
    subList1.addCandidate(-5, "-5")  // sub14

    subSubList21 = subList2.addSubCandidateList()  // sub20
    subList2.rotate = true
    subList2.addCandidate(21, "21")  // sub21
    subList2.addCandidate(22, "22")  // sub22
    subList2.addCandidate(23, "23")  // sub23
    subList2.addCandidate(24, "24")  // sub24
    subList2.addCandidate(25, "25")  // sub25

    subSubList21.addCandidate(210, "210")  // subsub210
    subSubList21.addCandidate(211, "211")  // subsub211
    subSubList21.addCandidate(212, "212")  // subsub212
  }
}

struct CandidateListTests {
  @Test func moveToId() {
    let f = Fixture()
    // main0
    #expect(f.mainList.moveToId(0))
    #expect(f.mainList.focusedId == 0)
    #expect(f.mainList.focusedIndex == 0)

    // main1
    #expect(f.mainList.moveToId(1))
    #expect(f.mainList.focusedId == 1)
    #expect(f.mainList.focusedIndex == 1)

    // (main2, sub13)
    #expect(f.mainList.moveToId(-4))
    #expect(f.mainList.focusedId == -4)
    #expect(f.mainList.focusedIndex == 2)
    #expect(f.subList1.focusedIndex == 3)

    // (main7, sub20, subsub210)
    #expect(f.mainList.moveToId(210))
    #expect(f.mainList.focusedId == 210)
    #expect(f.mainList.focusedIndex == 7)
    #expect(f.subList2.focusedIndex == 0)
    #expect(f.subSubList21.focusedIndex == 0)

    // Invalid IDs
    #expect(!f.mainList.moveToId(13))
    #expect(!f.mainList.moveToId(-6))
    #expect(!f.mainList.moveToId(9999))
  }

  @Test func moveNext() {
    let f = Fixture()
    // main0 -> main1
    #expect(f.mainList.moveToId(0))
    #expect(f.mainList.moveNext())
    #expect(f.mainList.focusedId == 1)
    #expect(f.mainList.focusedIndex == 1)

    // main1 -> (main2, sub10)
    #expect(f.mainList.moveNext())
    #expect(f.mainList.focusedId == -1)
    #expect(f.mainList.focusedIndex == 2)
    #expect(f.subList1.focusedIndex == 0)

    // (main2, sub10) -> (main2, sub11)
    #expect(f.mainList.moveNext())
    #expect(f.mainList.focusedId == -2)
    #expect(f.mainList.focusedIndex == 2)
    #expect(f.subList1.focusedIndex == 1)

    // (main2, sub14) -> main3: no rotation
    #expect(f.mainList.moveToId(-5))
    #expect(f.mainList.moveNext())
    #expect(f.mainList.focusedId == 2)
    #expect(f.mainList.focusedIndex == 3)

    // (main7, sub25) -> (main7, sub20, subsub210): rotation
    #expect(f.mainList.moveToId(25))
    #expect(f.mainList.moveNext())
    #expect(f.mainList.focusedId == 210)
    #expect(f.mainList.focusedIndex == 7)
    #expect(f.subList2.focusedIndex == 0)
    #expect(f.subSubList21.focusedIndex == 0)

    // (main7, sub20, subsub210) -> (main7, sub20, subsub211)
    #expect(f.mainList.moveNext())
    #expect(f.mainList.focusedId == 211)
    #expect(f.mainList.focusedIndex == 7)
    #expect(f.subList2.focusedIndex == 0)
    #expect(f.subSubList21.focusedIndex == 1)
  }

  @Test func movePrev() {
    let f = Fixture()
    // main1 -> main0
    #expect(f.mainList.moveToId(1))
    #expect(f.mainList.movePrev())
    #expect(f.mainList.focusedId == 0)
    #expect(f.mainList.focusedIndex == 0)

    // (main2, sub10) -> main1: no rotation
    #expect(f.mainList.moveToId(-1))
    #expect(f.mainList.movePrev())
    #expect(f.mainList.focusedId == 1)

    // (main7, sub20, subsub210) -> (main7, sub25)
    #expect(f.mainList.moveToId(210))
    #expect(f.mainList.movePrev())
    #expect(f.mainList.focusedId == 25)
  }

  @Test func moveNextPage() {
    let f = Fixture()
    // main3 -> main9
    #expect(f.mainList.moveToId(2))
    #expect(f.mainList.moveNextPage())
    #expect(f.mainList.focusedId == 7)

    // main9 -> main0
    #expect(f.mainList.moveNextPage())
    #expect(f.mainList.focusedId == 0)

    // (main2, sub10) -> main9: no ratation
    #expect(f.mainList.moveToId(-1))
    #expect(f.mainList.moveNextPage())
    #expect(f.mainList.focusedId == 7)

    // (main7, sub20, subsub210) -> (main7, sub20, subsub210)
    #expect(f.mainList.moveToId(210))
    #expect(f.mainList.moveNextPage())
    #expect(f.mainList.focusedId == 210)
  }

  @Test func movePrevPage() {
    let f = Fixture()
    // main3 -> main9
    #expect(f.mainList.moveToId(2))
    #expect(f.mainList.movePrevPage())
    #expect(f.mainList.focusedId == 7)

    // main9 -> main0
    #expect(f.mainList.movePrevPage())
    #expect(f.mainList.focusedId == 0)

    // (main2, sub10) -> main9: no ratation
    #expect(f.mainList.moveToId(-1))
    #expect(f.mainList.movePrevPage())
    #expect(f.mainList.focusedId == 7)

    // (main7, sub20, subsub210) -> (main7, sub20, subsub210)
    #expect(f.mainList.moveToId(210))
    #expect(f.mainList.movePrevPage())
    #expect(f.mainList.focusedId == 210)
  }

  @Test func moveToPageIndex() {
    let f = Fixture()
    #expect(f.mainList.moveToId(0))

    // main1
    #expect(f.mainList.moveToPageIndex(1))
    #expect(f.mainList.focusedId == 1)

    // (main2, sub10)
    #expect(f.mainList.moveToPageIndex(2))
    #expect(f.mainList.focusedId == -1)

    // main12
    #expect(f.mainList.moveToId(10))

    // main12 (id 10) is at page index 3 of the last page, whose valid page
    // indexes are [0, 4) as the list has 13 elements in total.
    #expect(f.mainList.moveToPageIndex(3))
    #expect(f.mainList.focusedId == 10)

    // Regression test for https://github.com/google/mozc/issues/1543.
    // Boundary check: page index 4 points to one past the last candidate.
    #expect(!f.mainList.moveToPageIndex(4))
    #expect(f.mainList.focusedId == 10)

    // invalid index
    #expect(!f.mainList.moveToPageIndex(7))
  }

  @Test func clear() {
    let f = Fixture()
    #expect(f.mainList.moveToId(0))

    f.mainList.clear()
    #expect(!f.mainList.moveToId(0))
    #expect(f.mainList.size == 0)

    f.mainList.addCandidate(500, "500")
    f.mainList.addCandidate(501, "501")

    #expect(f.mainList.moveNext())
    #expect(f.mainList.focusedId == 501)
    #expect(f.mainList.focusedIndex == 1)
  }

  @Test func duplication() {
    let mainList = CandidateList(rotate: true)

    mainList.addCandidate(0, "0")
    mainList.addCandidate(1, "1")
    mainList.addCandidate(2, "2")
    mainList.addCandidate(3, "0")  // dup
    mainList.addCandidate(4, "0")  // dup
    mainList.addCandidate(5, "1")  // dup
    let subList = mainList.addSubCandidateList()
    subList.addCandidate(6, "0")  // not dup
    subList.addCandidate(7, "7")
    subList.addCandidate(8, "7")  // dup

    #expect(mainList.size == 4)
    #expect(subList.size == 2)

    mainList.moveToId(3)
    #expect(mainList.focusedId == 0)

    mainList.moveToId(4)
    #expect(mainList.focusedId == 0)

    mainList.moveToId(5)
    #expect(mainList.focusedId == 1)

    mainList.moveToId(6)
    #expect(mainList.focusedId == 6)

    mainList.moveToId(8)
    #expect(mainList.focusedId == 7)
  }

  @Test func focusedId() {
    let emptyList = CandidateList(rotate: true)
    #expect(emptyList.focusedId == 0)
  }

  @Test func setPageSize() {
    let f = Fixture()
    #expect(f.mainList.pageSize == 9)
    // Move to the 10th item.
    #expect(f.mainList.moveToId(7))

    // Make sure the default values.
    #expect(f.mainList.focusedId == 7)
    #expect(f.mainList.focusedIndex == 9)
    // [begin, end)
    var (begin, end) = f.mainList.getPageRange(f.mainList.focusedIndex)
    #expect(begin == 9)
    #expect(end == 13)

    // Change the page size.
    f.mainList.pageSize = 11
    // The id and index should not be changed.
    #expect(f.mainList.focusedId == 7)
    #expect(f.mainList.focusedIndex == 9)

    // The begin and end should be changed.
    (begin, end) = f.mainList.getPageRange(f.mainList.focusedIndex)
    #expect(begin == 0)
    #expect(end == 11)
  }

  @Test func attributes() {
    let mainList = CandidateList(rotate: true)

    mainList.addCandidateWithAttributes(0, "hiragana", A.hiragana)
    mainList.addCandidateWithAttributes(1, "f_katakana", A.fullWidth | A.katakana)
    mainList.addCandidateWithAttributes(2, "h_ascii", A.halfWidth | A.ascii | A.lower)
    mainList.addCandidateWithAttributes(3, "H_ASCII", A.halfWidth | A.ascii | A.upper)
    // dup entry
    mainList.addCandidateWithAttributes(4, "h_ascii", A.halfWidth | A.ascii | A.lower)
    mainList.addCandidateWithAttributes(5, "H_Ascii", A.halfWidth | A.ascii)
    mainList.addCandidateWithAttributes(6, "f_ascii", A.fullWidth | A.ascii | A.lower)

    #expect(mainList.size == 6)

    #expect(!mainList.moveNextAttributes(A.halfWidth | A.katakana))

    // h_ascii
    #expect(mainList.moveNextAttributes(A.halfWidth | A.ascii))
    #expect(mainList.focusedId == 2)
    #expect(mainList.focusedCandidate.attributes == (A.halfWidth | A.ascii | A.lower))

    // H_ASCII
    #expect(mainList.moveNextAttributes(A.halfWidth | A.ascii))
    #expect(mainList.focusedId == 3)
    #expect(mainList.focusedCandidate.attributes == (A.halfWidth | A.ascii | A.upper))

    // ID:4 (h_ascii) should be skipped because it's a dup.

    // H_Ascii
    #expect(mainList.moveNextAttributes(A.halfWidth | A.ascii))
    #expect(mainList.focusedId == 5)
    #expect(mainList.focusedCandidate.attributes == (A.halfWidth | A.ascii))

    // h_ascii / Looped
    #expect(mainList.moveNextAttributes(A.halfWidth | A.ascii))
    #expect(mainList.focusedId == 2)
  }

  @Test func attributes2() {
    let mainList = CandidateList(rotate: true)

    mainList.addCandidate(0, "dvd")
    mainList.addCandidate(1, "DVD")
    mainList.addCandidateWithAttributes(2, "f_dvd", A.hiragana)
    // id#3 is dup
    mainList.addCandidateWithAttributes(3, "f_dvd", A.fullWidth | A.katakana)
    mainList.addCandidateWithAttributes(4, "h_dvd", A.halfWidth | A.ascii)
    // id#5 is dup
    mainList.addCandidateWithAttributes(5, "h_dvd", A.halfWidth | A.ascii | A.lower)
    mainList.addCandidateWithAttributes(6, "h_DVD", A.halfWidth | A.ascii | A.upper)
    mainList.addCandidateWithAttributes(7, "h_Dvd", A.halfWidth | A.ascii | A.capitalized)
    // id#8 is dup
    mainList.addCandidateWithAttributes(8, "f_dvd", A.fullWidth | A.ascii)
    // id#9 is dup
    mainList.addCandidateWithAttributes(9, "f_dvd", A.fullWidth | A.ascii | A.lower)
    mainList.addCandidateWithAttributes(10, "f_DVD", A.fullWidth | A.ascii | A.upper)
    mainList.addCandidateWithAttributes(11, "f_Dvd", A.fullWidth | A.ascii | A.capitalized)
    // id#12 is dup
    mainList.addCandidateWithAttributes(12, "h_dvd", A.halfWidth | A.katakana)

    #expect(mainList.size == 8)

    #expect(mainList.moveNextAttributes(A.fullWidth | A.ascii))

    #expect(mainList.focusedId == 2)
    #expect(
      mainList.focusedCandidate.attributes
        == (A.hiragana | A.katakana | A.fullWidth | A.ascii | A.lower))

    #expect(mainList.moveNextAttributes(A.fullWidth | A.ascii))
    #expect(mainList.focusedId == 10)
    #expect(mainList.focusedCandidate.attributes == (A.fullWidth | A.ascii | A.upper))

    #expect(mainList.moveNextAttributes(A.fullWidth | A.ascii))
    #expect(mainList.focusedId == 11)
    #expect(mainList.focusedCandidate.attributes == (A.fullWidth | A.ascii | A.capitalized))

    #expect(mainList.moveNextAttributes(A.fullWidth | A.ascii))
    #expect(mainList.focusedId == 2)
  }

  @Test func attributesWithSubList() {
    let mainList = CandidateList(rotate: true)
    mainList.addCandidate(0, "kanji")

    let subList = mainList.addSubCandidateList()
    subList.addCandidateWithAttributes(1, "hiragana", A.hiragana)
    subList.addCandidateWithAttributes(2, "f_katakana", A.fullWidth | A.katakana)
    subList.addCandidateWithAttributes(3, "h_ascii", A.halfWidth | A.ascii | A.lower)
    subList.addCandidateWithAttributes(4, "H_ASCII", A.halfWidth | A.ascii | A.upper)
    subList.addCandidateWithAttributes(5, "H_Ascii", A.halfWidth | A.ascii | A.capitalized)
    #expect(mainList.size == 2)
    #expect(subList.size == 5)

    // h_ascii
    #expect(mainList.moveNextAttributes(A.halfWidth | A.ascii))
    #expect(mainList.focusedId == 3)
    #expect(subList.focusedCandidate.attributes == (A.halfWidth | A.ascii | A.lower))

    // H_ASCII
    #expect(mainList.moveNextAttributes(A.halfWidth | A.ascii))
    #expect(mainList.focusedId == 4)
    #expect(subList.focusedCandidate.attributes == (A.halfWidth | A.ascii | A.upper))

    // H_Ascii
    #expect(mainList.moveNextAttributes(A.halfWidth | A.ascii))
    #expect(mainList.focusedId == 5)
    #expect(subList.focusedCandidate.attributes == (A.halfWidth | A.ascii | A.capitalized))

    // h_ascii / Looped
    #expect(mainList.moveNextAttributes(A.halfWidth | A.ascii))
    #expect(mainList.focusedId == 3)
    #expect(subList.focusedCandidate.attributes == (A.halfWidth | A.ascii | A.lower))
  }

  @Test func getDeepestFocusedCandidate() {
    let f = Fixture()
    #expect(f.mainList.moveToPageIndex(2))
    #expect(f.mainList.focusedCandidate.id == 0)
    #expect(f.mainList.focusedCandidate.hasSubcandidateList())

    let deepestCandidate = f.mainList.getDeepestFocusedCandidate()
    #expect(deepestCandidate.id == -1)
    #expect(!deepestCandidate.hasSubcandidateList())
  }

  @Test func nextAvailableId() {
    let f = Fixture()
    #expect(f.mainList.nextAvailableId == 213)
    #expect(f.subList1.nextAvailableId == 0)
    #expect(f.subList2.nextAvailableId == 213)
    #expect(f.subSubList21.nextAvailableId == 213)

    // Append duplicate candidate.
    // next_available_id should be incremented.
    f.subSubList21.addCandidate(213, "212")
    #expect(f.mainList.nextAvailableId == 214)
    #expect(f.subSubList21.nextAvailableId == 214)
  }
}
