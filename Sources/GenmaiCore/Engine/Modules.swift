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
  // @unchecked Sendable: every stored property is an immutable `let` set in
  // `init`; the members are themselves thread-safe or immutable (mmapped
  // data). Not checked because the supplemental model and the single kanji
  // dictionary are non-Sendable protocol existentials / open classes of the
  // prediction layer.

  /// Modules must be initialized via create() to keep Modules as immutable as
  /// possible.
  public static func create(_ dataManager: DataManager) throws -> Modules {
    try ModulesPresetBuilder().build(dataManager)
  }

  // MARK: - Accessors

  public func getDataManager() -> DataManager { dataManager }
  public func getPosMatcher() -> PosMatcher { posMatcher }
  public func getPosIdMap() -> PosIdMap { posIdMap }
  public func getConnector() -> Connector { connector }
  public func getSegmenter() -> Segmenter { segmenter }
  public func getUserDictionary() -> any UserDictionaryInterface { userDictionary }
  public func getSuffixDictionary() -> any DictionaryInterface { suffixDictionary }
  public func getDictionary() -> any DictionaryInterface { dictionary }
  public func getPosGroup() -> PosGroup { posGroup }
  public func getSuggestionFilter() -> SuggestionFilter { suggestionFilter }
  public func getSingleKanjiDictionary() -> SingleKanjiDictionary { singleKanjiDictionary }
  public func getZeroQueryDict() -> ZeroQueryDict { zeroQueryDict }
  public func getZeroQueryNumberDict() -> ZeroQueryDict { zeroQueryNumberDict }
  public func getUserHistoryStorage() -> UserHistoryStorage { userHistoryStorage }

  /// `GetSupplementalModel()`.
  public func getSupplementalModelInterface() -> any SupplementalModelInterface {
    supplementalModel
  }

  // ConverterModules
  public func getSupplementalModel() -> any ConverterSupplementalModel { supplementalModel }
  // UserHistoryPredictorModules
  public func getUserHistorySupplementalModel() -> any UserHistorySupplementalModel {
    supplementalModel
  }
  // RewriterModules
  public func getReadingAlignmentSupplementalModel() -> (any ReadingAlignmentSupplementalModel)? {
    supplementalModel
  }

  // MARK: - State

  private let dataManager: DataManager
  private let posMatcher: PosMatcher
  private let posIdMap: PosIdMap
  private let connector: Connector
  private let segmenter: Segmenter
  private let userDictionary: any UserDictionaryInterface
  private let suffixDictionary: any DictionaryInterface
  private let dictionary: any DictionaryInterface
  private let posGroup: PosGroup
  private let userHistoryStorage: UserHistoryStorage
  private let suggestionFilter: SuggestionFilter
  private let singleKanjiDictionary: SingleKanjiDictionary
  private let zeroQueryDict: ZeroQueryDict
  private let zeroQueryNumberDict: ZeroQueryDict

  // `supplemental_model_` is initialized by a static singleton object.
  // However, it can also be set to a different value by a PresetBuilder.
  private let supplementalModel: any SupplementalModelInterface

  /// The members a `ModulesPresetBuilder` presets (nil: built from the data
  /// manager).
  fileprivate struct Presets {
    var posMatcher: PosMatcher?
    var posIdMap: PosIdMap?
    var userDictionary: (any UserDictionaryInterface)?
    var suffixDictionary: (any DictionaryInterface)?
    var dictionary: (any DictionaryInterface)?
    var singleKanjiDictionary: SingleKanjiDictionary?
    var supplementalModel: (any SupplementalModelInterface)?
    var userHistoryStorage: UserHistoryStorage?
  }

  /// `Modules::Init`.
  fileprivate init(_ dataManager: DataManager, _ presets: Presets) throws {
    self.dataManager = dataManager

    let posMatcher = presets.posMatcher ?? PosMatcher(dataManager.getPosMatcherData())
    self.posMatcher = posMatcher

    posIdMap = presets.posIdMap ?? PosIdMap(dataManager.getPosIdMapData())

    let userDictionary: any UserDictionaryInterface
    if let preset = presets.userDictionary {
      userDictionary = preset
    } else {
      let userPosData = dataManager.getUserPosData()
      let userPos = UserPos(userPosData.tokenArray, userPosData.stringArray)
      userDictionary = UserDictionary(userPos, posMatcher)
    }
    self.userDictionary = userDictionary

    if let preset = presets.dictionary {
      dictionary = preset
    } else {
      let sysdic = try SystemDictionary.Builder(image: dataManager.getSystemDictionaryData())
        .build()
      let valueDic = ValueDictionary(posMatcher, sysdic.valueTrie)
      dictionary = DictionaryImpl(sysdic, valueDic, userDictionary, posMatcher)
    }

    if let preset = presets.suffixDictionary {
      suffixDictionary = preset
    } else {
      let d = dataManager.getSuffixDictionaryData()
      suffixDictionary = SuffixDictionary(d.keyArray, d.valueArray, d.tokenArray)
    }

    userHistoryStorage = presets.userHistoryStorage ?? UserHistoryStorage()

    connector = try Connector.create(dataManager.getConnectorData())

    segmenter = Segmenter(dataManager: dataManager)

    posGroup = PosGroup(dataManager.getPosGroupData())

    suggestionFilter = try SuggestionFilter.create(dataManager.getSuggestionFilterData())

    singleKanjiDictionary =
      presets.singleKanjiDictionary ?? SingleKanjiDictionary(dataManager.getSingleKanjiRewriterData())

    // [zero_query_token_array_data,zero_query_string_array_data,
    //  zero_query_number_token_array_data, zero_query_number_string_array_data]
    let zeroQueryData = dataManager.getZeroQueryData()
    zeroQueryDict = ZeroQueryDict(zeroQueryData.tokenArray, zeroQueryData.stringArray)
    zeroQueryNumberDict = ZeroQueryDict(
      zeroQueryData.numberTokenArray, zeroQueryData.numberStringArray)

    supplementalModel = presets.supplementalModel ?? gSupplementalModel
  }
}

