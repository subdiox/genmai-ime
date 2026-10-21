// Port of mozc/src/converter/converter_main.cc (3.35.6354).
//
// Reads commands from stdin (one per line; see `ConverterMain.execCommand`)
// and prints the resulting segments in the same text format as the C++
// converter_main, which is the parity oracle (Tools/oracle.sh).
//
// Deviations from C++:
// - absl flags are parsed by `FlagParser` (`--flag=value`, `--flag value`,
//   `--flag` / `--noflag` for booleans). `--helpfull` etc. are not supported.
// - Default data paths are relative to the current directory like C++, but
//   point at this repository's layout: `Data/genmai.data` (default / oss),
//   `Data/mock_genmai.data` (mock); id.def: `Vendor/mozc/src/data/
//   dictionary_oss/id.def` (default / oss) or `Vendor/mozc/src/data/test/
//   dictionary/id.def` (mock).
// - The command interpreter (ConverterMain) and the printing functions are in
//   Sources/GenmaiCore/Engine/ConverterMain.swift, shared with the parity tests.
// - LOG(...) messages go to stderr; CHECK failures exit with status 1.
// - Test-only flag `--fake_time_for_testing=<unix seconds>` (not in C++):
//   the clock starts at that time and advances in real time. The parity
//   fixtures record when the oracle ran, so date/time candidates (e.g. いま →
//   20:31) can be reproduced (Tools/compare_oracle.sh).

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol

// MARK: - Flags

struct Flags {
  var maxConversionCandidatesSize: Int32 = 200
  var userProfileDir = ""
  var engineName = "default"
  var engineType = "desktop"
  var maxCandidatesToShow = 100
  var showMetaCandidates = false
  var engineDataPath = ""
  var magic: [UInt8] = []
  var idDef = ""
  var decoderExperimentParams = ""
  var supplementalModel = ""
  var fakeTimeForTesting: Int64? = nil
}

func fatal(_ message: String) -> Never {
  FileHandle.standardError.write(Data("F \(message)\n".utf8))
  exit(1)
}

func logWarning(_ message: String) {
  FileHandle.standardError.write(Data("W \(message)\n".utf8))
}

/// Minimal absl::flags compatible parser.
enum FlagParser {
  static func parse(_ arguments: [String]) -> Flags {
    var flags = Flags()
    var i = 0
    func parseBool(_ name: String, _ value: String?) -> Bool {
      guard let value else { return true }
      switch value.lowercased() {
      case "true", "t", "yes", "y", "1": return true
      case "false", "f", "no", "n", "0": return false
      default: fatal("Illegal value '\(value)' specified for boolean flag '\(name)'")
      }
    }
    while i < arguments.count {
      let arg = arguments[i]
      i += 1
      guard arg.hasPrefix("-"), arg != "-", arg != "--" else {
        continue  // Positional arguments are ignored.
      }
      var body = arg.drop { $0 == "-" }
      var value: String? = nil
      if let eq = body.firstIndex(of: "=") {
        value = String(body[body.index(after: eq)...])
        body = body[..<eq]
      }
      let name = String(body)
      if name == "show_meta_candidates" {
        flags.showMetaCandidates = parseBool(name, value)
        continue
      }
      if name == "noshow_meta_candidates", value == nil {
        flags.showMetaCandidates = false
        continue
      }
      func takeValue() -> String {
        if let value { return value }
        guard i < arguments.count else { fatal("Missing the value for the flag '\(name)'") }
        i += 1
        return arguments[i - 1]
      }
      switch name {
      case "max_conversion_candidates_size":
        let v = takeValue()
        guard let n = Int32(v) else { fatal("Illegal value '\(v)' specified for flag '\(name)'") }
        flags.maxConversionCandidatesSize = n
      case "user_profile_dir": flags.userProfileDir = takeValue()
      case "engine_name": flags.engineName = takeValue()
      case "engine_type": flags.engineType = takeValue()
      case "max_candidates_to_show":
        let v = takeValue()
        guard let n = Int(v), n >= 0 else {
          fatal("Illegal value '\(v)' specified for flag '\(name)'")
        }
        flags.maxCandidatesToShow = n
      case "engine_data_path": flags.engineDataPath = takeValue()
      case "magic": flags.magic = Array(takeValue().utf8)
      case "id_def": flags.idDef = takeValue()
      case "decoder_experiment_params": flags.decoderExperimentParams = takeValue()
      case "supplemental_model": flags.supplementalModel = takeValue()
      case "fake_time_for_testing":
        let v = takeValue()
        guard let t = Int64(v) else { fatal("Illegal value '\(v)' specified for flag '\(name)'") }
        flags.fakeTimeForTesting = t
      default:
        fatal("Unknown command line flag '\(name)'")
      }
    }
    return flags
  }
}

let flags = FlagParser.parse(Array(CommandLine.arguments.dropFirst()))

// MARK: - main

/// The clock of `--fake_time_for_testing`: starts at `base` and advances in
/// real time.
final class FakeClock: ClockInterface {
  private let base: Date
  private let start = Date()

  init(_ base: Date) { self.base = base }

