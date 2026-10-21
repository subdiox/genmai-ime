// Port of mozc/src/engine/eval_engine_factory.{h,cc} (3.35.6354).

/// Creates an engine from the data set file at `dataFilePath` whose magic
/// number is that of `dataType` (DataManager::GetDataSetMagicNumber).
public func createEvalEngine(_ dataFilePath: String, _ dataType: String) throws -> Engine {
  let magicNumber = DataManager.getDataSetMagicNumber(dataType)
  let dataManager = try DataManager.createFromFile(dataFilePath, magic: magicNumber)
  return try Engine.createEngine(dataManager)
}
