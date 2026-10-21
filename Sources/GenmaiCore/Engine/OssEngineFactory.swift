// Port of mozc/src/engine/oss_engine_factory.h (3.35.6354).
//
// OssDataManager reads `Data/genmai.data` (see OssDataManager.defaultDataPath)
// instead of an embedded data set; `create()` throws when it is missing.

public enum OssEngineFactory {
  public static func create() throws -> Engine {
    try Engine.createEngine(OssDataManager())
  }
}
