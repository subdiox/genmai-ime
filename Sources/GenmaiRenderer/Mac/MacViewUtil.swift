// Port of mozc/src/renderer/mac/mac_view_util.{h,mm} (3.35.6354).

import AppKit
import GenmaiProtocol
import SwiftUI

public enum MacViewUtil {
  public static func toNSPoint(_ point: Point) -> NSPoint { NSPoint(x: point.x, y: point.y) }
  public static func toPoint(_ nspoint: NSPoint) -> Point { Point(Int(nspoint.x), Int(nspoint.y)) }
  public static func toNSSize(_ size: Size) -> NSSize { NSSize(width: size.width, height: size.height) }
  public static func toSize(_ nssize: NSSize) -> Size { Size(Int(nssize.width), Int(nssize.height)) }

  public static func toNSRect(_ rect: Rect) -> NSRect {
    NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
  }

  public static func toRect(_ nsrect: NSRect) -> Rect { Rect(toPoint(nsrect.origin), toSize(nsrect.size)) }

  /// Adds the left and right paddings of `style` to `size`.
  public static func applyTheme(_ size: NSSize, _ style: RendererStyle.TextStyle) -> NSSize {
    NSSize(
      width: size.width + CGFloat(style.leftPadding) + CGFloat(style.rightPadding), height: size.height)
  }

  public static func toNSColor(_ color: RendererStyle.RGBAColor) -> NSColor {
    NSColor(
      calibratedRed: color.r / 255.0, green: color.g / 255.0, blue: color.b / 255.0, alpha: color.a)
  }

  /// SwiftUI counterpart of toNSColor.
  public static func toColor(_ color: RendererStyle.RGBAColor) -> Color { Color(nsColor: toNSColor(color)) }

  /// The font of `style`: `font_name` if set, otherwise the message font.
  public static func toNSFont(_ style: RendererStyle.TextStyle) -> NSFont {
    if style.hasFontName, let font = NSFont(name: style.fontName, size: style.fontSize) {
      return font
    }
    return NSFont.messageFont(ofSize: style.fontSize)
  }

  public static func toNSAttributedString(_ str: String, _ style: RendererStyle.TextStyle)
    -> NSAttributedString
  {
    var attributes: [NSAttributedString.Key: Any] = [.font: toNSFont(style)]
    if style.hasForegroundColor {
      attributes[.foregroundColor] = toNSColor(style.foregroundColor)
    }
    return NSAttributedString(string: str, attributes: attributes)
  }
}

/// Measures text the way CandidateView / InfolistView do (`-[NSAttributedString size]` and
/// `boundingRectWithSize:options:NSStringDrawingUsesLineFragmentOrigin`). Injected so that the layout logic
/// can be tested with deterministic metrics.
public protocol TextMeasuring: Sendable {
  /// Single-line size.
  func size(of text: String, style: RendererStyle.TextStyle) -> CGSize
  /// Multi-line bounding size within `width`.
  func boundingSize(of text: String, style: RendererStyle.TextStyle, width: CGFloat) -> CGSize
}

public struct AppKitTextMeasurer: TextMeasuring {
  public init() {}

  public func size(of text: String, style: RendererStyle.TextStyle) -> CGSize {
    MacViewUtil.toNSAttributedString(text, style).size()
  }

  public func boundingSize(of text: String, style: RendererStyle.TextStyle, width: CGFloat) -> CGSize {
    MacViewUtil.toNSAttributedString(text, style)
      .boundingRect(with: NSSize(width: width, height: 1000), options: .usesLineFragmentOrigin).size
  }
}