  func getAbslTime() -> Date { base.addingTimeInterval(Date().timeIntervalSince(start)) }
  func getTimeZone() -> TimeZone { TimeZone.current }
}

func selectDataFileFromName(_ upstreamRunfilesDir: String, _ engineName: String) -> (String, [UInt8]) {
  let kNameAndPath: [(String, String, [UInt8])] = [
    ("default", "Data/genmai.data", [0xEF] + Array("MOZC\r\n".utf8)),
    ("oss", "Data/genmai.data", [0xEF] + Array("MOZC\r\n".utf8)),
    ("mock", "Data/mock_genmai.data", Array("MOCK".utf8)),
  ]
  for entry in kNameAndPath where engineName == entry.0 {
    return (FileUtil.joinPath(upstreamRunfilesDir, entry.1), entry.2)
  }
  return ("", [])
}

func selectIdDefFromName(_ upstreamRunfilesDir: String, _ engineName: String) -> String {
  let kNameAndPath: [(String, String)] = [
    ("default", "Vendor/mozc/src/data/dictionary_oss/id.def"),
    ("oss", "Vendor/mozc/src/data/dictionary_oss/id.def"),
    ("mock", "Vendor/mozc/src/data/test/dictionary/id.def"),
  ]
  for entry in kNameAndPath where engineName == entry.0 {
    return FileUtil.joinPath(upstreamRunfilesDir, entry.1)
  }
  return ""
}

func isConsistentEngineNameAndType(_ engineName: String, _ engineType: String) -> Bool {
  let kConsistentPairs: Set<String> = [
    "oss/desktop", "mock/desktop", "mock/mobile", "default/desktop", "/desktop", "/mobile",
  ]
  return kConsistentPairs.contains("\(engineName)/\(engineType)")
}

func main() {
  if let fakeTime = flags.fakeTimeForTesting {
    Clock.setClockForUnitTest(FakeClock(Date(timeIntervalSince1970: TimeInterval(fakeTime))))
  }

  if !flags.userProfileDir.isEmpty {
    SystemUtil.setUserProfileDirectory(flags.userProfileDir)
  }

  let upstreamRunfilesDir = "."
  var engineDataPathFlag = flags.engineDataPath
  var magicFlag = flags.magic
  if engineDataPathFlag.isEmpty {
    let pathAndMagic = selectDataFileFromName(upstreamRunfilesDir, flags.engineName)
    engineDataPathFlag = pathAndMagic.0
    magicFlag = pathAndMagic.1
  }
  if engineDataPathFlag.isEmpty {
    fatal(
      "--engine_data_path or --engine is invalid: --engine_data_path=\(engineDataPathFlag) --engine_name=\(flags.engineName)"
    )
  }

  var idDefFlag = flags.idDef
  if idDefFlag.isEmpty {
    let genmaiIdfileDir = "."
    idDefFlag = selectIdDefFromName(genmaiIdfileDir, flags.engineName)
  }

  print(
    "Engine type: \(flags.engineType)\nData file: \(engineDataPathFlag)\nid.def: \(idDefFlag)\nUser profile dir: \(flags.userProfileDir)"
  )

  let dataManager: DataManager
  do {
    dataManager =
      magicFlag.isEmpty
      ? try DataManager.createFromFile(engineDataPathFlag)
      : try DataManager.createFromFile(engineDataPathFlag, magic: magicFlag)
  } catch {
    fatal("Check failed: data_manager is OK (\(error))")
  }

  var config = ConfigHandler.defaultConfig()
  var request = Genmai_Commands_Request()
  let engine: Engine
  do {
    engine = try Engine.createEngine(dataManager)
  } catch {
    fatal("Engine::CreateEngine failed: \(error)")
  }
  if flags.engineType == "desktop" {
    // Uses the default request for desktop.
  } else if flags.engineType == "mobile" {
    RequestTestUtil.fillMobileRequest(&request)
    config.useKanaModifierInsensitiveConversion = true
    config.useTypingCorrection = true
  } else {
    fatal("Invalid type: --engine_type=\(flags.engineType)")
  }

  if !flags.decoderExperimentParams.isEmpty {
    let textproto = flags.decoderExperimentParams
    do {
      let params = try Genmai_Commands_DecoderExperimentParams(textFormatString: textproto)
      let bytes: [UInt8] = try params.serializedBytes()
      try request.decoderExperimentParams.merge(serializedBytes: bytes)
      GenmaiLog.info("DecoderExperimentParams was set:\n\(request.decoderExperimentParams)")
    } catch {
      fatal("Invalid DecoderExperimentParams: \(textproto)")
    }
  }

  if !isConsistentEngineNameAndType(flags.engineName, flags.engineType) {
    logWarning("Engine name and type do not match.")
  }

  var options = ConverterMain.Options()
  options.maxConversionCandidatesSize = flags.maxConversionCandidatesSize
  options.maxCandidatesToShow = flags.maxCandidatesToShow
  options.showMetaCandidates = flags.showMetaCandidates
  options.idDef = idDefFlag
  let converterMain = ConverterMain(engine, request, config, options)

  converterMain.loadSupplementalModel(flags.supplementalModel)

  converterMain.runLoop()
}

main()
