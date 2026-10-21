// Port of mozc/src/engine/modules.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - `Modules` conforms to the partial modules protocols of the lower layers
//   (ConverterModules, PredictionModules, UserHistoryPredictorModules,
//   RewriterModules), so it can be passed to Converter, ImmutableConverter,
//   Predictor and RewriterImpl directly.
// - C++ `GetSupplementalModel()` returns `SupplementalModelInterface&`; the
//   ConverterModules requirement of the same name returns the converter-side
//   protocol, so the full interface is `getSupplementalModelInterface()`
//   (the same object is returned by every supplemental model accessor).
// - `absl::StatusOr<std::unique_ptr<Modules>>` → `throws`. A second `build()`
//   on the same ModulesPresetBuilder throws `StatusError.unavailable`.
// - The C++ `RETURN_IF_NULL` checks guard allocations that cannot fail in
//   Swift; they are omitted. Errors from the system dictionary, connector and
//   suggestion filter are propagated as in C++.
// - The default supplemental model is a process-wide singleton
//   (`g_supplemental_model`), as in C++.

import GenmaiBase
import GenmaiStorage

// `g_supplemental_model` is static and initialized only once.
private let gSupplementalModel = SupplementalModelStub()

public final class Modules: ConverterModules, PredictionModules, UserHistoryPredictorModules,
  RewriterModules, @unchecked Sendable
{
  // @unchecked Sendable: every member is set once in `initialize` (before the
  // instance is handed out) and never reassigned; the members are themselves
  // thread-safe or immutable (mmapped data).

  /// Modules must be initialized via create() to keep Modules as immutable as
  /// possible.
  public static func create(_ dataManager: DataManager) throws -> Modules {
    try ModulesPresetBuilder().build(dataManager)
  }

  // MARK: - Accessors

  public func getDataManager() -> DataManager { dataManager! }
  public func getPosMatcher() -> PosMatcher { posMatcher! }
  public func getPosIdMap() -> PosIdMap { posIdMap! }
  public func getConnector() -> Connector { connector! }
  public func getSegmenter() -> Segmenter { segmenter! }
  public func getUserDictionary() -> any UserDictionaryInterface { userDictionary! }
  public func getSuffixDictionary() -> any DictionaryInterface { suffixDictionary! }
  public func getDictionary() -> any DictionaryInterface { dictionary! }
  public func getPosGroup() -> PosGroup { posGroup! }
  public func getSuggestionFilter() -> SuggestionFilter { suggestionFilter! }
  public func getSingleKanjiDictionary() -> SingleKanjiDictionary { singleKanjiDictionary! }
  public func getZeroQueryDict() -> ZeroQueryDict { zeroQueryDict }
  public func getZeroQueryNumberDict() -> ZeroQueryDict { zeroQueryNumberDict }
  public func getUserHistoryStorage() -> UserHistoryStorage { userHistoryStorage! }

  /// `GetSupplementalModel()`.
  public func getSupplementalModelInterface() -> any SupplementalModelInterface {
    supplementalModel!
  }

  // ConverterModules
  public func getSupplementalModel() -> any ConverterSupplementalModel { supplementalModel! }
  // UserHistoryPredictorModules
  public func getUserHistorySupplementalModel() -> any UserHistorySupplementalModel {
    supplementalModel!
  }
  // RewriterModules
  public func getReadingAlignmentSupplementalModel() -> (any ReadingAlignmentSupplementalModel)? {
    supplementalModel!
  }

  // MARK: - State

  fileprivate init() {}

  fileprivate var dataManager: DataManager?
  fileprivate var posMatcher: PosMatcher?
  fileprivate var posIdMap: PosIdMap?
  fileprivate var connector: Connector?
  fileprivate var segmenter: Segmenter?
  fileprivate var userDictionary: (any UserDictionaryInterface)?
  fileprivate var suffixDictionary: (any DictionaryInterface)?
  fileprivate var dictionary: (any DictionaryInterface)?
  fileprivate var posGroup: PosGroup?
  fileprivate var userHistoryStorage: UserHistoryStorage?
  fileprivate var suggestionFilter: SuggestionFilter?
  fileprivate var singleKanjiDictionary: SingleKanjiDictionary?
  fileprivate var zeroQueryDict = ZeroQueryDict()
  fileprivate var zeroQueryNumberDict = ZeroQueryDict()

  // `supplemental_model_` is initialized by a static singleton object.
  // However, it can also be set to a different value by a PresetBuilder.
  fileprivate var supplementalModel: (any SupplementalModelInterface)?

  fileprivate func initialize(_ dataManager: DataManager) throws {
    self.dataManager = dataManager

    if posMatcher == nil {
      posMatcher = PosMatcher(dataManager.getPosMatcherData())
    }
    let posMatcher = posMatcher!

    if posIdMap == nil {
      posIdMap = PosIdMap(dataManager.getPosIdMapData())
    }

    if userDictionary == nil {
      let userPosData = dataManager.getUserPosData()
      let userPos = UserPos(userPosData.tokenArray, userPosData.stringArray)
      userDictionary = UserDictionary(userPos, posMatcher)
    }

    if dictionary == nil {
      let sysdic = try SystemDictionary.Builder(image: dataManager.getSystemDictionaryData())
        .build()
      let valueDic = ValueDictionary(posMatcher, sysdic.valueTrie)
      dictionary = DictionaryImpl(sysdic, valueDic, userDictionary!, posMatcher)
    }

    if suffixDictionary == nil {
      let d = dataManager.getSuffixDictionaryData()
      suffixDictionary = SuffixDictionary(d.keyArray, d.valueArray, d.tokenArray)
    }

    if userHistoryStorage == nil {
      userHistoryStorage = UserHistoryStorage()
    }

    connector = try Connector.create(dataManager.getConnectorData())

    segmenter = Segmenter(dataManager: dataManager)

    posGroup = PosGroup(dataManager.getPosGroupData())

    suggestionFilter = try SuggestionFilter.create(dataManager.getSuggestionFilterData())

    if singleKanjiDictionary == nil {
      singleKanjiDictionary = SingleKanjiDictionary(dataManager.getSingleKanjiRewriterData())
    }

    // [zero_query_token_array_data,zero_query_string_array_data,
    //  zero_query_number_token_array_data, zero_query_number_string_array_data]
    let zeroQueryData = dataManager.getZeroQueryData()
    zeroQueryDict = ZeroQueryDict(zeroQueryData.tokenArray, zeroQueryData.stringArray)
    zeroQueryNumberDict = ZeroQueryDict(
      zeroQueryData.numberTokenArray, zeroQueryData.numberStringArray)

    if supplementalModel == nil {
      supplementalModel = gSupplementalModel
    }
  }
}

