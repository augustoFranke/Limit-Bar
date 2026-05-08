import AppKit

enum StatusIconFactory {
    static func makeImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        let fallback = NSImage(size: NSSize(width: 18, height: 18))
        fallback.lockFocus()
        NSColor.labelColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: 3, y: 4))
        path.curve(to: NSPoint(x: 15, y: 4), controlPoint1: NSPoint(x: 5, y: 12), controlPoint2: NSPoint(x: 13, y: 12))
        path.move(to: NSPoint(x: 9, y: 7))
        path.line(to: NSPoint(x: 12, y: 10))
        path.stroke()
        fallback.unlockFocus()
        fallback.isTemplate = true
        return fallback
    }
}
