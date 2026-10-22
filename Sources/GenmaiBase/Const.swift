// Port of mozc/src/base/const.h (3.35.6354).
//
// Only the constants of the `__APPLE__` branch (and the common ones) are
// ported; the Windows / Linux constants (registry keys, window class names,
// pipe names, .exe / .dll names) have no meaning on macOS. The OSS (non
// GOOGLE_JAPANESE_INPUT_BUILD) branding is used.
//
// The constants are namespaced in `GenmaiConst` (C++ names kept) so that they do
// not clash with the module-level copies some app-layer modules declare
// (GenmaiGUI.kProductNameInEnglish, GenmaiClient.kWordRegisterEnvironmentName).
public enum GenmaiConst {
  /// kProductPrefix
  public static let kProductPrefix = "Genmai"
  /// kProductNameInEnglish
  public static let kProductNameInEnglish = "Genmai"
  /// kVersionRewriterVersionPrefix = kProductPrefix "-"
  public static let kVersionRewriterVersionPrefix = kProductPrefix + "-"

  // macOS bundle names.
  /// kGenmaiServerName = kProductPrefix "Converter.app"
  public static let kGenmaiServerName = kProductPrefix + "Converter.app"
  /// kGenmaiRenderer = kProductPrefix "Renderer.app"
  public static let kGenmaiRenderer = kProductPrefix + "Renderer.app"
  /// The tool app (the dialogs) in Genmai.app/Contents/Resources. The C++ kMozcTool is kProductPrefix "Tool.app";
  /// the port names it after the product, so that the Dock, the app switcher and Activity Monitor show "Genmai".
  public static let kGenmaiTool = kProductPrefix + ".app"
  /// kEventPathPrefix
  public static let kEventPathPrefix = "Genmai.event."

  /// Environment variable names of the default entries of the word register
  /// dialog.
  public static let kWordRegisterEnvironmentName = "default_entry_of_word_register"
  public static let kWordRegisterEnvironmentReadingName = "default_reading_entry_of_word_register"
}
