// Port of mozc/src/converter/immutable_converter_interface.h (3.35.6354).

/// Perform one-shot conversion with constraints.
/// Constraints are encoded in |segments|
public protocol ImmutableConverterInterface: AnyObject, Sendable {
  func convert(_ options: ConversionOptions, _ segments: Segments) -> Bool
}
