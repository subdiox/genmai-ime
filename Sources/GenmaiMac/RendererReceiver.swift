// Port of mozc/src/mac/renderer_receiver.{h,mm} and the protocols of mac/common.h (3.35.6354).
//
// In C++ the renderer runs in its own process and sends clicked candidates (serialized SessionCommand) and
// results back over NSConnection; RendererReceiver forwards them to the active controller. The Swift renderer
// runs in the IME process, so RendererReceiver is the SendCommandInterface given to the CandidateController
// and forwards directly to the current controller (`setCurrentController` is called in -activateServer:).

import Foundation
import GenmaiClient
import GenmaiProtocol

@MainActor
public final class RendererReceiver: SendCommandInterface {
  /// The current active controller that handles events from the renderer.
  public private(set) weak var currentController: (any ControllerCallback)?

  public init() {}

  public func setCurrentController(_ controller: (any ControllerCallback)?) {
    currentController = controller
  }

  /// `sendData:` with a serialized SessionCommand (kept for parity with the IPC protocol).
  public func sendData(_ data: Data) {
    guard currentController != nil, let command = try? SessionCommand(serializedBytes: data) else {
      return
    }
    currentController?.sendCommand(command)
  }

  /// `outputResult:` with a serialized Output.
  public func outputResult(_ result: Data) {
    guard let output = try? Output(serializedBytes: result) else {
      return
    }
    currentController?.outputResult(output)
  }

  // SendCommandInterface: called by the candidate window on mouse clicks.
  @discardableResult
  public func sendCommand(_ command: SessionCommand) -> Output? {
    currentController?.sendCommand(command)
    return Output()
  }
}
