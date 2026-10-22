// Port of mozc/src/session/ime_context.{h,cc} (3.35.6354).
//
// ImeContext class contains the whole internal variables representing
// a session.
//
// Swift notes: the C++ `shared_ptr<const Request/Config>` members are held as
// protobuf values; the KeyMapManager (immutable after construction) is shared
// by reference. The copy constructor (used for the undo stack) is
// `init(copying:)`, which clones the converter like the C++ one.

import Foundation
import GenmaiBase
import GenmaiCore
import GenmaiProtocol

private let kDefaultKeyMapManager = KeyMapManager()

public final class ImeContext {
  public enum State: Int, Sendable {
    case none = 0
    case direct = 1
    case precomposition = 2
    case composition = 4
    case conversion = 8
  }

  // Separate copyable data and non-copyable data to
  // easily overload copy operator.
  struct CopyableData {
    // TODO(team): Actual use of |create_time| is to keep the time when the
    // session holding this instance is created and not the time when this
    // instance is created. We may want to move out |create_time| from
    // ImeContext to Session, or somewhere more appropriate.
    var createTime = Date.distantPast
    var lastCommandTime = Date.distantPast

    var request: Genmai_Commands_Request
    var config: Genmai_Config_Config
    var keyMapManager: KeyMapManager

    var composer: Composer
    var keyEventTransformer = KeyEventTransformer()

    var state: State = .none
    var clientCapability = Genmai_Commands_Capability()
    var applicationInfo = Genmai_Commands_ApplicationInfo()
    var clientContext = Genmai_Commands_Context()

    // Storing the last output consisting of the last result and the
    // last performed command.
    var output = Genmai_Commands_Output()

    init() {
      request = getSharedDefaultRequest()
      config = ConfigHandler.getSharedDefaultConfig()
      keyMapManager = kDefaultKeyMapManager
      composer = Composer(Table.getSharedDefaultTable(), request, config)
      keyEventTransformer.reloadConfig(config)
    }
  }

  var data = CopyableData()

  // converter_ should explicitly be copied via Clone() method.
  private var converterImpl: (any EngineConverterInterface)?

  public init() {}

  public init(_ converter: (any EngineConverterInterface)?) {
    converterImpl = converter
  }

  /// C++ copy constructor.
  public init(copying src: ImeContext) {
    data = src.data
    if let converter = src.converterImpl {
      converterImpl = converter.clone()
    }
  }

  public var createTime: Date {
    get { data.createTime }
    set { data.createTime = newValue }
  }

  public var lastCommandTime: Date {
    get { data.lastCommandTime }
    set { data.lastCommandTime = newValue }
  }

  public var composer: Composer {
    get { data.composer }
    set { data.composer = newValue }
  }

  /// Mutating access to the composer (C++ `mutable_composer()`).
  public func withMutableComposer<R>(_ body: (inout Composer) throws -> R) rethrows -> R {
    try body(&data.composer)
  }

  /// The converter (C++ `converter()` dereferences the pointer; a context without one is a programming error).
  public var converter: any EngineConverterInterface {
    guard let converterImpl else { preconditionFailure("ImeContext has no converter") }
    return converterImpl
  }

  public var hasConverter: Bool { converterImpl != nil }

  public var keyEventTransformer: KeyEventTransformer { data.keyEventTransformer }

  public var state: State {
    get { data.state }
    set { data.state = newValue }
  }

  public func setRequest(_ request: Genmai_Commands_Request) {
    data.request = request
    converterImpl?.setRequest(data.request)
    data.composer.setRequest(data.request)
  }

  public func getRequest() -> Genmai_Commands_Request { data.request }

  public func setConfig(_ config: Genmai_Config_Config) {
    data.config = config

    converterImpl?.setConfig(data.config)

    data.composer.setConfig(data.config)
    data.keyEventTransformer.reloadConfig(data.config)
  }

  public func getConfig() -> Genmai_Config_Config { data.config }

  public func setKeyMapManager(_ keyMapManager: KeyMapManager) {
    data.keyMapManager = keyMapManager
  }

  public func getKeyMapManager() -> KeyMapManager { data.keyMapManager }

  public var clientCapability: Genmai_Commands_Capability {
    get { data.clientCapability }
    set { data.clientCapability = newValue }
  }

  public var applicationInfo: Genmai_Commands_ApplicationInfo {
    get { data.applicationInfo }
    set { data.applicationInfo = newValue }
  }

  /// Note that this may not be the latest info: this is likely to be a snapshot
  /// of during the precomposition state and may not be updated during
  /// composition/conversion state.
  public var clientContext: Genmai_Commands_Context {
    get { data.clientContext }
    set { data.clientContext = newValue }
  }

  public var output: Genmai_Commands_Output {
    get { data.output }
    set { data.output = newValue }
  }
}
