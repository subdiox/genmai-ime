// Port of mozc/src/gui/dictionary_tool/dictionary_tool.{h,cc} (3.35.6354): the state and the operations of
// the dictionary tool, independent of the SwiftUI views.
//
// The QTableWidget becomes `rows` (the editable copy of the current dictionary, synced back to the storage by
// `syncToStorage()` exactly where the Qt code calls SyncToStorage()). QMessageBox / QInputDialog become
// `pendingMessage` / `prompt`, which the views present.

import Foundation
import GenmaiBase
import GenmaiClient
import GenmaiCore
import GenmaiProtocol
import Observation

private let kContext = "genmai::gui::DictionaryTool"

private func trDT(_ source: String) -> String { tr(kContext, source) }

public typealias IMEType = UserDictionaryImporter.IMEType
public typealias EncodingType = UserDictionaryImporter.EncodingType
typealias ExtendedErrorCode = UserDictionaryUtil.ExtendedErrorCode
typealias UserDictionaryEntry = Genmai_UserDictionary_UserDictionary.Entry

extension UserDictionaryStorage {
  static var maxDictionarySize: Int { maxDictionarySize() }
  static var maxEntrySize: Int { maxEntrySize() }
}

@MainActor
@Observable
public final class DictionaryToolModel {
  /// One row of the entry table (reading, word, category, comment).
  public struct Row: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var reading: String
    public var word: String
    public var category: String
    public var comment: String

