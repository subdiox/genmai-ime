// Port of mozc/src/renderer/renderer_style_handler.{h,cc} (3.35.6354).
//
// The text protos renderer/renderer_style.textproto and renderer_style_dark.textproto are embedded below
// (the C++ build embeds them as renderer_style.inc / renderer_style_dark.inc).

import GenmaiBase
import GenmaiProtocol
import SwiftProtobuf

public typealias RendererStyle = Genmai_Renderer_RendererStyle

public enum RendererStyleHandler {
  /// Color theme of the candidate window. kDark mirrors the system dark-mode preference.
  public enum ColorTheme: Sendable {
    case light
    case dark
  }

  /// Returns the style for the light theme.
  public static func getRendererStyle() -> RendererStyle {
    getRendererStyle(.light)
  }

  /// Returns the style for the specified color theme.
  public static func getRendererStyle(_ theme: ColorTheme) -> RendererStyle {
    let styleTextProto = theme == .dark ? kStyleDarkTextProto : kStyleTextProto
    // CHECK(ParseFromString) in C++: the embedded text protos are known to be valid.
    var style = try! RendererStyle(textFormatString: styleTextProto)

    if !style.candidateStyle.hasBackgroundColor {
      setRgbaColor(&style.candidateStyle.backgroundColor, 255, 255, 255)
    }

    sanitizeMessageStrings(&style)
    return style
  }

  private static func setRgbaColor(
    _ color: inout RendererStyle.RGBAColor, _ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0
  ) {
    color.r = r
    color.g = g
    color.b = b
    color.a = a
  }

  /// protobuf_util::SanitizeMessageStrings over the string fields of RendererStyle: limit the length of the
  /// string to 100 bytes and remove ill-formed UTF-8 sequences and ASCII control characters.
  private static func sanitizeMessageStrings(_ style: inout RendererStyle) {
    func sanitize(_ value: inout String, isSet: Bool) {
      guard isSet, let newValue = TextNormalizer.sanitizeText(value, 100) else { return }
      value = newValue
    }
    func sanitize(_ textStyle: inout RendererStyle.TextStyle, isSet: Bool) {
      guard isSet else { return }
      sanitize(&textStyle.fontName, isSet: textStyle.hasFontName)
    }
    sanitize(&style.columnMinimumWidthString, isSet: style.hasColumnMinimumWidthString)
    sanitize(&style.logoFileName, isSet: style.hasLogoFileName)
    sanitize(&style.shortcutStyle, isSet: style.hasShortcutStyle)
    sanitize(&style.gap1Style, isSet: style.hasGap1Style)
    sanitize(&style.candidateStyle, isSet: style.hasCandidateStyle)
    sanitize(&style.descriptionStyle, isSet: style.hasDescriptionStyle)
    sanitize(&style.footerStyle, isSet: style.hasFooterStyle)
    sanitize(&style.footerSubLabelStyle, isSet: style.hasFooterSubLabelStyle)
    if style.hasInfolistStyle {
      sanitize(&style.infolistStyle.captionString, isSet: style.infolistStyle.hasCaptionString)
      sanitize(&style.infolistStyle.captionStyle, isSet: style.infolistStyle.hasCaptionStyle)
      sanitize(&style.infolistStyle.titleStyle, isSet: style.infolistStyle.hasTitleStyle)
      sanitize(&style.infolistStyle.descriptionStyle, isSet: style.infolistStyle.hasDescriptionStyle)
    }
  }
}

