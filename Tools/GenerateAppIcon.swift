import AppKit
import Foundation

enum IconGenerationError: Error {
    case missingGaugeSVG
    case invalidGaugeSVG
    case failedToEncodePNG
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let gaugeSVGURL = resources.appendingPathComponent("gauge.svg")

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

guard
    FileManager.default.fileExists(atPath: gaugeSVGURL.path)
else {
    throw IconGenerationError.missingGaugeSVG
}

let gaugeSVG = try String(contentsOf: gaugeSVGURL, encoding: .utf8)
    .replacingOccurrences(of: "currentColor", with: "rgb(26,27,26)")

guard
    let gaugeData = gaugeSVG.data(using: .utf8),
    let gaugeImage = NSImage(data: gaugeData)
else {
    throw IconGenerationError.invalidGaugeSVG
}

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
    let plateInset = CGFloat(pixelSize) * 0.095
    let plateRect = canvas.insetBy(dx: plateInset, dy: plateInset)

    drawPlate(in: plateRect, pixelSize: CGFloat(pixelSize))
    drawGauge(in: plateRect, gaugeImage: gaugeImage)

    return image
}

func drawPlate(in rect: NSRect, pixelSize: CGFloat) {
    let radius = rect.width * 0.23
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.18)
    shadow.shadowBlurRadius = pixelSize * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -pixelSize * 0.012)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()

    let gradient = NSGradient(
        starting: NSColor(srgbRed: 225 / 255, green: 224 / 255, blue: 225 / 255, alpha: 1),
        ending: NSColor(srgbRed: 195 / 255, green: 195 / 255, blue: 196 / 255, alpha: 1)
    )
    gradient?.draw(in: rect, angle: 90)

    let highlightRect = NSRect(
        x: rect.minX,
        y: rect.midY,
        width: rect.width,
        height: rect.height / 2
    )
    let highlight = NSGradient(
        colorsAndLocations:
            (NSColor(calibratedWhite: 1, alpha: 0.26), 0),
            (NSColor(calibratedWhite: 1, alpha: 0.06), 0.55),
            (NSColor(calibratedWhite: 1, alpha: 0), 1)
    )
    highlight?.draw(in: highlightRect, angle: 90)

    NSGraphicsContext.restoreGraphicsState()

    NSColor(srgbRed: 176 / 255, green: 176 / 255, blue: 178 / 255, alpha: 0.65).setStroke()
    path.lineWidth = max(1, pixelSize * 0.004)
    path.stroke()
}

func drawGauge(in rect: NSRect, gaugeImage: NSImage) {
    let glyphSide = rect.width * 0.62
    let glyphRect = NSRect(
        x: rect.midX - glyphSide / 2,
        y: rect.midY - glyphSide / 2,
        width: glyphSide,
        height: glyphSide
    )

    gaugeImage.draw(
        in: glyphRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
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
