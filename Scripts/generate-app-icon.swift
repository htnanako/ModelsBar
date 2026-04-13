#!/usr/bin/env swift

import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appending(path: "Resources", directoryHint: .isDirectory)
let iconsetURL = resourcesURL.appending(path: "ModelsBar.iconset", directoryHint: .isDirectory)
let outputURL = resourcesURL.appending(path: "ModelsBar.icns")

let sizes: [(name: String, points: CGFloat, scale: CGFloat)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

for icon in sizes {
    let pixels = Int(icon.points * icon.scale)
    let image = makeLogoImage(size: CGFloat(pixels))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: iconsetURL.appending(path: icon.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}

try? FileManager.default.removeItem(at: iconsetURL)
print("Generated \(outputURL.path)")

private func makeLogoImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    defer {
        image.unlockFocus()
    }

    let rect = NSRect(origin: .zero, size: image.size)
    let inset = size * 0.1
    let content = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = size * 0.24

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.15, green: 0.44, blue: 0.93, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.74, blue: 0.72, alpha: 1)
    ])!
    let background = NSBezierPath(roundedRect: content, xRadius: cornerRadius, yRadius: cornerRadius)
    gradient.draw(in: background, angle: 45)

    NSColor.white.withAlphaComponent(0.16).setStroke()
    background.lineWidth = max(1.6, size * 0.02)
    background.stroke()

    let barWidth = content.width * 0.14
    let gap = content.width * 0.09
    let leftX = content.minX + content.width * 0.2
    let baseY = content.minY + content.height * 0.18
    let heights = [content.height * 0.28, content.height * 0.46, content.height * 0.62]

    NSColor.white.withAlphaComponent(0.94).setFill()
    for (index, height) in heights.enumerated() {
        let x = leftX + CGFloat(index) * (barWidth + gap)
        let barRect = NSRect(x: x, y: baseY, width: barWidth, height: height)
        let radius = min(barWidth / 2, size * 0.08)
        NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius).fill()
    }

    NSColor(calibratedRed: 0.93, green: 1, blue: 0.98, alpha: 1).setStroke()
    let check = NSBezierPath()
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.lineWidth = max(1.8, size * 0.085)
    check.move(to: NSPoint(x: content.minX + content.width * 0.26, y: content.minY + content.height * 0.51))
    check.line(to: NSPoint(x: content.minX + content.width * 0.41, y: content.minY + content.height * 0.36))
    check.line(to: NSPoint(x: content.minX + content.width * 0.74, y: content.minY + content.height * 0.72))
    check.stroke()

    NSColor.white.withAlphaComponent(0.24).setFill()
    NSBezierPath(
        ovalIn: NSRect(
            x: content.minX + content.width * 0.68,
            y: content.minY + content.height * 0.14,
            width: content.width * 0.14,
            height: content.width * 0.14
        )
    ).fill()

    return image
}
