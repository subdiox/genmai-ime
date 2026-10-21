// Port of mozc/src/renderer/renderer_interface.h (3.35.6354).
//
// In C++ the IME talks to the candidate renderer process (mozc_renderer) through RendererClient over IPC
// (renderer/renderer_client, renderer_server, renderer/mac/mac_server*). The Swift IME renders the candidate
// window in-process, so the controller implements this interface directly.

import GenmaiClient
import GenmaiProtocol

public typealias RendererCommand = Genmai_Commands_RendererCommand

@MainActor
public protocol RendererInterface: AnyObject {
  /// Activate candidate window.
  /// Activate must not have any visible change.
  /// If the renderer is already activated, this method does nothing and return false.
  @discardableResult func activate() -> Bool

  /// return true if the renderer is available
  func isAvailable() -> Bool

  /// exec stateless rendering command
  @discardableResult func execCommand(_ command: RendererCommand) -> Bool

  /// set mouse callback handler.
  func setSendCommandInterface(_ sendCommandInterface: (any SendCommandInterface)?)
}

extension RendererInterface {
  public func setSendCommandInterface(_ sendCommandInterface: (any SendCommandInterface)?) {}
}