public final class ModulesPresetBuilder {
  /// The presets; nil after build().
  private var presets: Modules.Presets?

  public init() {
    presets = Modules.Presets()
  }

  // Preset functions must be called before build().

  @discardableResult
  public func presetPosMatcher(_ posMatcher: PosMatcher) -> ModulesPresetBuilder {
    assert(presets != nil, "Module is already initialized")
    presets?.posMatcher = posMatcher
    return self
  }

  @discardableResult
  public func presetPosIdMap(_ posIdMap: PosIdMap) -> ModulesPresetBuilder {
    assert(presets != nil, "Module is already initialized")
    presets?.posIdMap = posIdMap
    return self
  }

  @discardableResult
  public func presetUserDictionary(_ userDictionary: any UserDictionaryInterface)
    -> ModulesPresetBuilder
  {
    assert(presets != nil, "Module is already initialized")
    presets?.userDictionary = userDictionary
    return self
  }

  @discardableResult
  public func presetSuffixDictionary(_ suffixDictionary: any DictionaryInterface)
    -> ModulesPresetBuilder
  {
    assert(presets != nil, "Module is already initialized")
    presets?.suffixDictionary = suffixDictionary
    return self
  }

  @discardableResult
  public func presetDictionary(_ dictionary: any DictionaryInterface) -> ModulesPresetBuilder {
    assert(presets != nil, "Module is already initialized")
    presets?.dictionary = dictionary
    return self
  }

  @discardableResult
  public func presetSingleKanjiDictionary(_ singleKanjiDictionary: SingleKanjiDictionary)
    -> ModulesPresetBuilder
  {
    assert(presets != nil, "Module is already initialized")
    presets?.singleKanjiDictionary = singleKanjiDictionary
    return self
  }

  @discardableResult
  public func presetSupplementalModel(_ supplementalModel: any SupplementalModelInterface)
    -> ModulesPresetBuilder
  {
    assert(presets != nil, "Module is already initialized")
    presets?.supplementalModel = supplementalModel
    return self
  }

  /// Preset of the user history storage (not in C++, where it is always
  /// created with the default file name). Lets tests keep the history in a
  /// temporary file.
  @discardableResult
  public func presetUserHistoryStorage(_ userHistoryStorage: UserHistoryStorage)
    -> ModulesPresetBuilder
  {
    assert(presets != nil, "Module is already initialized")
    presets?.userHistoryStorage = userHistoryStorage
    return self
  }

  public func build(_ dataManager: DataManager) throws -> Modules {
    guard let presets else {
      throw StatusError(.unavailable, "Build() must not be called twice")
    }
    let modules = try Modules(dataManager, presets)
    self.presets = nil
    return modules
  }
}
