import AppKit
import Foundation

private let arguments = CommandLine.arguments
guard arguments.count == 3 else {
  FileHandle.standardError.write(
    Data("usage: render_app_icon.swift INPUT.png OUTPUT.png\n".utf8))
  exit(64)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard
  let sourceImage = NSImage(contentsOf: inputURL),
  let sourceCGImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
  FileHandle.standardError.write(Data("Could not read \(inputURL.path)\n".utf8))
  exit(65)
}

// The selected 2048 px artwork includes a presentation canvas around the icon.
// Crop that canvas before applying a deterministic macOS-style rounded mask.
let sourceSide = min(sourceCGImage.width, sourceCGImage.height)
let cropInset = sourceSide / 16
let cropSide = sourceSide - (cropInset * 2)
let cropRect = CGRect(
  x: (sourceCGImage.width - cropSide) / 2,
  y: (sourceCGImage.height - cropSide) / 2,
  width: cropSide,
  height: cropSide)

guard let croppedImage = sourceCGImage.cropping(to: cropRect) else {
  FileHandle.standardError.write(Data("Could not crop \(inputURL.path)\n".utf8))
  exit(65)
}

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

let outputRect = CGRect(x: 0, y: 0, width: outputSide, height: outputSide)
context.clear(outputRect)
context.addPath(
  CGPath(
    roundedRect: outputRect,
    cornerWidth: CGFloat(outputSide) * 0.22,
    cornerHeight: CGFloat(outputSide) * 0.22,
    transform: nil))
context.clip()
context.interpolationQuality = .high
context.draw(croppedImage, in: outputRect)

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
