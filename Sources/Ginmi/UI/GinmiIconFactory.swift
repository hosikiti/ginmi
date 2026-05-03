import AppKit

enum GinmiIconFactory {
    static func statusBarIcon() -> NSImage {
        if let image = resourceImage(named: "ginmi-tray-icon") {
            return statusBarTemplateImage(from: image)
        }

        let fallback = drawFanIcon(size: NSSize(width: 22, height: 22), strokeWidth: 1.9)
        fallback.isTemplate = true
        return fallback
    }

    static func appIcon() -> NSImage {
        resourceImage(named: "ginmi-icon")
            ?? drawFanIcon(size: NSSize(width: 256, height: 256), strokeWidth: 14)
    }

    private static func resourceImage(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func statusBarTemplateImage(from source: NSImage) -> NSImage {
        let targetSize = NSSize(width: 22, height: 22)
        guard
            let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let visibleRect = nonTransparentPixelBounds(in: cgImage)
        else {
            source.size = targetSize
            source.isTemplate = true
            return source
        }

        let image = NSImage(size: targetSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        NSGraphicsContext.current?.imageInterpolation = .high

        let fitScale = min(targetSize.width / visibleRect.width, targetSize.height / visibleRect.height)
        let drawSize = NSSize(width: visibleRect.width * fitScale, height: visibleRect.height * fitScale)
        let drawRect = NSRect(
            x: (targetSize.width - drawSize.width) * 0.5,
            y: (targetSize.height - drawSize.height) * 0.5,
            width: drawSize.width,
            height: drawSize.height
        )
        let sourceRect = NSRect(
            x: visibleRect.minX,
            y: CGFloat(cgImage.height) - visibleRect.maxY,
            width: visibleRect.width,
            height: visibleRect.height
        )

        source.draw(in: drawRect, from: sourceRect, operation: .sourceOver, fraction: 1)
        image.isTemplate = true
        return image
    }

    private static func nonTransparentPixelBounds(in image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[(y * bytesPerRow) + (x * bytesPerPixel) + 3]
                guard alpha > 8 else { continue }

                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard minX <= maxX, minY <= maxY else {
            return nil
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
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
