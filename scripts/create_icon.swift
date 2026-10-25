#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalog = projectRoot.appendingPathComponent("Resources/Assets.xcassets")
let iconDirectory = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red / 255, green / 255, blue / 255, alpha])!
}

let cream = color(246, 243, 234)
let ink = color(32, 57, 46)
let mint = color(211, 230, 205)
let orange = color(229, 163, 61)

context.setFillColor(cream)
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))

func rounded(_ rectangle: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rectangle, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawCard(center: CGPoint, rotation: CGFloat, fill: CGColor, openSmile: Bool) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: rotation * .pi / 180)
    let rectangle = CGRect(x: -174, y: -244, width: 348, height: 488)

    context.saveGState()
    context.translateBy(x: 10, y: -17)
    context.setFillColor(color(32, 57, 46, alpha: 0.10))
    context.addPath(rounded(rectangle, radius: 68))
    context.fillPath()
    context.restoreGState()

    context.setFillColor(fill)
    context.setStrokeColor(ink)
    context.setLineWidth(11)
    context.addPath(rounded(rectangle, radius: 68))
    context.drawPath(using: .fillStroke)

    context.setFillColor(ink)
    for x: CGFloat in [-66, 66] {
        context.addPath(rounded(CGRect(x: x - 13, y: 29, width: 26, height: 57), radius: 13))
        context.fillPath()
    }

    context.setLineCap(.round)
    context.setLineJoin(.round)
    if openSmile {
        context.move(to: CGPoint(x: -65, y: -40))
        context.addLine(to: CGPoint(x: 65, y: -40))
        context.addCurve(to: CGPoint(x: 0, y: -114), control1: CGPoint(x: 65, y: -90), control2: CGPoint(x: 37, y: -114))
        context.addCurve(to: CGPoint(x: -65, y: -40), control1: CGPoint(x: -37, y: -114), control2: CGPoint(x: -65, y: -90))
        context.closePath()
        context.fillPath()
    } else {
        context.setLineWidth(18)
        context.move(to: CGPoint(x: -56, y: -52))
        context.addCurve(to: CGPoint(x: 56, y: -52), control1: CGPoint(x: -40, y: -106), control2: CGPoint(x: 40, y: -106))
        context.strokePath()
    }
    context.restoreGState()
}

drawCard(center: CGPoint(x: 359, y: 472), rotation: 13, fill: mint, openSmile: false)
drawCard(center: CGPoint(x: 650, y: 538), rotation: -12, fill: orange, openSmile: true)

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(
    iconDirectory.appendingPathComponent("AppIcon.png") as CFURL,
    UTType.png.identifier as CFString, 1, nil
)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write AppIcon.png") }

let catalogJSON = """
{
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
let iconJSON = """
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try (catalogJSON + "\n").write(to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try (iconJSON + "\n").write(to: iconDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Created opaque 1024 × 1024 AppIcon.png")
