import AppKit
import Foundation

private let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  FileHandle.standardError.write(
    Data("usage: render_app_icon.swift OUTPUT.png\n".utf8))
  exit(64)
}

let outputURL = URL(fileURLWithPath: arguments[1])

let outputSide = 1024
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

let outputRect = CGRect(x: 0, y: 0, width: outputSide, height: outputSide)
let iconRect = outputRect.insetBy(dx: 54, dy: 54)
context.clear(outputRect)

// Draw the icon from geometry so 16 px and 32 px variants retain the same
// silhouette as the large artwork. The older photographic source lost most of
// the open ring when macOS downsampled it for sidebars.
context.saveGState()
context.setShadow(
  offset: CGSize(width: 0, height: -18), blur: 30,
  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42))
context.setFillColor(CGColor(red: 0.045, green: 0.059, blue: 0.078, alpha: 1))
context.addPath(
  CGPath(
    roundedRect: iconRect,
    cornerWidth: 202,
    cornerHeight: 202,
    transform: nil))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(
  CGPath(
    roundedRect: iconRect,
    cornerWidth: 202,
    cornerHeight: 202,
    transform: nil))
context.clip()

let arcCenter = CGPoint(x: 512, y: 516)
let arcPath = CGMutablePath()
arcPath.addArc(
  center: arcCenter,
  radius: 330,
  startAngle: radians(-50),
  endAngle: radians(230),
  clockwise: false)
context.addPath(arcPath)
context.setLineWidth(146)
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
  start: CGPoint(x: 160, y: 512),
  end: CGPoint(x: 864, y: 512),
  options: [])
context.restoreGState()

// A custom stroked infinity remains recognizable without overpowering the
// surrounding TokenLink arc at Finder/sidebar sizes.
let infinity = CGMutablePath()
infinity.move(to: CGPoint(x: 512, y: 512))
infinity.addCurve(
  to: CGPoint(x: 370, y: 425),
  control1: CGPoint(x: 450, y: 445),
  control2: CGPoint(x: 412, y: 425))
infinity.addCurve(
  to: CGPoint(x: 370, y: 599),
  control1: CGPoint(x: 300, y: 425),
  control2: CGPoint(x: 300, y: 599))
infinity.addCurve(
  to: CGPoint(x: 512, y: 512),
  control1: CGPoint(x: 412, y: 599),
  control2: CGPoint(x: 450, y: 579))
infinity.addCurve(
  to: CGPoint(x: 654, y: 425),
  control1: CGPoint(x: 574, y: 445),
  control2: CGPoint(x: 612, y: 425))
infinity.addCurve(
  to: CGPoint(x: 654, y: 599),
  control1: CGPoint(x: 724, y: 425),
  control2: CGPoint(x: 724, y: 599))
infinity.addCurve(
  to: CGPoint(x: 512, y: 512),
  control1: CGPoint(x: 612, y: 599),
  control2: CGPoint(x: 574, y: 579))
context.addPath(infinity)
context.setStrokeColor(CGColor(red: 0.95, green: 0.97, blue: 0.98, alpha: 1))
context.setLineWidth(80)
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
