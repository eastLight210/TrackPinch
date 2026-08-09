#!/usr/bin/env swift

import AppKit
import Foundation

private let arguments = CommandLine.arguments

guard arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: render_app_icon.swift INPUT.png OUTPUT.png\n".utf8)
    )
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let sourceImage = NSImage(contentsOf: inputURL) else {
    FileHandle.standardError.write(
        Data("Unable to read app icon source: \(inputURL.path)\n".utf8)
    )
    exit(1)
}

let pixelSize = 1_024
let canvas = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("Unable to allocate icon bitmap.\n".utf8))
    exit(1)
}

bitmap.size = canvas.size

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("Unable to create icon graphics context.\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
graphicsContext.imageInterpolation = .high
graphicsContext.cgContext.clear(canvas)
graphicsContext.cgContext.setAllowsAntialiasing(true)
graphicsContext.cgContext.setShouldAntialias(true)

// The selected artwork includes a presentation background outside its large
// glass tile. Clip to that tile so Finder and System Settings receive a native
// macOS icon silhouette with transparent corners.
let tileBounds = canvas.insetBy(dx: 80, dy: 80)
let tileMask = NSBezierPath(
    roundedRect: tileBounds,
    xRadius: 170,
    yRadius: 170
)
tileMask.addClip()

let sourceSize = sourceImage.size
let scale = max(
    canvas.width / sourceSize.width,
    canvas.height / sourceSize.height
)
let drawSize = NSSize(
    width: sourceSize.width * scale,
    height: sourceSize.height * scale
)
let drawRect = NSRect(
    x: canvas.midX - drawSize.width / 2,
    y: canvas.midY - drawSize.height / 2,
    width: drawSize.width,
    height: drawSize.height
)

sourceImage.draw(
    in: drawRect,
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Unable to encode app icon PNG.\n".utf8))
    exit(1)
}

do {
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(
        Data("Unable to write app icon: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
