// Draws the genmai app icons and writes them to Tools/assets/:
//
//   genmai.icon, genmai-settings.icon, genmai-uninstaller.icon   Icon Composer documents (the sources; they open in
//                                                                Xcode's Icon Composer)
//   genmai.car, genmai-settings.car, genmai-uninstaller.car      compiled by actool: copy into the bundle as
//                                                                Contents/Resources/Assets.car and set
//                                                                CFBundleIconName (macOS 26+: Liquid Glass, dark,
//                                                                tinted and clear appearances)
//   genmai.icns, genmai-settings.icns, genmai-uninstaller.icns   the same icons drawn flat on the macOS icon grid
//                                                                (CFBundleIconFile; used before macOS 26 and by
//                                                                tools reading .icns, e.g. make_installer_pkg.sh)
//   product_logo.png                                             128 px, the main icon
//
// genmai.icon is the input method itself: 玄 in Hiragino Mincho ProN W6 on a brown-rice gradient. The settings app
// (GenmaiTool) adds a gear badge and the uninstaller a trash badge in the lower right; 玄 and the background are the
// same in all three.
//
// Usage: swift Tools/make_icon.swift   (needs Xcode 26 or later for actool's .icon support)
import AppKit
import SwiftUI

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let assets = root.appending(path: "assets")
let work = FileManager.default.temporaryDirectory.appending(path: "genmai-icons")
try? FileManager.default.removeItem(at: work)
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

// MARK: - Artwork (unit square, origin bottom left; 1 = the icon shape)

let backgroundTop = NSColor(srgbRed: 0.83, green: 0.62, blue: 0.38, alpha: 1)
let backgroundBottom = NSColor(srgbRed: 0.55, green: 0.36, blue: 0.20, alpha: 1)
let glyphColor = NSColor(srgbRed: 1, green: 0.97, blue: 0.9, alpha: 1)

enum Badge: CaseIterable {
  case none, settings, uninstaller

  var name: String {
    switch self {
    case .none: "genmai"
    case .settings: "genmai-settings"
    case .uninstaller: "genmai-uninstaller"
    }
  }

  // Disc colors, top to bottom: graphite like System Settings, red for removal.
  var discColors: (NSColor, NSColor) {
    switch self {
    case .none, .settings:
      (NSColor(srgbRed: 0.60, green: 0.60, blue: 0.63, alpha: 1), NSColor(srgbRed: 0.34, green: 0.34, blue: 0.37, alpha: 1))
    case .uninstaller:
      (NSColor(srgbRed: 1.00, green: 0.42, blue: 0.36, alpha: 1), NSColor(srgbRed: 0.84, green: 0.16, blue: 0.13, alpha: 1))
    }
  }
}

// The badge disc: lower right, inside the shape's corner curve.
let badgeCenter = NSPoint(x: 0.75, y: 0.25)
let badgeRadius: CGFloat = 0.185

/// 玄 exactly as the original icon drew it: 62 % of the shape's height, centered, 2 % above the middle.
func drawGlyph(in rect: NSRect) {
  let font = NSFont(name: "Hiragino Mincho ProN W6", size: rect.height * 0.62) ?? .boldSystemFont(ofSize: rect.height * 0.62)
  let text = NSAttributedString(string: "玄", attributes: [.font: font, .foregroundColor: glyphColor])
  let bounds = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin])
  text.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2 + rect.height * 0.02))
}

func drawBackground(_ path: NSBezierPath) {
  NSGradient(starting: backgroundTop, ending: backgroundBottom)!.draw(in: path, angle: -90)
}

