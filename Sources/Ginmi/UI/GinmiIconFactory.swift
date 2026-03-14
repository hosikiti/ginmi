import AppKit

enum GinmiIconFactory {
    static func statusBarIcon() -> NSImage {
        let image = drawFanIcon(size: NSSize(width: 22, height: 22), strokeWidth: 1.9)
        image.isTemplate = true
        return image
    }

    static func appIcon() -> NSImage {
        drawFanIcon(size: NSSize(width: 256, height: 256), strokeWidth: 14)
    }

    private static func drawFanIcon(size: NSSize, strokeWidth: CGFloat) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.setAllowsAntialiasing(true)
        ctx?.setShouldAntialias(true)

        let color = NSColor.labelColor
        color.setStroke()
        color.setFill()

        let w = size.width
        let h = size.height
        let verticalOffset = size.width <= 24 ? 3.0 : 3.0 * (size.height / 22.0)
        let pivot = CGPoint(x: w * 0.5, y: h * 0.19 + verticalOffset)
        let radius = min(w, h) * 0.43
        let startAngle: CGFloat = 14
        let endAngle: CGFloat = 142
        let tiltRadians: CGFloat = -.pi / 18

        let outerArc = NSBezierPath()
        outerArc.lineWidth = strokeWidth * 0.95
        outerArc.lineCapStyle = .round
        var transform = AffineTransform(
            translationByX: pivot.x,
            byY: pivot.y
        )
        transform.rotate(byRadians: tiltRadians)
        transform.translate(x: -pivot.x, y: -pivot.y)

        outerArc.appendArc(withCenter: pivot, radius: radius, startAngle: startAngle, endAngle: endAngle)
        outerArc.transform(using: transform)
        outerArc.stroke()

        // Slightly uneven ribs feel more hand-held than perfectly radial geometry.
        let ribAngles: [CGFloat] = [28, 68, 106, 136]
        let ribLengths: [CGFloat] = [0.88, 0.96, 0.9, 0.8]
        for (index, angleDegrees) in ribAngles.enumerated() {
            let angle = angleDegrees * .pi / 180
            let end = CGPoint(
                x: pivot.x + cos(angle) * radius * ribLengths[index],
                y: pivot.y + sin(angle) * radius * ribLengths[index]
            )
            let rib = NSBezierPath()
            rib.lineWidth = strokeWidth * (index == 1 ? 0.92 : 0.8)
            rib.lineCapStyle = .round
            rib.move(to: pivot)
            rib.line(to: end)
            rib.transform(using: transform)
            rib.stroke()
        }

        let pivotDotSize = strokeWidth * 1.2
        let pivotDotRect = CGRect(
            x: pivot.x - pivotDotSize * 0.5,
            y: pivot.y - pivotDotSize * 0.5,
            width: pivotDotSize,
            height: pivotDotSize
        )
        let pivotDot = NSBezierPath(ovalIn: pivotDotRect)
        pivotDot.transform(using: transform)
        pivotDot.fill()

        let stem = NSBezierPath()
        stem.lineWidth = strokeWidth * 0.8
        stem.lineCapStyle = .round
        stem.move(to: CGPoint(x: pivot.x + strokeWidth * 0.08, y: pivot.y - pivotDotSize * 0.18))
        stem.line(to: CGPoint(x: pivot.x + radius * 0.1, y: pivot.y - radius * 0.24))
        stem.transform(using: transform)
        stem.stroke()

        return image
    }
}
