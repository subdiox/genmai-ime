// Port of mozc/src/rewriter/rewriter.{h,cc} (3.35.6354).
//
// Deviations from C++:
// - The C++ class `mozc::Rewriter` is named `RewriterImpl` here: the name
//   `Rewriter` is taken by the namespace enum of rewriter_interface.h
//   (`Rewriter.CapabilityType`, ...).
// - engine::Modules is not ported yet; the constructor takes the subset of it
//   that the rewriters need, abstracted by `RewriterModules` (engine::Modules
//   should conform to it).
// - The absl flag `--use_history_rewriter` (default true, as
//   MOZC_USER_HISTORY_REWRITER is defined) is the `useHistoryRewriter`
//   argument.
// - Build configuration: this is the macOS desktop build, so
//   MOZC_COMMAND_REWRITER, MOZC_DATE_REWRITER, MOZC_FORTUNE_REWRITER,
//   MOZC_USAGE_REWRITER, MOZC_USER_DICTIONARY_REWRITER and
//   MOZC_USER_HISTORY_REWRITER are all enabled.
// - CollocationRewriter::Create returns nullptr on broken data; C++ adds it
//   anyway (DCHECK). Here a nil rewriter is skipped.

import GenmaiBase

/// The subset of engine::Modules used by the rewriters.
public protocol RewriterModules: AnyObject {
  func getDataManager() -> DataManager
  func getDictionary() -> any DictionaryInterface
  func getPosMatcher() -> PosMatcher
  func getPosGroup() -> PosGroup
  func getSingleKanjiDictionary() -> SingleKanjiDictionary
  /// `GetSupplementalModel()` as used by CorrectionRewriter (reading
  /// alignment); nil behaves like the stub model.
  func getReadingAlignmentSupplementalModel() -> (any ReadingAlignmentSupplementalModel)?
}

public final class RewriterImpl: MergerRewriter {
  public init(_ modules: any RewriterModules, useHistoryRewriter: Bool = true) {
    super.init()
    let dataManager = modules.getDataManager()
    let dictionary = modules.getDictionary()
    let posMatcher = modules.getPosMatcher()
    let posGroup = modules.getPosGroup()
    let singleKanjiDictionary = modules.getSingleKanjiDictionary()

    // MOZC_USER_DICTIONARY_REWRITER
    addRewriter(UserDictionaryRewriter())

    addRewriter(FocusCandidateRewriter(dataManager.getCounterSuffixSortedArray(), posMatcher))
    addRewriter(LanguageAwareRewriter(posMatcher, dictionary))
    addRewriter(TransliterationRewriter(posMatcher))
    addRewriter(EnglishVariantsRewriter(posMatcher))
    addRewriter(NumberRewriter(dataManager.getCounterSuffixSortedArray(), posMatcher))
    if let collocation = CollocationRewriter.create(posMatcher, dataManager.getCollocationData()) {
      addRewriter(collocation)
    } else {
      assertionFailure("CollocationRewriter::Create failed")
    }
    addRewriter(SingleKanjiRewriter(posMatcher, singleKanjiDictionary))
    addRewriter(IvsVariantsRewriter())
    addRewriter(EmoticonRewriter(dataManager.getEmoticonRewriterData()))
    addRewriter(EmojiRewriter(dataManager.getEmojiRewriterData()))
    addRewriter(CalculatorRewriter())
    addRewriter(SymbolRewriter(dataManager.getSymbolRewriterData()))
    addRewriter(UnicodeRewriter())
    if useHistoryRewriter {
      addRewriter(UserSegmentHistoryRewriter(posMatcher, posGroup))
    }

    addRewriter(VariantsRewriter(posMatcher))
    addRewriter(ZipcodeRewriter(posMatcher))
    addRewriter(DiceRewriter())
    addRewriter(SmallLetterRewriter())

    if useHistoryRewriter {
      addRewriter(UserBoundaryHistoryRewriter())
    }

    // MOZC_DATE_REWRITER
    addRewriter(DateRewriter(dictionary))

    // MOZC_FORTUNE_REWRITER
    addRewriter(FortuneRewriter())

    // MOZC_COMMAND_REWRITER
    addRewriter(CommandRewriter())

    // MOZC_USAGE_REWRITER
    addRewriter(UsageRewriter(dataManager.getUsageRewriterData(), dictionary, posMatcher))

    addRewriter(VersionRewriter(dataManager.getDataVersion()))
    addRewriter(
      CorrectionRewriter(
        supplementalModel: modules.getReadingAlignmentSupplementalModel(),
        dataManager: dataManager))
    addRewriter(T13nPromotionRewriter())
    addRewriter(EnvironmentalFilterRewriter(dataManager.getEmojiRewriterData()))
    addRewriter(RemoveRedundantCandidateRewriter())
    addRewriter(A11yDescriptionRewriter(dataManager.getA11yDescriptionRewriterData()))
  }
}
