// Port of mozc/src/rewriter/command_rewriter_test.cc (3.35.6354).

import GenmaiProtocol
import Testing
@testable import GenmaiCore

@Suite struct CommandRewriterTests {
  private var request = Genmai_Commands_Request()
  private var config = ConfigHandler.defaultConfig()

  private static func commandCandidatesSize(_ segment: Segment) -> Int {
    var result = 0
    for i in 0..<segment.candidatesSize
    where segment.candidate(i).attributes & Attribute.commandCandidate != 0 {
      result += 1
    }
    return result
  }

  private static func getCommandCandidateValue(_ segment: Segment) -> String {
    for i in 0..<segment.candidatesSize
    where segment.candidate(i).attributes & Attribute.commandCandidate != 0 {
      return segment.candidate(i).value
    }
    return ""
  }

  private static func convReq(_ config: Genmai_Config_Config, _ request: Genmai_Commands_Request)
    -> ConversionRequest
  {
    ConversionRequestBuilder().setConfig(config).setRequest(request).build()
  }

  @Test func rewrite() {
    let rewriter = CommandRewriter()
    let segments = Segments()
    let seg = segments.pushBackSegment()

    let convreq = Self.convReq(config, request)
    #expect(!rewriter.rewrite(convreq, segments))

    do {
      let candidate = seg.addCandidate()
      seg.setKey("こまんど")
      candidate.value = "コマンド"
      #expect(rewriter.rewrite(convreq, segments))
      #expect(Self.commandCandidatesSize(seg) == 2)
      seg.clearCandidates()
    }

    do {
      let candidate = seg.addCandidate()
      seg.setKey("さじぇすと")
      candidate.value = "サジェスト"
      #expect(rewriter.rewrite(convreq, segments))
      #expect(Self.commandCandidatesSize(seg) == 1)
      seg.clearCandidates()
    }

    do {
      let candidate = seg.addCandidate()
      seg.setKey("ひみつ")
      candidate.value = "秘密"
      #expect(rewriter.rewrite(convreq, segments))
      #expect(Self.commandCandidatesSize(seg) == 1)
      seg.clearCandidates()
    }

    do {
      let candidate = seg.addCandidate()
      seg.setKey("きょうと")
      candidate.value = "京都"
      #expect(!rewriter.rewrite(convreq, segments))
      #expect(Self.commandCandidatesSize(seg) == 0)
      seg.clearCandidates()
    }

    do {
      // don't trigger when multiple segments.
      let candidate = seg.addCandidate()
      seg.setKey("こまんど")
      candidate.value = "コマンド"
      let seg2 = segments.pushBackSegment()
      let candidate2 = seg2.addCandidate()
      seg2.setKey("です")
      candidate2.value = "です"
      #expect(!rewriter.rewrite(convreq, segments))
      #expect(Self.commandCandidatesSize(seg) == 0)
    }
  }

  @Test mutating func valueCheck() {
    let rewriter = CommandRewriter()
    let segments = Segments()
    let seg = segments.pushBackSegment()

    do {
      let candidate = seg.addCandidate()
      seg.setKey("さじぇすと")
      candidate.value = "サジェスト"
      config.presentationMode = false
      let convreq = Self.convReq(config, request)
      #expect(rewriter.rewrite(convreq, segments))
      #expect(Self.getCommandCandidateValue(seg) == "サジェスト機能の一時停止")
      seg.clearCandidates()
    }

    do {
      let candidate = seg.addCandidate()
      seg.setKey("さじぇすと")
      candidate.value = "サジェスト"
      config.presentationMode = true
      let convreq = Self.convReq(config, request)
      #expect(rewriter.rewrite(convreq, segments))
      #expect(Self.getCommandCandidateValue(seg) == "サジェスト機能を元に戻す")
      seg.clearCandidates()
    }

    do {
      let candidate = seg.addCandidate()
      seg.setKey("ひみつ")
      candidate.value = "秘密"
      config.incognitoMode = false
      let convreq = Self.convReq(config, request)
      #expect(rewriter.rewrite(convreq, segments))
      #expect(Self.getCommandCandidateValue(seg) == "シークレットモードをオン")
      seg.clearCandidates()
    }

    do {
      let candidate = seg.addCandidate()
      seg.setKey("ひみつ")
      candidate.value = "秘密"
      config.incognitoMode = true
      let convreq = Self.convReq(config, request)
      #expect(rewriter.rewrite(convreq, segments))
      #expect(Self.getCommandCandidateValue(seg) == "シークレットモードをオフ")
      seg.clearCandidates()
    }
  }
}
