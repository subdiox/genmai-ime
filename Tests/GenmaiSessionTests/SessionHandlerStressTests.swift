// Port of mozc/src/session/session_handler_stress_test.cc (3.35.6354).
//
// Sends 2500 random key events (RandomKeyEventsGenerator), split into 32
// shards, through SessionHandlerTool with the OSS engine (EngineFactory) in a
// temporary user profile; every TestSendKey / SendKey must succeed.
//
// Deviations from C++:
// - --random_seed: MOZC_STRESS_RANDOM_SEED (the shard index is added like the
//   C++). Without it, the C++ uses a non-deterministic generator; here the
//   shard index itself is the seed so that failures are reproducible.
// - --set_mobile_request: MOZC_STRESS_MOBILE=1.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol
import Testing

@testable import GenmaiSession

private let kTotalEventSize = 2500
private let kShardCount = 32
private let kEventsPerShard = kTotalEventSize / kShardCount

@Suite(
  .enabled(
    if: FileManager.default.fileExists(atPath: OssDataManager.defaultDataPath),
    "genmai.data is missing; run Tools/build_oracle.sh"))
struct SessionHandlerStressTest {
  @Test(arguments: 0..<kShardCount)
  func basicStressTest(_ shard: Int) throws {
    let env = ProcessInfo.processInfo.environment
    let baseSeed = env["MOZC_STRESS_RANDOM_SEED"].flatMap { UInt32($0) } ?? 0
    let seed = UInt64(baseSeed &+ UInt32(shard))
    try SystemUtil.withTempUserProfile { _ in
      let client = SessionHandlerTool(try EngineFactory.create())
      var generator = RandomKeyEventsGenerator(Random(seed: seed))
      var keys: [Genmai_Commands_KeyEvent] = []
      var output = Genmai_Commands_Output()
      var keyeventsSize = 0
      try #require(client.createSession())
      if env["MOZC_STRESS_MOBILE"] == "1" {
        var request = Genmai_Commands_Request()
        RequestTestUtil.fillMobileRequest(&request)
        _ = client.setRequest(request, &output)
      }
      while keyeventsSize < kEventsPerShard {
        keys.removeAll()
        generator.generateSequence(&keys)
        for key in keys {
          keyeventsSize += 1
          #expect(client.testSendKey(key, &output))
          #expect(client.sendKey(key, &output))
        }
      }
      #expect(client.deleteSession())
    }
  }
}
