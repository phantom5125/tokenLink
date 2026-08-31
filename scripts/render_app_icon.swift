import AppKit
import Foundation

private let arguments = CommandLine.arguments
guard
  arguments.count == 3,
  let outputSide = Int(arguments[2]),
  outputSide > 0
else {
  FileHandle.standardError.write(
    Data("usage: render_app_icon.swift OUTPUT.png PIXELS\n".utf8))
  exit(64)
}

let outputURL = URL(fileURLWithPath: arguments[1])

guard
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
  let context = CGContext(
    data: nil,
    width: outputSide,
    height: outputSide,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
  FileHandle.standardError.write(Data("Could not create the icon renderer\n".utf8))
  exit(70)
}

func radians(_ degrees: CGFloat) -> CGFloat {
  degrees * .pi / 180
}

let side = CGFloat(outputSide)
let outputRect = CGRect(x: 0, y: 0, width: side, height: side)
let iconRect = outputRect.insetBy(dx: side * 54 / 1024, dy: side * 54 / 1024)
context.clear(outputRect)

// Draw every icon master from geometry so small variants retain the intended
// open-ring silhouette. The older photographic source lost most of the gap
// when macOS downsampled it for sidebars.
context.saveGState()
context.setShadow(
  offset: CGSize(width: 0, height: -side * 18 / 1024), blur: side * 30 / 1024,
  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42))
context.setFillColor(CGColor(red: 0.045, green: 0.059, blue: 0.078, alpha: 1))
context.addPath(
  CGPath(
    roundedRect: iconRect,
    cornerWidth: side * 202 / 1024,
    cornerHeight: side * 202 / 1024,
    transform: nil))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(
  CGPath(
    roundedRect: iconRect,
    cornerWidth: side * 202 / 1024,
    cornerHeight: side * 202 / 1024,
    transform: nil))
context.clip()

// Small masters need a slimmer, slightly inset arc as well as an optical gap.
// Otherwise the rounded stroke reads as a clipped U instead of an open ring.
let (arcRadiusUnits, arcLineWidthUnits, gapDegrees): (CGFloat, CGFloat, CGFloat) =
  switch outputSide {
  case ...16: (312, 104, 104)
  case ...32: (320, 116, 96)
  case ...64: (326, 132, 88)
  default: (330, 146, 80)
  }
let arcCenter = CGPoint(x: side / 2, y: side * 516 / 1024)
let arcPath = CGMutablePath()
arcPath.addArc(
  center: arcCenter,
  radius: side * arcRadiusUnits / 1024,
  startAngle: radians(-90 + gapDegrees / 2),
  endAngle: radians(270 - gapDegrees / 2),
  clockwise: false)
context.addPath(arcPath)
context.setLineWidth(side * arcLineWidthUnits / 1024)
context.setLineCap(.round)
context.replacePathWithStrokedPath()
context.clip()

let arcColors = [
  CGColor(red: 0.02, green: 0.86, blue: 0.67, alpha: 1),
  CGColor(red: 0.04, green: 0.78, blue: 0.65, alpha: 1),
  CGColor(red: 0.95, green: 0.97, blue: 0.98, alpha: 1),
] as CFArray
let arcLocations: [CGFloat] = [0, 0.56, 1]
guard
  let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: arcColors,
    locations: arcLocations)
else {
  FileHandle.standardError.write(Data("Could not create the icon gradient\n".utf8))
  exit(70)
}
context.drawLinearGradient(
  gradient,
  start: CGPoint(x: side * 160 / 1024, y: side / 2),
  end: CGPoint(x: side * 864 / 1024, y: side / 2),
  options: [])
context.restoreGState()

// A custom stroked infinity remains recognizable without overpowering the
// surrounding TokenLink arc at Finder/sidebar sizes.
let infinity = CGMutablePath()
infinity.move(to: CGPoint(x: side * 512 / 1024, y: side * 512 / 1024))
infinity.addCurve(
  to: CGPoint(x: side * 370 / 1024, y: side * 425 / 1024),
  control1: CGPoint(x: side * 450 / 1024, y: side * 445 / 1024),
  control2: CGPoint(x: side * 412 / 1024, y: side * 425 / 1024))
infinity.addCurve(
  to: CGPoint(x: side * 370 / 1024, y: side * 599 / 1024),
  control1: CGPoint(x: side * 300 / 1024, y: side * 425 / 1024),
  control2: CGPoint(x: side * 300 / 1024, y: side * 599 / 1024))
infinity.addCurve(
  to: CGPoint(x: side * 512 / 1024, y: side * 512 / 1024),
  control1: CGPoint(x: side * 412 / 1024, y: side * 599 / 1024),
  control2: CGPoint(x: side * 450 / 1024, y: side * 579 / 1024))
infinity.addCurve(
  to: CGPoint(x: side * 654 / 1024, y: side * 425 / 1024),
  control1: CGPoint(x: side * 574 / 1024, y: side * 445 / 1024),
  control2: CGPoint(x: side * 612 / 1024, y: side * 425 / 1024))
infinity.addCurve(
  to: CGPoint(x: side * 654 / 1024, y: side * 599 / 1024),
  control1: CGPoint(x: side * 724 / 1024, y: side * 425 / 1024),
  control2: CGPoint(x: side * 724 / 1024, y: side * 599 / 1024))
infinity.addCurve(
  to: CGPoint(x: side * 512 / 1024, y: side * 512 / 1024),
  control1: CGPoint(x: side * 612 / 1024, y: side * 599 / 1024),
  control2: CGPoint(x: side * 574 / 1024, y: side * 579 / 1024))
context.addPath(infinity)
context.setStrokeColor(CGColor(red: 0.95, green: 0.97, blue: 0.98, alpha: 1))
context.setLineWidth(side * 80 / 1024)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

guard let renderedImage = context.makeImage() else {
  FileHandle.standardError.write(Data("Could not render the icon\n".utf8))
  exit(70)
}

let bitmap = NSBitmapImageRep(cgImage: renderedImage)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
  FileHandle.standardError.write(Data("Could not encode the icon as PNG\n".utf8))
  exit(70)
}

do {
  try png.write(to: outputURL, options: .atomic)
} catch {
  FileHandle.standardError.write(Data("Could not write \(outputURL.path): \(error)\n".utf8))
  exit(74)
}
