// Draws the genmai product icon (a rounded square in brown-rice colors with 玄) and writes
// Tools/assets/genmai.icns and Tools/assets/product_logo.png.
// Usage: swift Tools/make_icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let assets = root.appending(path: "assets")
let iconset = FileManager.default.temporaryDirectory.appending(path: "genmai.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
  let s = CGFloat(size)
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let inset = s * 0.09
  let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
  let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
  NSGradient(
    starting: NSColor(srgbRed: 0.83, green: 0.62, blue: 0.38, alpha: 1),
    ending: NSColor(srgbRed: 0.55, green: 0.36, blue: 0.20, alpha: 1))!.draw(in: path, angle: -90)
  let font = NSFont(name: "Hiragino Mincho ProN W6", size: rect.height * 0.62) ?? .boldSystemFont(ofSize: rect.height * 0.62)
  let text = NSAttributedString(
    string: "玄", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 1, green: 0.97, blue: 0.9, alpha: 1)])
  let bounds = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin])
  text.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2 + rect.height * 0.02))
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
  try render(base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
  try render(base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try render(128).write(to: assets.appending(path: "product_logo.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", assets.appending(path: "genmai.icns").path]
try p.run()
p.waitUntilExit()
print("wrote \(assets.path)/genmai.icns, product_logo.png")
