// Draws Flip's application icon and packs it into resources/Flip.icns.
//
// A generator rather than a checked-in image, so the icon can be adjusted by
// changing numbers instead of round-tripping through a drawing program — and so
// it needs nothing installed beyond the Swift toolchain the project already uses.
//
//   swift scripts/make-icon.swift        (or: make icon)
//
// The motif is the app's own: two window tiles, offset, the front one carrying
// the same blue selection ring the overlay draws.

import AppKit
import Foundation

// MARK: - Geometry, all on the 1024 canvas Apple asks for

let canvas: CGFloat = 1024

/// Apple leaves the outer tenth of the canvas empty and rounds what is left. Fill
/// the whole square instead and the icon looks oversized next to every other one.
let plateInset: CGFloat = 100
let plateRadius: CGFloat = 185

let tileSize = CGSize(width: 404, height: 274)
let tileRadius: CGFloat = 30
let backTileCentre = CGPoint(x: 452, y: 596)
let frontTileCentre = CGPoint(x: 572, y: 436)

// Taken from Theme.swift, so icon and overlay are recognisably the same app.
let plateTop = NSColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1)
let plateBottom = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
let selectionBlue = NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)

func rounded(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func tile(centredAt centre: CGPoint) -> CGRect {
    CGRect(
        x: centre.x - tileSize.width / 2,
        y: centre.y - tileSize.height / 2,
        width: tileSize.width,
        height: tileSize.height
    )
}

/// A line across the top of a tile, which is the least detail that still reads as
/// a window rather than a rectangle. Anything finer turns to mush at 32 points.
func drawTitleBar(in rect: CGRect, alpha: CGFloat) {
    let y = rect.maxY - 52
    let bar = NSBezierPath()
    bar.move(to: CGPoint(x: rect.minX, y: y))
    bar.line(to: CGPoint(x: rect.maxX, y: y))
    bar.lineWidth = 5
    NSColor(white: 1, alpha: alpha).setStroke()
    bar.stroke()
}

func drawIcon() {
    let plate = CGRect(
        x: plateInset, y: plateInset,
        width: canvas - plateInset * 2, height: canvas - plateInset * 2
    )
    let platePath = rounded(plate, plateRadius)

    NSGradient(starting: plateTop, ending: plateBottom)?
        .draw(in: platePath, angle: -90)

    // A hairline along the top edge, the same trick the overlay panel uses to keep
    // a dark surface from looking flat.
    platePath.addClip()
    let highlight = rounded(plate.insetBy(dx: 2, dy: 2), plateRadius - 2)
    highlight.lineWidth = 4
    NSColor(white: 1, alpha: 0.10).setStroke()
    highlight.stroke()

    let back = tile(centredAt: backTileCentre)
    let front = tile(centredAt: frontTileCentre)

    // Behind: dimmer, thinner, no ring — the window you are leaving. Not much
    // dimmer, though: at 16 points it is three pixels of difference against the
    // plate, and anything subtler simply vanishes.
    let backPath = rounded(back, tileRadius)
    NSColor(white: 1, alpha: 0.21).setFill()
    backPath.fill()
    NSColor(white: 1, alpha: 0.30).setStroke()
    backPath.lineWidth = 5
    backPath.stroke()
    drawTitleBar(in: back, alpha: 0.26)

    // A shadow only under the front tile, which is what separates the two at small
    // sizes far better than any difference in fill.
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()

    let frontPath = rounded(front, tileRadius)
    NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1).setFill()
    frontPath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor(white: 1, alpha: 0.16).setFill()
    frontPath.fill()
    selectionBlue.setStroke()
    frontPath.lineWidth = 12
    frontPath.stroke()
    drawTitleBar(in: front, alpha: 0.30)
}

// MARK: - Rendering

func render(at pixels: Int) -> Data {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: representation)!
    NSGraphicsContext.current = context

    let scale = CGFloat(pixels) / canvas
    context.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()

    NSGraphicsContext.restoreGraphicsState()

    return representation.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/Flip.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The names are fixed; iconutil rejects anything it does not recognise.
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                        (256, 1), (256, 2), (512, 1), (512, 2)] {
    let suffix = scale == 1 ? "" : "@2x"
    let name = "icon_\(points)x\(points)\(suffix).png"
    try render(at: points * scale).write(to: iconset.appendingPathComponent(name))
}

let icns = root.appendingPathComponent("resources/Flip.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

print("wrote \(icns.path)")