func discPath(in rect: NSRect) -> NSBezierPath {
  let c = NSPoint(x: rect.minX + badgeCenter.x * rect.width, y: rect.minY + badgeCenter.y * rect.height)
  let r = badgeRadius * rect.width
  return NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

func drawDisc(_ badge: Badge, in rect: NSRect, ring: Bool) {
  let disc = discPath(in: rect)
  let (top, bottom) = badge.discColors
  NSGradient(starting: top, ending: bottom)!.draw(in: disc, angle: -90)
  if ring {
    // Separates the disc from 玄 and the background when the system does not add its glass edge.
    glyphColor.setStroke()
    disc.lineWidth = rect.width * 0.014
    disc.stroke()
  }
}

/// The white symbol on the disc.
func symbolPath(_ badge: Badge, in rect: NSRect) -> NSBezierPath {
  let c = NSPoint(x: rect.minX + badgeCenter.x * rect.width, y: rect.minY + badgeCenter.y * rect.height)
  let r = badgeRadius * rect.width
  let path = NSBezierPath()
  path.windingRule = .evenOdd
  switch badge {
  case .none:
    break
  case .settings:
    // A gear: 10 teeth with straight flanks, a hub hole.
    let teeth = 10
    let outer = r * 0.72, root = r * 0.57, hole = r * 0.25
    let step = 2 * CGFloat.pi / CGFloat(teeth)
    let topHalf = step * 0.20, baseHalf = step * 0.29
    func point(_ radius: CGFloat, _ angle: CGFloat) -> NSPoint {
      NSPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
    }
    for i in 0..<teeth {
      let a = CGFloat.pi / 2 + CGFloat(i) * step
      let p0 = point(root, a - baseHalf)
      if i == 0 { path.move(to: p0) } else { path.line(to: p0) }
      path.line(to: point(outer, a - topHalf))
      path.appendArc(
        withCenter: c, radius: outer, startAngle: (a - topHalf) * 180 / .pi, endAngle: (a + topHalf) * 180 / .pi)
      path.line(to: point(root, a + baseHalf))
      path.appendArc(
        withCenter: c, radius: root, startAngle: (a + baseHalf) * 180 / .pi,
        endAngle: (a + step - baseHalf) * 180 / .pi)
    }
    path.close()
    path.appendOval(in: NSRect(x: c.x - hole, y: c.y - hole, width: 2 * hole, height: 2 * hole))
  case .uninstaller:
    // A trash can: lid with handle, tapered body with three slots.
    let u = r
    let lid = NSRect(x: c.x - 0.50 * u, y: c.y + 0.30 * u, width: 1.00 * u, height: 0.11 * u)
    path.append(NSBezierPath(roundedRect: lid, xRadius: 0.055 * u, yRadius: 0.055 * u))
    let handle = NSBezierPath(
      roundedRect: NSRect(x: c.x - 0.16 * u, y: c.y + 0.36 * u, width: 0.32 * u, height: 0.16 * u),
      xRadius: 0.06 * u, yRadius: 0.06 * u)
    handle.append(
      NSBezierPath(
        roundedRect: NSRect(x: c.x - 0.08 * u, y: c.y + 0.405 * u, width: 0.16 * u, height: 0.06 * u),
        xRadius: 0.03 * u, yRadius: 0.03 * u))
    handle.windingRule = .evenOdd
    path.append(handle)
    let body = NSBezierPath()
    let top = c.y + 0.23 * u, bottom = c.y - 0.52 * u, corner = 0.08 * u
    body.move(to: NSPoint(x: c.x - 0.40 * u, y: top))
    body.line(to: NSPoint(x: c.x + 0.40 * u, y: top))
    body.line(to: NSPoint(x: c.x + 0.33 * u, y: bottom + corner))
    body.curve(
      to: NSPoint(x: c.x + 0.33 * u - corner, y: bottom), controlPoint1: NSPoint(x: c.x + 0.325 * u, y: bottom),
      controlPoint2: NSPoint(x: c.x + 0.33 * u - corner / 2, y: bottom))
    body.line(to: NSPoint(x: c.x - 0.33 * u + corner, y: bottom))
    body.curve(
      to: NSPoint(x: c.x - 0.33 * u, y: bottom + corner),
      controlPoint1: NSPoint(x: c.x - 0.33 * u + corner / 2, y: bottom), controlPoint2: NSPoint(x: c.x - 0.325 * u, y: bottom))
    body.close()
    path.append(body)
    for dx in [-0.17, 0, 0.17] as [CGFloat] {
      path.append(
        NSBezierPath(
          roundedRect: NSRect(x: c.x + dx * u - 0.04 * u, y: c.y - 0.40 * u, width: 0.08 * u, height: 0.52 * u),
          xRadius: 0.04 * u, yRadius: 0.04 * u))
    }
  }
  return path
}

// MARK: - Rendering

func bitmap(_ size: Int, _ draw: (CGFloat) -> Void) -> Data {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSGraphicsContext.current!.imageInterpolation = .high
  draw(CGFloat(size))
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

/// The macOS icon grid: an 824/1024 shape centered in the canvas with continuous ("squircle") corners of 185.4/824
/// (22.5 %), the shape the system gives app icons.
func gridShape(_ s: CGFloat) -> (NSRect, NSBezierPath) {
  let side = s * 824 / 1024
  let rect = NSRect(x: (s - side) / 2, y: (s - side) / 2, width: side, height: side)
  let cgPath = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous).path(in: rect).cgPath
  return (rect, NSBezierPath(cgPath: cgPath))
}

/// The flat icon for the .icns: background, 玄 and the badge on the icon grid.
func renderFlat(_ badge: Badge, _ size: Int) -> Data {
  bitmap(size) { s in
    let (rect, shape) = gridShape(s)
    drawBackground(shape)
    drawGlyph(in: rect)
    if badge != .none {
      drawDisc(badge, in: rect, ring: true)
      NSColor.white.setFill()
      symbolPath(badge, in: rect).fill()
    }
  }
}

// MARK: - Icon Composer documents

/// Layers are full-canvas 1024 px images; in an .icon the canvas is the icon shape, the system masks it.
func writeIconDocument(_ badge: Badge) throws -> URL {
  let doc = assets.appending(path: "\(badge.name).icon")
  try? FileManager.default.removeItem(at: doc)
  let images = doc.appending(path: "Assets")
  try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
  let unit = NSRect(x: 0, y: 0, width: 1024, height: 1024)
  try bitmap(1024) { _ in drawGlyph(in: unit) }.write(to: images.appending(path: "glyph.png"))
  var groups: [String] = []
  if badge != .none {
    try bitmap(1024) { _ in drawDisc(badge, in: unit, ring: false) }.write(to: images.appending(path: "disc.png"))
    try bitmap(1024) { _ in
      NSColor.white.setFill()
      symbolPath(badge, in: unit).fill()
    }.write(to: images.appending(path: "symbol.png"))
    // Groups are listed top first. The badge is Liquid Glass with the system shadow.
    groups.append(
      """
          {
            "layers" : [
              { "glass" : true, "image-name" : "symbol.png", "name" : "symbol" },
              { "glass" : true, "image-name" : "disc.png", "name" : "disc" }
            ],
            "name" : "badge",
            "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
            "translucency" : { "enabled" : false, "value" : 0.5 }
          }
      """)
  }
  // 玄 stays flat (no glass, no shadow) so its shape and color are exactly the drawn ones.
  groups.append(
    """
        {
          "layers" : [
            { "glass" : false, "image-name" : "glyph.png", "name" : "glyph" }
          ],
          "name" : "glyph",
          "shadow" : { "kind" : "none", "opacity" : 0 },
          "translucency" : { "enabled" : false, "value" : 0 }
        }
    """)
  func srgb(_ c: NSColor) -> String {
    String(format: "srgb:%.5f,%.5f,%.5f,1.00000", c.redComponent, c.greenComponent, c.blueComponent)
  }
  let json = """
    {
      "fill" : {
        "linear-gradient" : [
          "\(srgb(backgroundTop))",
          "\(srgb(backgroundBottom))"
        ]
      },
      "groups" : [
    \(groups.joined(separator: ",\n"))
      ],
      "supported-platforms" : {
        "squares" : [
          "macOS"
        ]
      }
    }

    """
  try json.write(to: doc.appending(path: "icon.json"), atomically: true, encoding: .utf8)
  return doc
}

func run(_ tool: String, _ arguments: [String]) throws {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: tool)
  p.arguments = arguments
  let pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = pipe
  try p.run()
  let output = pipe.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  guard p.terminationStatus == 0 else {
    FileHandle.standardError.write(output)
    throw NSError(domain: "make_icon", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\(tool) failed"])
  }
}

for badge in Badge.allCases {
  // .icns from the flat drawing.
  let iconset = work.appending(path: "\(badge.name).iconset")
  try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
  for base in [16, 32, 128, 256, 512] {
    try renderFlat(badge, base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try renderFlat(badge, base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
  }
  try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", assets.appending(path: "\(badge.name).icns").path])

  // Assets.car from the Icon Composer document. actool also writes a small .icns (up to 256 px), not used.
  let doc = try writeIconDocument(badge)
  let out = work.appending(path: "\(badge.name).actool")
  try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
  try run(
    "/usr/bin/xcrun",
    [
      "actool", "--compile", out.path, "--platform", "macosx", "--minimum-deployment-target", "15.0",
      "--app-icon", badge.name, "--output-partial-info-plist", out.appending(path: "partial.plist").path,
      "--errors", "--warnings", doc.path,
    ])
  let car = assets.appending(path: "\(badge.name).car")
  try? FileManager.default.removeItem(at: car)
  try FileManager.default.copyItem(at: out.appending(path: "Assets.car"), to: car)
  print("wrote \(badge.name).icon, \(badge.name).car, \(badge.name).icns")
}
try renderFlat(.none, 128).write(to: assets.appending(path: "product_logo.png"))
print("wrote product_logo.png to \(assets.path)")
