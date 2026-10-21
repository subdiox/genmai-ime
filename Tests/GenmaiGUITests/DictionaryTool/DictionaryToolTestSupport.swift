import Foundation
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol

/// A session backend that records the commands the dictionary tool / word register dialog send.
@MainActor
final class RecordingBackend: SessionBackend {
  var inputs: [Genmai_Commands_Input] = []
  var reloadCount: Int { inputs.filter { $0.type == .reload }.count }

  func evalCommand(_ input: Genmai_Commands_Input) -> Genmai_Commands_Output? {
    inputs.append(input)
    var output = Genmai_Commands_Output()
    output.id = input.type == .createSession ? 1 : input.id
    output.errorCode = .sessionSuccess
    return output
  }
}

@MainActor
func makeRecordingClient() -> (InProcessClient, RecordingBackend) {
  let backend = RecordingBackend()
  let client = InProcessClient(
    backend: backend, initialConfig: Genmai_Config_Config(), directModeKeysExtractor: { _ in [] })
  return (client, backend)
}

/// Runs `body` with a temporary user profile (the process mutex files live there) and a storage path in it.
func withTempDictionaryFile<R>(_ body: (String) throws -> R) rethrows -> R {
  try SystemUtil.withTempUserProfile { dir in
    try body(FileUtil.joinPath(dir, "user_dictionary.db"))
  }
}
