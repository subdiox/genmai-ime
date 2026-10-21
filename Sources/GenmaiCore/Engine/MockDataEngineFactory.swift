// Port of mozc/src/engine/mock_data_engine_factory.{h,cc} (3.35.6354).

public enum MockDataEngineFactory {
  /// Creates an instance of Engine class with the mock data set.
  public static func create() throws -> Engine {
    try Engine.createEngine(MockDataManager())
  }
}
