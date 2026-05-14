import AppKit

enum StatusIconFactory {
    static func makeImage() -> NSImage {
        let pointSize: CGFloat = 22
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        NSColor.labelColor.setFill()
        duckSilhouette().fill()

        // Punch a small eye out of the head so the duck is unmistakable
        // even at status-bar sizes.
        if let ctx = NSGraphicsContext.current {
            ctx.saveGraphicsState()
            ctx.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 15.0, y: 12.5, width: 1.6, height: 1.6)).fill()
            ctx.restoreGraphicsState()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Side-profile duck silhouette in a 22 × 22 coordinate space, facing right.
    /// Body, head, beak, and tail are four overlapping closed sub-paths whose
    /// non-zero-winding union is the duck shape.
    private static func duckSilhouette() -> NSBezierPath {
        let path = NSBezierPath()
        path.windingRule = .nonZero

        // Body — long horizontal oval sitting low in the frame.
        path.append(NSBezierPath(ovalIn: NSRect(x: 1, y: 3, width: 16, height: 8.5)))

        // Head — sinks into the front of the body to form one silhouette.
        path.append(NSBezierPath(ovalIn: NSRect(x: 10, y: 7.5, width: 9, height: 9)))

        // Beak — short bill leaving the front of the head.
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

        // Tail — small upturned bump at back-left.
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
}
