import AppKit
import Foundation

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .deletingLastPathComponent()
let output = projectRoot.appendingPathComponent("assets/ClearDisplayVolume.icns")

func drawIcon(size: Int) -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0),
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
  else { fatalError("Could not create icon bitmap") }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = graphics
  let context = graphics.cgContext
  context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

  let shell = CGPath(
    roundedRect: CGRect(x: 84, y: 84, width: 856, height: 856),
    cornerWidth: 190, cornerHeight: 190, transform: nil)
  context.addPath(shell)
  context.clip()
  let colors =
    [
      NSColor(srgbRed: 0.08, green: 0.41, blue: 0.84, alpha: 1).cgColor,
      NSColor(srgbRed: 0.07, green: 0.15, blue: 0.45, alpha: 1).cgColor,
    ] as CFArray
  let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
  context.drawLinearGradient(
    gradient, start: CGPoint(x: 200, y: 950), end: CGPoint(x: 800, y: 80), options: [])

  context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
  context.setLineWidth(13)
  context.addPath(
    CGPath(
      roundedRect: CGRect(x: 91, y: 91, width: 842, height: 842),
      cornerWidth: 183, cornerHeight: 183, transform: nil))
  context.strokePath()

  context.setFillColor(NSColor.white.cgColor)
  context.addPath(
    CGPath(
      roundedRect: CGRect(x: 224, y: 346, width: 576, height: 400),
      cornerWidth: 57, cornerHeight: 57, transform: nil))
  context.fillPath()

  context.setFillColor(NSColor(srgbRed: 0.10, green: 0.34, blue: 0.69, alpha: 1).cgColor)
  context.addPath(
    CGPath(
      roundedRect: CGRect(x: 251, y: 373, width: 522, height: 346),
      cornerWidth: 35, cornerHeight: 35, transform: nil))
  context.fillPath()

  context.setFillColor(NSColor(srgbRed: 0.38, green: 0.84, blue: 1, alpha: 1).cgColor)
  for x in [430, 516] {
    for y in [493, 579] {
      context.fill(CGRect(x: x, y: y, width: 69, height: 69))
    }
  }

  context.setFillColor(NSColor.white.cgColor)
  context.fill(CGRect(x: 479, y: 253, width: 66, height: 93))
  context.addPath(
    CGPath(
      roundedRect: CGRect(x: 361, y: 221, width: 302, height: 49),
      cornerWidth: 24, cornerHeight: 24, transform: nil))
  context.fillPath()
  NSGraphicsContext.restoreGraphicsState()

  guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon bitmap")
  }
  return data
}

func appendLength(_ length: Int, to data: inout Data) {
  var value = UInt32(length).bigEndian
  withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
}

var chunks = Data()
for (type, size) in [
  ("icp4", 16), ("icp5", 32), ("icp6", 64),
  ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
] {
  let png = drawIcon(size: size)
  chunks.append(contentsOf: type.utf8)
  appendLength(8 + png.count, to: &chunks)
  chunks.append(png)
}

var icon = Data("icns".utf8)
appendLength(8 + chunks.count, to: &icon)
icon.append(chunks)
try FileManager.default.createDirectory(
  at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try icon.write(to: output)
print("Generated \(output.path)")