// renderer/renderer_style.textproto
private let kStyleTextProto = """
window_border: 1
scrollbar_width: 4
row_rect_padding: 1
border_color { r: 150 g: 150 b: 150 }
shortcut_style {
  font_size: 14
  foreground_color { r: 97 g: 97 b: 97 }
  background_color { r: 243 g: 244 b: 255 }
  left_padding: 8
  right_padding: 8
}
gap1_style { font_size: 14 }
candidate_style {
  font_size: 14
  foreground_color { r: 0 g: 0 b: 0 }
}
description_style {
  font_size: 12
  foreground_color { r: 136 g: 136 b: 136 }
  right_padding: 8
}
column_minimum_width_string: "そのほかの文字種"
footer_style {
  font_size: 14
  foreground_color { r: 76 g: 76 b: 76 }
  left_padding: 4
  right_padding: 4
}
footer_sub_label_style {
  font_size: 10
  foreground_color { r: 167 g: 167 b: 167 }
  left_padding: 4
  right_padding: 4
}
footer_border_colors { r: 96 g: 96 b: 96 }
footer_top_color { r: 255 g: 255 b: 255 }
footer_bottom_color { r: 238 g: 238 b: 238 }
logo_file_name: "candidate_window_logo.tiff"
focused_background_color { r: 209 g: 234 b: 255 }
focused_border_color { r: 127 g: 172 b: 221 }
scrollbar_background_color { r: 224 g: 224 b: 224 }
scrollbar_indicator_color { r: 117 g: 144 b: 184 }
infolist_style {
  caption_string: "用例"
  caption_height: 20
  caption_padding: 1
  caption_style { font_size: 12 left_padding: 2 }
  caption_background_color { r: 236 g: 240 b: 250 }
  window_border: 1
  row_rect_padding: 2
  window_width: 300
  title_style { font_size: 15 left_padding: 5 }
  description_style { font_size: 12 left_padding: 15 }
  border_color { r: 150 g: 150 b: 150 }
  focused_background_color { r: 209 g: 234 b: 255 }
  focused_border_color { r: 127 g: 172 b: 221 }
}
"""

// renderer/renderer_style_dark.textproto
private let kStyleDarkTextProto = """
window_border: 1
scrollbar_width: 4
row_rect_padding: 1
border_color { r: 74 g: 74 b: 74 }
shortcut_style {
  font_size: 14
  foreground_color { r: 144 g: 144 b: 144 }
  background_color { r: 50 g: 51 b: 58 }
  left_padding: 8
  right_padding: 8
}
gap1_style { font_size: 14 }
candidate_style {
  font_size: 14
  foreground_color { r: 229 g: 229 b: 229 }
  background_color { r: 44 g: 44 b: 44 }
}
description_style {
  font_size: 12
  foreground_color { r: 144 g: 144 b: 144 }
  right_padding: 8
}
column_minimum_width_string: "そのほかの文字種"
footer_style {
  font_size: 14
  foreground_color { r: 144 g: 144 b: 144 }
  left_padding: 4
  right_padding: 4
}
footer_sub_label_style {
  font_size: 10
  foreground_color { r: 128 g: 128 b: 128 }
  left_padding: 4
  right_padding: 4
}
footer_border_colors { r: 74 g: 74 b: 74 }
footer_top_color { r: 33 g: 33 b: 33 }
footer_bottom_color { r: 33 g: 33 b: 33 }
logo_file_name: "candidate_window_logo.tiff"
focused_background_color { r: 61 g: 61 b: 61 }
focused_border_color { r: 85 g: 85 b: 85 }
scrollbar_background_color { r: 53 g: 53 b: 53 }
scrollbar_indicator_color { r: 110 g: 110 b: 110 }
infolist_style {
  caption_string: "用例"
  caption_height: 20
  caption_padding: 1
  caption_style {
    font_size: 12
    left_padding: 2
    foreground_color { r: 229 g: 229 b: 229 }
  }
  caption_background_color { r: 33 g: 33 b: 33 }
  window_border: 1
  row_rect_padding: 2
  window_width: 300
  title_style {
    font_size: 15
    left_padding: 5
    foreground_color { r: 229 g: 229 b: 229 }
  }
  description_style {
    font_size: 12
    left_padding: 15
    foreground_color { r: 176 g: 176 b: 176 }
  }
  border_color { r: 74 g: 74 b: 74 }
  focused_background_color { r: 61 g: 61 b: 61 }
  focused_border_color { r: 85 g: 85 b: 85 }
}
"""
