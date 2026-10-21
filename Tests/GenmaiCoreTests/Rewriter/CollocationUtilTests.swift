// Port of mozc/src/rewriter/collocation_util_test.cc (3.35.6354).

import Testing
@testable import GenmaiCore

struct CollocationUtilTests {
  @Test func getNormalizedScript() {
    #expect(CollocationUtil.getNormalizedScript("あいうえお", true) == "あいうえお")
    #expect(CollocationUtil.getNormalizedScript("あいうえお", false) == "あいうえお")

    #expect(CollocationUtil.getNormalizedScript("1個", true) == "個")
    #expect(CollocationUtil.getNormalizedScript("1個", false) == "1個")

    #expect(CollocationUtil.getNormalizedScript("１個", true) == "個")
    #expect(CollocationUtil.getNormalizedScript("１個", false) == "１個")

    #expect(CollocationUtil.getNormalizedScript("", true) == "")
    #expect(CollocationUtil.getNormalizedScript("", false) == "")

    #expect(CollocationUtil.getNormalizedScript("＄", true) == "")
    #expect(CollocationUtil.getNormalizedScript("＄", false) == "")

    #expect(CollocationUtil.getNormalizedScript("等々", true) == "等々")
    #expect(CollocationUtil.getNormalizedScript("等々", false) == "等々")

    #expect(CollocationUtil.getNormalizedScript("％%％", true) == "%%%")
    #expect(CollocationUtil.getNormalizedScript("％%％", false) == "%%%")
  }
}
