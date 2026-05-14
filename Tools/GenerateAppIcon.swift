import AppKit
import Foundation

enum IconGenerationError: Error {
    case failedToEncodePNG
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)

let sizes: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2),
]

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> NSImage {
    let size = NSSize(width: pixelSize, height: pixelSize)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    NSGraphicsContext.current?.imageInterpolation = .high

    let canvas = NSRect(origin: .zero, size: size)
    let plateInset = CGFloat(pixelSize) * 0.06
    let plateRect = canvas.insetBy(dx: plateInset, dy: plateInset)

    drawPlate(in: plateRect, pixelSize: CGFloat(pixelSize))
    drawDuck(in: plateRect, pixelSize: CGFloat(pixelSize))

    return image
}

/// Liquid-glass-style black plate: deep black fill, glossy top rim,
/// soft bottom highlight, and a bright corner sheen reminiscent of
/// the Tahoe "Liquid Glass" look.
func drawPlate(in rect: NSRect, pixelSize: CGFloat) {
    let radius = rect.width * 0.224
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Drop shadow under the plate.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.32)
    shadow.shadowBlurRadius = pixelSize * 0.045
    shadow.shadowOffset = NSSize(width: 0, height: -pixelSize * 0.022)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()

    // Subtle vertical gradient: charcoal at top → pure black at bottom.
    // Gives the plate depth without lifting it away from solid black.
    let bodyGradient = NSGradient(
        starting: NSColor(srgbRed: 36 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1),
        ending: NSColor.black
    )
    bodyGradient?.draw(in: rect, angle: 270)

    // Glossy top rim — the bright catch-light typical of Liquid Glass.
    let topRimRect = NSRect(
        x: rect.minX,
        y: rect.minY + rect.height * 0.55,
        width: rect.width,
        height: rect.height * 0.45
    )
    let topRim = NSGradient(
        colorsAndLocations:
            (NSColor(calibratedWhite: 1, alpha: 0.00), 0.0),
            (NSColor(calibratedWhite: 1, alpha: 0.08), 0.55),
            (NSColor(calibratedWhite: 1, alpha: 0.28), 0.92),
            (NSColor(calibratedWhite: 1, alpha: 0.16), 1.0)
    )
    topRim?.draw(in: topRimRect, angle: 90)

    // Soft bottom reflection — Liquid Glass picks up a hint of light from below.
    let bottomRimRect = NSRect(
        x: rect.minX,
        y: rect.minY,
        width: rect.width,
        height: rect.height * 0.22
    )
    let bottomRim = NSGradient(
        colorsAndLocations:
            (NSColor(calibratedWhite: 1, alpha: 0.10), 0.0),
            (NSColor(calibratedWhite: 1, alpha: 0.02), 0.6),
            (NSColor(calibratedWhite: 1, alpha: 0.0), 1.0)
    )
    bottomRim?.draw(in: bottomRimRect, angle: 90)

    // Diagonal corner sheen — a faint white wash from the top-left,
    // mimicking a specular highlight on glass.
    let cornerSheen = NSGradient(
        colorsAndLocations:
            (NSColor(calibratedWhite: 1, alpha: 0.12), 0),
            (NSColor(calibratedWhite: 1, alpha: 0.02), 0.45),
            (NSColor(calibratedWhite: 1, alpha: 0), 1)
    )
    cornerSheen?.draw(in: rect, angle: 315)

    NSGraphicsContext.restoreGraphicsState()

    // Inner highlight stroke — the bright "glass edge" of the plate.
    let innerInset: CGFloat = max(0.5, pixelSize * 0.0025)
    let innerPath = NSBezierPath(
        roundedRect: rect.insetBy(dx: innerInset, dy: innerInset),
        xRadius: radius - innerInset,
        yRadius: radius - innerInset
    )
    NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
    innerPath.lineWidth = max(1, pixelSize * 0.005)
    innerPath.stroke()

    // Crisp outer hairline — defines the silhouette against light backgrounds.
    NSColor(calibratedWhite: 0, alpha: 0.55).setStroke()
    path.lineWidth = max(1, pixelSize * 0.003)
    path.stroke()
}

