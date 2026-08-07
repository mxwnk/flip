// Draws the backdrop of the disk image window into resources/dmg-background.tiff.
//
// A TIFF with both a normal and a doubled representation, which is how a Finder
// background stays crisp on a retina display — a plain PNG is measured in points
// and comes out soft.
//
// The icon positions here have to agree with the ones in scripts/make-dmg.sh, or
// the arrow points at nothing.

import AppKit
import Foundation

let width = 660.0
let height = 400.0

/// Where Finder puts the two icons, measured from the top left like Finder does.
let appIcon = CGPoint(x: 170, y: 205)
let applications = CGPoint(x: 490, y: 205)

// Taken from Theme.swift by way of the application icon, so the disk image, the
// icon and the overlay are recognisably one thing.
let plateTop = NSColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1)
let plateBottom = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
let selectionBlue = NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)

func draw(title: String, _ font: NSFont, _ colour: NSColor, centredAt point: CGPoint) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
    let size = title.size(withAttributes: attributes)
    title.draw(
        at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
        withAttributes: attributes
    )
}

/// Between the two icons, clear of both. Drawn rather than an image so it scales
/// with whatever the positions above end up being.
func drawArrow(from start: CGFloat, to end: CGFloat, y: CGFloat) {
    let head = 11.0
    let line = NSBezierPath()
    line.move(to: CGPoint(x: start, y: y))
    line.line(to: CGPoint(x: end - head, y: y))
    line.lineWidth = 3
    line.lineCapStyle = .round
    selectionBlue.withAlphaComponent(0.85).setStroke()
    line.stroke()

    let tip = NSBezierPath()
    tip.move(to: CGPoint(x: end, y: y))
    tip.line(to: CGPoint(x: end - head, y: y + head * 0.62))
    tip.line(to: CGPoint(x: end - head, y: y - head * 0.62))
    tip.close()
    selectionBlue.withAlphaComponent(0.85).setFill()
    tip.fill()
}

func drawBackground() {
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    NSGradient(starting: plateTop, ending: plateBottom)?.draw(in: bounds, angle: -90)

    draw(
        title: "Flip",
        .systemFont(ofSize: 34, weight: .semibold),
        NSColor(white: 1, alpha: 0.94),
        centredAt: CGPoint(x: width / 2, y: height - 74)
    )
    draw(
        title: "A window switcher for macOS that gets out of the way.",
        .systemFont(ofSize: 13),
        NSColor(white: 1, alpha: 0.5),
        centredAt: CGPoint(x: width / 2, y: height - 108)
    )

    // Finder counts from the top, this context from the bottom.
    let iconRow = height - appIcon.y
    drawArrow(from: appIcon.x + 82, to: applications.x - 82, y: iconRow)

    draw(
        title: "Drag Flip into Applications",
        .systemFont(ofSize: 12),
        NSColor(white: 1, alpha: 0.42),
        centredAt: CGPoint(x: width / 2, y: 62)
    )
}

func render(scale: Int) -> Data {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: representation)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()

    return representation.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let build = root.appendingPathComponent("build")
try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)

let single = build.appendingPathComponent("dmg-background.png")
let double = build.appendingPathComponent("dmg-background@2x.png")
try render(scale: 1).write(to: single)
try render(scale: 2).write(to: double)

let output = root.appendingPathComponent("resources/dmg-background.tiff")
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", single.path, double.path, "-out", output.path]
try tiffutil.run()
tiffutil.waitUntilExit()

guard tiffutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("tiffutil failed\n".utf8))
    exit(1)
}

print("wrote \(output.path)")