    public init(id: UUID = UUID(), reading: String, word: String, category: String, comment: String) {
      self.id = id
      self.reading = reading
      self.word = word
      self.category = category
      self.comment = comment
    }
  }

  public struct DictionaryItem: Identifiable, Hashable, Sendable {
    public let id: UInt64
    public var name: String
  }

  /// Columns of the entry table.
  public enum Column: Int, Sendable, CaseIterable {
    case reading = 0
    case word
    case category
    case comment
  }

  /// QInputDialog requests.
  public enum Prompt: Identifiable, Equatable, Sendable {
    case newDictionary
    case renameDictionary(currentName: String)
    case editComment

    public var id: String {
      switch self {
      case .newDictionary: "new"
      case .renameDictionary: "rename"
      case .editComment: "comment"
      }
    }

    public var label: String {
      switch self {
      case .newDictionary: trDT("Name of the new dictionary")
      case .renameDictionary: trDT("New name of the dictionary")
      case .editComment: trDT("New comment")
      }
    }

    public var initialText: String {
      if case .renameDictionary(let name) = self { return name }
      return ""
    }

    /// PromptForDictionaryName repeats until the name is non-empty; the comment may be empty.
    public var allowsEmpty: Bool { self == .editComment }
  }

  /// The import dialog mode (ImportDialog::ExecInCreateMode / ExecInAppendMode).
  public enum ImportMode: Sendable, Equatable {
    case create
    case append
  }

  public enum Availability: Equatable, Sendable {
    case available
    /// The storage is locked by another process; the window shows the message and closes.
    case unavailable(String)
  }

  // MARK: - State

  public private(set) var availability: Availability = .available
  public private(set) var dictionaries: [DictionaryItem] = []
  /// The selection in the dictionary list.
  public private(set) var selectedDictionaryID: UInt64?
  public var rows: [Row] = [] {
    didSet { modified = true }
  }
  public var selectedRowIDs: Set<Row.ID> = []
  /// The row being edited after AddWord (the view focuses its reading field).
  public private(set) var editingRowID: Row.ID?
  public var pendingMessage: GUIMessage?
  public var prompt: Prompt?
  public var importMode: ImportMode?
  public var isFindDialogShown = false
  public private(set) var statusMessage = ""

  public let windowTitle = kProductNameInEnglish
  public let posList: [String]
  public let defaultPos: String

  // MARK: - Internals

  private let client: any GenmaiClientProtocol
  let storage: UserDictionaryStorage
  /// current_dic_id_: the dictionary whose contents are in `rows` (0: none).
  private var currentDictionaryID: UInt64 = 0
  private(set) var modified = false
  private let maxEntrySize = UserDictionaryStorage.maxEntrySize

  public init(
    client: any GenmaiClientProtocol,
    storage: UserDictionaryStorage = UserDictionaryStorage(),
    posListProvider: PosListProvider = PosListProvider()
  ) {
    self.client = client
    self.storage = storage
    posList = posListProvider.getPosList()
    defaultPos = posList.indices.contains(posListProvider.getPosListDefaultIndex())
      ? posList[posListProvider.getPosListDefaultIndex()] : "名詞"

    do {
      try storage.load()
    } catch {
      GenmaiLog.warning("UserDictionaryStorage::Load() failed")
    }
    if !storage.lock() {
      availability = .unavailable(trDT("Another process is accessing the user dictionary file."))
      return
    }

    // Initialize the list widget for a list of dictionaries.
    initDictionaryList()
    if let first = dictionaries.first {
      selectDictionary(first.id)
    } else {
      // Make sure that the table widget is initialized when there is no dictionary.
      onDictionarySelectionChanged()
    }

    // If this is the first time for the user dictionary is used, create a default dictionary.
    do {
      try storage.exists()
    } catch {
      createDictionaryHelper(trDT("User Dictionary 1"))
    }
    updateUIStatus()
  }

  // MARK: - UI state (UpdateUIStatus)

  public var hasCurrentDictionary: Bool { selectedDictionaryID != nil }
  public var canCreateDictionary: Bool { dictionaries.count < UserDictionaryStorage.maxDictionarySize }
  public var canAddWord: Bool { !dictionaries.isEmpty && hasCurrentDictionary && rows.count < maxEntrySize }
  public var canDeleteWord: Bool { !rows.isEmpty }
  public var canMoveWords: Bool { dictionaries.count > 1 }

  /// Dictionaries other than the current one ("Move to" targets).
  public var moveTargets: [DictionaryItem] { dictionaries.filter { $0.id != selectedDictionaryID } }

  private func updateUIStatus() {
    if let item = currentItem {
      statusMessage = DictionaryToolText.arg(trDT("%1: %2 entries"), item.name, rows.count)
    } else {
      statusMessage = ""
    }
  }

  private var currentItem: DictionaryItem? {
    dictionaries.first { $0.id == selectedDictionaryID }
  }

  // MARK: - Dictionary list

  /// Changes the selection of the dictionary list (itemSelectionChanged).
  public func selectDictionary(_ id: UInt64?) {
    selectedDictionaryID = id
    onDictionarySelectionChanged()
  }

  private func onDictionarySelectionChanged() {
    syncToStorage()
    guard let item = currentItem else {
      currentDictionaryID = 0
      setRowsWithoutModification([])
      updateUIStatus()
      return
    }
    currentDictionaryID = item.id
    setupDicContentEditor(item)
  }

  private func setupDicContentEditor(_ item: DictionaryItem) {
    guard let dic = storage.getUserDictionary(item.id) else {
      reportError(nil)
      return
    }
    setRowsWithoutModification(
      dic.entries.map {
        Row(reading: $0.key, word: $0.value, category: UserPos.getStringPosType($0.pos), comment: $0.comment)
      })
    updateUIStatus()
  }

  private func setRowsWithoutModification(_ newRows: [Row]) {
    rows = newRows
    selectedRowIDs = []
    editingRowID = nil
    modified = false
  }

  private func initDictionaryList() {
    dictionaries = storage.proto.dictionaries.map { DictionaryItem(id: $0.id, name: $0.name) }
    updateUIStatus()
  }

  /// "New dictionary..." — checks the limit, then asks for the name.
  public func requestCreateDictionary() {
    let maxSize = UserDictionaryStorage.maxDictionarySize
    if dictionaries.count >= maxSize {
      showMessage(.critical, DictionaryToolText.arg(trDT("You can't have more than %1 dictionaries."), maxSize))
      return
    }
    prompt = .newDictionary
  }

  public func createDictionary(named dicName: String) {
    if dicName.isEmpty {
      return  // canceled by user
    }
    syncToStorage()
    createDictionaryHelper(dicName)
  }

  private func createDictionaryHelper(_ dicName: String) {
    let newDicID: UInt64
    do {
      newDicID = try storage.createDictionary(dicName)
    } catch {
      reportError(error)
      return
    }
    dictionaries.append(DictionaryItem(id: newDicID, name: dicName))
    selectDictionary(newDicID)
    addWord()
  }

  public func requestDeleteDictionary() {
    guard let item = currentItem else {
      showMessage(.information, trDT("No dictionary is selected."))
      return
    }
    showMessage(.question, DictionaryToolText.arg(trDT("Do you want to delete %1?"), item.name)) { [weak self] in
      self?.deleteDictionary(item.id)
    }
  }

  func deleteDictionary(_ id: UInt64) {
    do {
      try storage.deleteDictionary(id)
    } catch {
      reportError(error)
      return
    }
    modified = false
    dictionaries.removeAll { $0.id == id }
    if selectedDictionaryID == id {
      selectedDictionaryID = nil
      currentDictionaryID = 0
      setRowsWithoutModification([])
    }
    updateUIStatus()
  }

  public func requestRenameDictionary() {
    guard let item = currentItem else {
      showMessage(.information, trDT("No dictionary is selected."))
      return
    }
    prompt = .renameDictionary(currentName: item.name)
  }

  public func renameDictionary(to dicName: String) {
    guard let item = currentItem, !dicName.isEmpty else {
      return
    }
    do {
      try storage.renameDictionary(item.id, dicName)
    } catch {
      reportError(error)
      return
    }
    if let index = dictionaries.firstIndex(where: { $0.id == item.id }) {
      dictionaries[index].name = dicName
    }
    updateUIStatus()
  }

  /// Answers a prompt (nil: canceled).
  public func completePrompt(_ prompt: Prompt, text: String?) {
    self.prompt = nil
    guard let text else { return }
    switch prompt {
    case .newDictionary: createDictionary(named: text)
    case .renameDictionary: renameDictionary(to: text)
    case .editComment: editComment(text)
    }
  }

  // MARK: - Import / export

  public func requestImportAndCreateDictionary() {
    let maxSize = UserDictionaryStorage.maxDictionarySize
    if dictionaries.count >= maxSize {
      showMessage(.critical, DictionaryToolText.arg(trDT("You can't have more than %1 dictionaries."), maxSize))
      return
    }
    importMode = .create
  }

  public func requestImportAndAppendDictionary() {
    guard currentItem != nil else {
      showMessage(.information, trDT("No dictionary is selected."))
      return
    }
    if rows.count >= maxEntrySize {
      showMessage(
        .critical,
        DictionaryToolText.arg(trDT("You can't have more than %1 words in one dictionary."), maxEntrySize))
      return
    }
    importMode = .append
  }

  /// Accepted import dialog.
  public func completeImport(
    mode: ImportMode, fileName: String, dicName: String, imeType: IMEType, encodingType: EncodingType
  ) {
    importMode = nil
    switch mode {
    case .create:
      importHelper(0, dicName, fileName, imeType, encodingType)
    case .append:
      guard let item = currentItem else { return }
      importHelper(item.id, item.name, fileName, imeType, encodingType)
    }
  }

  private func reportImportError(_ error: ExtendedErrorCode?, _ dicName: String, _ addedEntriesSize: Int) {
    switch error ?? .ok {
    case .ok:
      showMessage(
        .information, DictionaryToolText.arg(trDT("%1 entries are imported to %2."), addedEntriesSize, dicName))
    case .importNotSupported:
      showMessage(
        .information,
        DictionaryToolText.arg(
          trDT(
            "You have imported a file in an invalid or unsupported file format.\n\nPlease check the file format. ATOK11 or older format is not supported by %1."
          ), kProductNameInEnglish))
    case .importTooManyWords:
      showMessage(
        .information,
        DictionaryToolText.arg(
          trDT(
            "%1 doesn't have enough space to import all words in the file. First %2 entries are imported."),
          dicName, addedEntriesSize))
    case .importInvalidEntries:
      showMessage(
        .information,
        DictionaryToolText.arg(
          trDT(
            "%1 entries are imported to %2.\n\nSome imported words were not recognized by %3. Please check the original import file."
          ), addedEntriesSize, dicName, windowTitle))
    case .importFatal:
      showMessage(.critical, trDT("Failed to open user dictionary"))
    default:
      break
    }
  }

  private func importHelper(
    _ dicID: UInt64, _ dicName: String, _ fileName: String, _ imeType: IMEType, _ encodingType: EncodingType
  ) {
    if !isReadableToImport(fileName) {
      showMessage(.critical, DictionaryToolText.arg(trDT("Can't open %1."), fileName))
      return
    }
    var dicID = dicID
    if dicID == 0 {
      do {
        dicID = try storage.createDictionary(dicName)
      } catch {
        reportError(error)
        return
      }
    }
    guard let dic = storage.getUserDictionary(dicID) else {
      reportError(nil)
      return
    }
    if dic.name != dicName {
      reportError(nil)
      return
    }

    // Everything looks Okey so far. Now starting import operation.
    syncToStorage()

    // Open dictionary
    guard let iter = UserDictionaryImporter.createTextLineIterator(encodingType, fileName) else {
      return
    }
    let oldSize = dic.entries.count
    var importError: ExtendedErrorCode?
    var addedEntriesSize = 0
    storage.withUserDictionary(dicID) { dic in
      do {
        try UserDictionaryImporter.importFromTextLineIterator(imeType, iter, &dic)
      } catch {
        importError = error as? ExtendedErrorCode ?? .importUnknownError
      }
      addedEntriesSize = dic.entries.count - oldSize
    }

    // Update window state.
    initDictionaryList()
    selectedDictionaryID = dicID
    currentDictionaryID = 0  // Already synced; reload the rows from the storage.
    onDictionarySelectionChanged()
    updateUIStatus()

    reportImportError(importError, dicName, addedEntriesSize)
  }

  /// Exports the current dictionary to `fileName` (the view asks for the path with a save panel).
  public func exportDictionary(to fileName: String) {
    guard let item = currentItem else {
      showMessage(.information, trDT("No dictionary is selected."))
      return
    }
    if fileName.isEmpty {
      return
    }
    if !isWritableToExport(fileName) {
      showMessage(.critical, DictionaryToolText.arg(trDT("Can't open %1."), fileName))
      return
    }
    syncToStorage()
    do {
      try storage.exportDictionary(item.id, fileName)
    } catch {
      reportError(error)
      return
    }
    showMessage(.information, trDT("Dictionary export finished."))
  }

  /// Checks done before showing the export save panel.
  public func canStartExport() -> Bool {
    if currentItem == nil {
      showMessage(.information, trDT("No dictionary is selected."))
      return false
    }
    return true
  }

  // MARK: - Words

  public func addWord() {
    let row = rows.count
    if row >= maxEntrySize {
      showMessage(
        .information,
        DictionaryToolText.arg(trDT("You can't have more than %1 words in one dictionary."), maxEntrySize))
      return
    }
    let newRow = Row(reading: "", word: "", category: defaultPos, comment: "")
    rows.append(newRow)
    selectedRowIDs = [newRow.id]
    editingRowID = newRow.id
    updateUIStatus()
  }

  /// The selected row indices, unique and sorted in descending order (GetSortedSelectedRows).
  func sortedSelectedRows() -> [Int] {
    rows.indices.filter { selectedRowIDs.contains(rows[$0].id) }.sorted(by: >)
  }

  public func requestDeleteWords() {
    let selected = sortedSelectedRows()
    if selected.isEmpty {
      return
    }
    let message =
      selected.count == 1
      ? trDT("Do you want to delete this word?") : trDT("Do you want to delete the selected words?")
    showMessage(.question, message) { [weak self] in
      self?.deleteSelectedWords()
    }
  }

  func deleteSelectedWords() {
    let selected = sortedSelectedRows()
    for index in selected {
      rows.remove(at: index)
    }
    selectedRowIDs = []
    updateUIStatus()
    modified = true
  }

  /// "Change category to" (EditPos).
  public func editPos(_ pos: String) {
    if selectedRowIDs.isEmpty {
      return
    }
    for index in rows.indices where selectedRowIDs.contains(rows[index].id) {
      rows[index].category = pos
    }
  }

  public func requestEditComment() {
    if selectedRowIDs.isEmpty {
      return
    }
    prompt = .editComment
  }

  func editComment(_ newComment: String) {
    for index in rows.indices where selectedRowIDs.contains(rows[index].id) {
      rows[index].comment = newComment
    }
  }

  /// Moves the selected words to the dictionary `targetID` (MoveTo).
  public func moveSelectedWords(to targetID: UInt64) {
    guard selectedDictionaryID != nil, targetID != selectedDictionaryID,
      let targetDict = storage.getUserDictionary(targetID)
    else {
      return
    }
    let selected = sortedSelectedRows()
    if selected.isEmpty {
      return
    }
    let targetMaxEntrySize = UserDictionaryStorage.maxEntrySize
    if targetDict.entries.count + selected.count > targetMaxEntrySize {
      showMessage(
        .critical,
        DictionaryToolText.arg(
          trDT("Cannot move all the selected items.\nThe target dictionary can have maximum %1 entries."),
          targetMaxEntrySize))
      return
    }
    storage.withUserDictionary(targetID) { dic in
      for index in selected {
        dic.entries.append(Self.makeEntry(rows[index]))
      }
    }
    for index in selected {
      rows.remove(at: index)
    }
    selectedRowIDs = []
    updateUIStatus()
    modified = true
  }

  /// Called when a cell was edited by the user (OnItemChanged).
  public func onItemChanged(_ rowID: Row.ID, _ column: Column) {
    if column == .reading, let row = rows.first(where: { $0.id == rowID }), !row.reading.isEmpty,
      !UserDictionaryUtil.isValidReading(row.reading)
    {
      showMessage(.critical, trDT("An invalid character is included in the reading."))
    }
    if editingRowID == rowID {
      editingRowID = nil
    }
    updateUIStatus()
    modified = true
  }

  /// Sorts the table (OnHeaderClicked); the view keeps the ascending/descending toggle state.
  public func sort(by column: Column, ascending: Bool) {
    func key(_ row: Row) -> String {
      switch column {
      case .reading: row.reading
      case .word: row.word
      case .category: row.category
      case .comment: row.comment
      }
    }
    // QTableWidget::sortItems is a stable sort by the cell text.
    let sorted = rows.enumerated().sorted { lhs, rhs in
      let l = key(lhs.element)
      let r = key(rhs.element)
      if l == r { return lhs.offset < rhs.offset }
      return ascending ? l < r : l > r
    }
    rows = sorted.map(\.element)
    modified = true
  }

  // MARK: - Find (FindDialog)

  public enum FindDirection: Sendable {
    case forward
    case backward
  }

  /// The cell matched by the last find (FindDialog::last_item_), as (row id, column 0 or 1).
  public private(set) var lastFoundCell: (rowID: Row.ID, column: Int)?

  /// Resets the find state (FindDialog::showEvent / closeEvent).
  public func resetFind() {
    lastFoundCell = nil
  }

  /// FindDialog::Find. Starts at the current (first selected) row; columns 0 (reading) and 1 (word) are
  /// searched case-insensitively. Returns false (and shows "Cannot find pattern") if nothing matched.
  @discardableResult
  public func find(_ query: String, direction: FindDirection) -> Bool {
    let currentRow = rows.firstIndex { selectedRowIDs.contains($0.id) } ?? 0
    let startRow = max(0, currentRow)
    var startColumn = min(max(lastFoundCell?.column ?? 0, 0), 1)
    if let last = lastFoundCell, rows.firstIndex(where: { $0.id == last.rowID }) != startRow {
      startColumn = 0
    }

    func text(_ row: Int, _ column: Int) -> String { column == 0 ? rows[row].reading : rows[row].word }
    func match(_ row: Int, _ column: Int) -> Bool {
      if let last = lastFoundCell, last.rowID == rows[row].id, last.column == column {
        return false
      }
      return text(row, column).range(of: query, options: .caseInsensitive) != nil
    }

    var found: (Int, Int)?
    switch direction {
    case .forward:
      outer: for row in startRow..<max(startRow, rows.count) {
        var column = startColumn
        while column < 2 {
          startColumn = 0
          if match(row, column) {
            found = (row, column)
            break outer
          }
          column += 1
        }
      }
    case .backward:
      if startRow < rows.count {
        outer: for row in stride(from: startRow, through: 0, by: -1) {
          var column = startColumn
          while column >= 0 {
            startColumn = 1
            if match(row, column) {
              found = (row, column)
              break outer
            }
            column -= 1
          }
        }
      }
    }

    if let (row, column) = found {
      lastFoundCell = (rows[row].id, column)
      selectedRowIDs = [rows[row].id]
      return true
    }
    lastFoundCell = nil
    pendingMessage = GUIMessage(
      kind: .information, title: tr("FindDialog", "[ProductName] Dictionary Find Dialog"),
      text: DictionaryToolText.arg(tr("genmai::gui::FindDialog", "Cannot find pattern %1"), query))
    return false
  }

  // MARK: - Saving

  static func makeEntry(_ row: Row) -> UserDictionaryEntry {
    var entry = UserDictionaryEntry()
    entry.key = row.reading
    entry.value = row.word
    // C++: set_pos(ToPosType(text)) + SanitizeEntry, which falls back to NOUN for an invalid POS.
    entry.pos = UserPos.toPosType(row.category) ?? .noun
    entry.comment = row.comment
    UserDictionaryUtil.sanitizeEntry(&entry)
    return entry
  }

  /// Save content of the current dictionary to the UserDictionaryStorage (SyncToStorage).
  func syncToStorage() {
    if currentDictionaryID == 0 || !modified {
      return
    }
    let entries = rows.map(Self.makeEntry)
    if storage.withUserDictionary(currentDictionaryID, { $0.entries = entries }) == nil {
      return
    }
    modified = false
  }

  /// Save storage contents into the disk and send Reload command to the server.
  @discardableResult
  func saveAndReloadServer() -> (any Error)? {
    var status: (any Error)?
    do {
      try storage.save()
    } catch {
      status = error
      if (error as? StatusError)?.code != .resourceExhausted {
        return error
      }
    }
    // If server is not running, we don't need to execute Reload command.
    if !client.pingServer() {
      return status
    }
    // Update server version if need be.
    if !client.checkVersionOrRestartServer() {
      return status
    }
    // We don't show any dialog even when an error happens, since
    // dictionary serialization is finished correctly.
    _ = client.reload()
    return status
  }

  /// The window is closing (closeEvent).
  public func close() {
    guard availability == .available else { return }
    syncToStorage()
    let status = saveAndReloadServer()
    if (status as? StatusError)?.code == .resourceExhausted {
      showMessage(
        .warning,
        trDT(
          "Making dangerously large user dictionary file. If the dictionary file turns out to be larger than 256Mbyte, the dictionary loader skips to handle all the words to prevent the converter from being halted."
        ))
    }
    storage.unlock()
  }

  /// The application was deactivated (OnDeactivate): save so that the IME can reload.
  public func onDeactivate() {
    guard availability == .available else { return }
    syncToStorage()
    saveAndReloadServer()
  }

  // MARK: - Messages

  private func reportError(_ error: (any Error)?) {
    switch error as? ExtendedErrorCode {
    case .dictionaryNameContainsInvalidCharacter:
      showMessage(.critical, trDT("An invalid character is included in the dictionary name."))
    case .dictionaryNameEmpty:
      showMessage(.critical, trDT("Dictionary name is empty."))
    case .dictionaryNameTooLong:
      showMessage(.critical, trDT("Dictionary name is too long."))
    case .dictionaryNameDuplicated:
      showMessage(.critical, trDT("Dictionary already exists."))
    default:
      showMessage(.critical, trDT("A fatal error occurred."))
    }
  }

  private func showMessage(
    _ kind: GUIMessage.Kind, _ text: String, onYes: (@MainActor @Sendable () -> Void)? = nil
  ) {
    pendingMessage = GUIMessage(kind: kind, title: windowTitle, text: text, onYes: onYes)
  }

  // MARK: - Cell bindings

  /// Updates one cell; used by the table's editable cells.
  public func setCell(_ rowID: Row.ID, _ column: Column, _ value: String) {
    guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
    switch column {
    case .reading: rows[index].reading = value
    case .word: rows[index].word = value
    case .category: rows[index].category = value
    case .comment: rows[index].comment = value
    }
  }
}