public final class ModulesPresetBuilder {
  private var modules: Modules?

  public init() {
    modules = Modules()
  }

  // Preset functions must be called before build().

  @discardableResult
  public func presetPosMatcher(_ posMatcher: PosMatcher) -> ModulesPresetBuilder {
    assert(modules != nil, "Module is already initialized")
    modules?.posMatcher = posMatcher
    return self
  }

  @discardableResult
  public func presetPosIdMap(_ posIdMap: PosIdMap) -> ModulesPresetBuilder {
    assert(modules != nil, "Module is already initialized")
    modules?.posIdMap = posIdMap
    return self
  }

  @discardableResult
  public func presetUserDictionary(_ userDictionary: any UserDictionaryInterface)
    -> ModulesPresetBuilder
  {
    assert(modules != nil, "Module is already initialized")
    modules?.userDictionary = userDictionary
    return self
  }

  @discardableResult
  public func presetSuffixDictionary(_ suffixDictionary: any DictionaryInterface)
    -> ModulesPresetBuilder
  {
    assert(modules != nil, "Module is already initialized")
    modules?.suffixDictionary = suffixDictionary
    return self
  }

  @discardableResult
  public func presetDictionary(_ dictionary: any DictionaryInterface) -> ModulesPresetBuilder {
    assert(modules != nil, "Module is already initialized")
    modules?.dictionary = dictionary
    return self
  }

  @discardableResult
  public func presetSingleKanjiDictionary(_ singleKanjiDictionary: SingleKanjiDictionary)
    -> ModulesPresetBuilder
  {
    assert(modules != nil, "Module is already initialized")
    modules?.singleKanjiDictionary = singleKanjiDictionary
    return self
  }

  @discardableResult
  public func presetSupplementalModel(_ supplementalModel: any SupplementalModelInterface)
    -> ModulesPresetBuilder
  {
    assert(modules != nil, "Module is already initialized")
    modules?.supplementalModel = supplementalModel
    return self
  }

  /// Preset of the user history storage (not in C++, where it is always
  /// created with the default file name). Lets tests keep the history in a
  /// temporary file.
  @discardableResult
  public func presetUserHistoryStorage(_ userHistoryStorage: UserHistoryStorage)
    -> ModulesPresetBuilder
  {
    assert(modules != nil, "Module is already initialized")
    modules?.userHistoryStorage = userHistoryStorage
    return self
  }

  public func build(_ dataManager: DataManager) throws -> Modules {
    guard let modules else {
      throw StatusError(.unavailable, "Build() must not be called twice")
    }
    try modules.initialize(dataManager)
    self.modules = nil
    return modules
  }
}