/// Centered white duck silhouette — same geometry as the menu bar icon
/// but scaled up to fill ~70% of the plate.
func drawDuck(in rect: NSRect, pixelSize: CGFloat) {
    let duckUnit: CGFloat = 22 // duck path is authored in a 22 × 22 box
    let targetSide = rect.width * 0.72
    let scale = targetSide / duckUnit

    // Duck bounding box (in duck units) is approximately x: 0.6→21.3, y: 3→16.5
    // → width ≈ 20.7, height ≈ 13.5. Center the rendered duck on the plate.
    let duckWidth: CGFloat = 20.7 * scale
    let duckHeight: CGFloat = 13.5 * scale
    let duckOriginX = rect.midX - duckWidth / 2
    // Optical balance — sit the duck slightly above the geometric centerline
    // so the wider body doesn't look bottom-heavy.
    let duckOriginY = rect.midY - duckHeight / 2 + pixelSize * 0.005

    NSGraphicsContext.saveGraphicsState()
    let xform = NSAffineTransform()
    // Translate so duck unit (0.6, 3) maps to the plate origin we computed.
    xform.translateX(by: duckOriginX - 0.6 * scale, yBy: duckOriginY - 3 * scale)
    xform.scale(by: scale)
    xform.concat()

    // Soft glow under the duck — a very subtle inner-shadow feel.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.55)
    shadow.shadowBlurRadius = (pixelSize * 0.018) / scale
    shadow.shadowOffset = NSSize(width: 0, height: -(pixelSize * 0.005) / scale)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    duckSilhouette().fill()
    NSGraphicsContext.restoreGraphicsState()

    // Eye — punch a small black dot back into the head.
    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: 15.0, y: 12.5, width: 1.6, height: 1.6)).fill()

    NSGraphicsContext.restoreGraphicsState()
}

/// Side-profile duck silhouette in a 22 × 22 coordinate space, facing right.
func duckSilhouette() -> NSBezierPath {
    let path = NSBezierPath()
    path.windingRule = .nonZero

    path.append(NSBezierPath(ovalIn: NSRect(x: 1, y: 3, width: 16, height: 8.5)))
    path.append(NSBezierPath(ovalIn: NSRect(x: 10, y: 7.5, width: 9, height: 9)))

    let beak = NSBezierPath()
    beak.move(to: NSPoint(x: 17, y: 13.6))
    beak.curve(
        to: NSPoint(x: 21.3, y: 12.6),
        controlPoint1: NSPoint(x: 19, y: 13.4),
        controlPoint2: NSPoint(x: 21, y: 13.0)
    )
    beak.curve(
        to: NSPoint(x: 21.3, y: 11.6),
        controlPoint1: NSPoint(x: 21.5, y: 12.3),
        controlPoint2: NSPoint(x: 21.5, y: 11.9)
    )
    beak.curve(
        to: NSPoint(x: 17, y: 11.4),
        controlPoint1: NSPoint(x: 20, y: 11.4),
        controlPoint2: NSPoint(x: 18.5, y: 11.4)
    )
    beak.close()
    path.append(beak)

    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 3, y: 9.5))
    tail.curve(
        to: NSPoint(x: 0.6, y: 11.4),
        controlPoint1: NSPoint(x: 2, y: 10.5),
        controlPoint2: NSPoint(x: 1, y: 11.0)
    )
    tail.line(to: NSPoint(x: 3.5, y: 11.0))
    tail.close()
    path.append(tail)

    return path
}

for size in sizes {
    let pixels = size.points * size.scale
    let image = renderIcon(pixelSize: pixels)
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw IconGenerationError.failedToEncodePNG
    }

    try png.write(to: iconset.appendingPathComponent(size.name))
}

print("Wrote \(sizes.count) PNGs to \(iconset.path)")
