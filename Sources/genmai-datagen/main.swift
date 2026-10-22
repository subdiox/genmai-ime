// genmai-datagen: builds Mozc data sets (genmai.data / mock_genmai.data) from the
// sources in Vendor/mozc/src/data without Bazel, Python or C++.  Replaces
// `//data_manager/oss:mozc_dataset_for_oss` and
// `//data_manager/testing:mozc_dataset_for_testing` (see
// data_manager/mozc_data.bzl).

import Foundation
import GenmaiBase
import GenmaiDataGen

func usage() -> Never {
  let text = """
    usage:
      genmai-datagen build --set oss|mock --output FILE [--src-root DIR] [--usage-dict FILE]
                         [--zip-code-ken-all FILE --zip-code-jigyosyo FILE] [--work-dir DIR]
                         [--compare REF.data] [--timings]
                         [--aux-dictionary FILE --filtered-dictionary FILE]  (oss: skip the dictionary preprocessing)
      genmai-datagen sections --set oss|mock --only GEN[,GEN...] --compare REF.data [options as above]
          Runs only the named generators (\(DataGenerator.allCases.map(\.rawValue).joined(separator: ", ")))
          and compares their sections with those of REF.data.  --user-pos-manager-data FILE (e.g.
          bazel-bin/data_manager/oss/user_pos_manager.data) skips the POS generators.
      genmai-datagen oss-dictionary --output-dir DIR [--src-root DIR] [--zip-code-ken-all FILE --zip-code-jigyosyo FILE]
          Writes zip_code.tsv, dictionary.txt (filtered) and aux_dictionary.txt.
      genmai-datagen diff ACTUAL.data EXPECTED.data
    defaults: --src-root ./Vendor/mozc/src; --usage-dict omitted = no usage sections.
    """
  FileHandle.standardError.write(Data((text + "\n").utf8))
  exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
args.removeFirst()
var options: [String: String] = [:]
var flags: Set<String> = []
var positional: [String] = []
var i = 0
while i < args.count {
  let a = args[i]
  if a.hasPrefix("--") {
    let key = String(a.dropFirst(2))
    if key == "timings" {
      flags.insert(key)
    } else if let eq = key.firstIndex(of: "=") {
      options[String(key[..<eq])] = String(key[key.index(after: eq)...])
    } else {
      guard i + 1 < args.count else { usage() }
      options[key] = args[i + 1]
      i += 1
    }
  } else {
    positional.append(a)
  }
  i += 1
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("genmai-datagen: \(message)\n".utf8))
  exit(1)
}

let srcRoot = options["src-root"] ?? FileManager.default.currentDirectoryPath + "/Vendor/mozc/src"

@MainActor func ossDictionarySources() -> OssDictionarySources {
  OssDictionarySources(
    srcRoot: srcRoot, zipCodeKenAll: options["zip-code-ken-all"], zipCodeJigyosyo: options["zip-code-jigyosyo"])
}

@MainActor func makeSources() throws -> DataGenSources {
  switch options["set"] {
  case "mock":
    return .mock(srcRoot: srcRoot, usageDict: options["usage-dict"])
  case "oss":
    if let aux = options["aux-dictionary"], let filtered = options["filtered-dictionary"] {
      return .oss(srcRoot: srcRoot, auxDictionary: aux, filteredDictionary: filtered, usageDict: options["usage-dict"])
    }
    let workDir =
      options["work-dir"]
      ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("genmai-datagen-\(getpid())")
    try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
    let start = Date()
    let (aux, filtered) = try ossDictionarySources().generate(workDir: workDir)
    if flags.contains("timings") {
      print(timingLine("oss_dictionary (zip+filtered+aux)", Date().timeIntervalSince(start)))
    }
    return .oss(srcRoot: srcRoot, auxDictionary: aux, filteredDictionary: filtered, usageDict: options["usage-dict"])
  default:
    usage()
  }
}

func timingLine(_ name: String, _ seconds: Double) -> String {
  "  " + name.padding(toLength: 34, withPad: " ", startingAt: 0) + String(format: "%7.2f s", seconds)
}

func printTimings(_ timings: [GenmaiDataSet.Timing]) {
  for t in timings.sorted(by: { $0.seconds > $1.seconds }) {
    print(timingLine(t.generator.rawValue, t.seconds))
  }
}

do {
  switch command {
  case "build":
    guard let output = options["output"] else { usage() }
    let start = Date()
    let sources = try makeSources()
    let (image, timings) = try await GenmaiDataSet.generate(sources)
    try FileUtil.setContents(output, image)
    if flags.contains("timings") { printTimings(timings) }
    print(
      String(format: "wrote %@ (%d bytes) in %.1f s", output as NSString, image.count, Date().timeIntervalSince(start)))
    if let ref = options["compare"] {
      let expected = try FileUtil.getContentBytes(ref)
      if let report = DataSetDiff.report(actual: image, expected: expected) {
        print("DIFFERS from \(ref):\n\(report)")
        exit(1)
      }
      print("identical to \(ref)")
    }
  case "sections":
    guard let only = options["only"], let ref = options["compare"] else { usage() }
    var gens: Set<DataGenerator> = []
    for name in only.split(separator: ",") {
      guard let g = DataGenerator(rawValue: String(name)) else { fail("unknown generator \(name)") }
      gens.insert(g)
    }
    let sources = try makeSources()
    let upm = try options["user-pos-manager-data"].map { try FileUtil.getContentBytes($0) }
    let (outputs, timings) = try await GenmaiDataSet.generateSections(sources, only: gens, userPosManagerData: upm)
    if flags.contains("timings") { printTimings(timings) }
    let expected = try FileUtil.getContentBytes(ref)
    let refSections = Dictionary(
      try DataSetDiff.sections(expected).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    var ok = true
    for e in GenmaiDataSet.entries(withUsage: sources.usageDict != nil) where gens.contains(e.generator) {
      guard let actual = outputs[e.generator]?[e.name] else {
        print("\(e.name): not produced")
        ok = false
        continue
      }
      guard let r = refSections[e.name] else {
        print("\(e.name): not in reference")
        ok = false
        continue
      }
      let exp = Array(expected[r.offset..<(r.offset + r.size)])
      if let d = DataSetDiff.compareBytes(actual, exp) {
        print("\(e.name) [\(e.generator.rawValue)]: DIFFERS: \(d)")
        ok = false
      } else {
        print("\(e.name) [\(e.generator.rawValue)]: identical (\(actual.count) bytes)")
      }
    }
    exit(ok ? 0 : 1)
  case "oss-dictionary":
    guard let dir = options["output-dir"] else { usage() }
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let (aux, filtered) = try ossDictionarySources().generate(workDir: dir)
    print("wrote \(aux), \(filtered)")
  case "diff":
    guard positional.count == 2 else { usage() }
    let a = try FileUtil.getContentBytes(positional[0])
    let b = try FileUtil.getContentBytes(positional[1])
    if let report = DataSetDiff.report(actual: a, expected: b) {
      print(report)
      exit(1)
    }
    print("identical")
  default:
    usage()
  }
} catch {
  fail("\(error)")
}
