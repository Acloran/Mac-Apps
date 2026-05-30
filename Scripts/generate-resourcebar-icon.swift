import AppKit
import Foundation

struct IconSize {
    let filename: String
    let pixels: Int
}

let outputURL: URL
if CommandLine.arguments.count > 1 {
    outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    outputURL = URL(fileURLWithPath: "Resources/ResourceBar.iconset")
}

let sizes = [
    IconSize(filename: "icon_16x16.png", pixels: 16),
    IconSize(filename: "icon_16x16@2x.png", pixels: 32),
    IconSize(filename: "icon_32x32.png", pixels: 32),
    IconSize(filename: "icon_32x32@2x.png", pixels: 64),
    IconSize(filename: "icon_128x128.png", pixels: 128),
    IconSize(filename: "icon_128x128@2x.png", pixels: 256),
    IconSize(filename: "icon_256x256.png", pixels: 256),
    IconSize(filename: "icon_256x256@2x.png", pixels: 512),
    IconSize(filename: "icon_512x512.png", pixels: 512),
    IconSize(filename: "icon_512x512@2x.png", pixels: 1024)
]

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

for size in sizes {
    let image = drawIcon(size: CGFloat(size.pixels))
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Failed to render \(size.filename)")
    }

    try pngData.write(to: outputURL.appendingPathComponent(size.filename), options: .atomic)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true

        let scale = size / 1024
        let outer = rect.insetBy(dx: 44 * scale, dy: 44 * scale)
        let radius = 220 * scale

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
        shadow.shadowBlurRadius = 54 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -20 * scale)
        shadow.set()

        let outerPath = NSBezierPath(roundedRect: outer, xRadius: radius, yRadius: radius)
        let background = NSGradient(colors: [
            NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.12, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.21, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.06, alpha: 1)
        ])
        background?.draw(in: outerPath, angle: -38)

        NSGraphicsContext.saveGraphicsState()
        outerPath.addClip()
        drawSoftGlow(in: outer, scale: scale)
        NSGraphicsContext.restoreGraphicsState()

        shadow.shadowColor = .clear
        shadow.set()

        let stroke = NSBezierPath(roundedRect: outer.insetBy(dx: 9 * scale, dy: 9 * scale), xRadius: radius - 9 * scale, yRadius: radius - 9 * scale)
        NSColor.white.withAlphaComponent(0.16).setStroke()
        stroke.lineWidth = 5 * scale
        stroke.stroke()

        drawMenuStrip(in: outer, scale: scale)
        drawSignalMark(in: outer, scale: scale)
        drawMetricPips(in: outer, scale: scale)

        return true
    }

    image.isTemplate = false
    return image
}

func drawSoftGlow(in outer: NSRect, scale: CGFloat) {
    let cyanRect = NSRect(
        x: outer.minX - 90 * scale,
        y: outer.maxY - 390 * scale,
        width: 560 * scale,
        height: 420 * scale
    )
    NSGradient(colors: [
        NSColor.systemCyan.withAlphaComponent(0.34),
        NSColor.systemBlue.withAlphaComponent(0.03),
        NSColor.clear
    ])?.draw(in: NSBezierPath(ovalIn: cyanRect), angle: 0)

    let amberRect = NSRect(
        x: outer.maxX - 420 * scale,
        y: outer.minY - 110 * scale,
        width: 520 * scale,
        height: 430 * scale
    )
    NSGradient(colors: [
        NSColor.systemOrange.withAlphaComponent(0.28),
        NSColor.systemRed.withAlphaComponent(0.05),
        NSColor.clear
    ])?.draw(in: NSBezierPath(ovalIn: amberRect), angle: 0)
}

func drawMenuStrip(in outer: NSRect, scale: CGFloat) {
    let strip = NSRect(
        x: outer.minX + 112 * scale,
        y: outer.minY + 338 * scale,
        width: outer.width - 224 * scale,
        height: 310 * scale
    )
    let stripPath = NSBezierPath(roundedRect: strip, xRadius: 74 * scale, yRadius: 74 * scale)

    let stripShadow = NSShadow()
    stripShadow.shadowColor = NSColor.black.withAlphaComponent(0.36)
    stripShadow.shadowBlurRadius = 28 * scale
    stripShadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    stripShadow.set()

    NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.17, alpha: 0.94).setFill()
    stripPath.fill()

    stripShadow.shadowColor = .clear
    stripShadow.set()

    NSColor.white.withAlphaComponent(0.16).setStroke()
    stripPath.lineWidth = 3 * scale
    stripPath.stroke()

    drawRow(y: strip.maxY - 113 * scale, strip: strip, scale: scale, top: true)
    drawRow(y: strip.minY + 84 * scale, strip: strip, scale: scale, top: false)
}

func drawRow(y: CGFloat, strip: NSRect, scale: CGFloat, top: Bool) {
    let labelColor = NSColor.white.withAlphaComponent(0.54)
    let textColor = NSColor.white.withAlphaComponent(0.90)

    drawBlock(x: strip.minX + 56 * scale, y: y, width: 62 * scale, height: 28 * scale, color: labelColor, radius: 12 * scale)
    drawBlock(x: strip.minX + 134 * scale, y: y, width: top ? 108 * scale : 86 * scale, height: 32 * scale, color: textColor, radius: 14 * scale)

    drawBlock(x: strip.minX + 294 * scale, y: y, width: 50 * scale, height: 28 * scale, color: labelColor, radius: 12 * scale)
    drawBlock(x: strip.minX + 360 * scale, y: y, width: top ? 96 * scale : 122 * scale, height: 32 * scale, color: textColor, radius: 14 * scale)

    let accent = top ? NSColor.systemBlue : NSColor.systemRed
    drawBlock(x: strip.minX + 528 * scale, y: y, width: 30 * scale, height: 30 * scale, color: accent, radius: 13 * scale)
    drawBlock(x: strip.minX + 578 * scale, y: y, width: 112 * scale, height: 32 * scale, color: textColor.withAlphaComponent(0.82), radius: 14 * scale)
}

func drawSignalMark(in outer: NSRect, scale: CGFloat) {
    let origin = NSPoint(x: outer.minX + 194 * scale, y: outer.minY + 188 * scale)
    let barWidth = 42 * scale
    let gap = 21 * scale
    let heights: [CGFloat] = [62, 98, 142, 196, 252]
    let colors: [NSColor] = [.systemBlue, .systemCyan, .systemGreen, .systemOrange, .systemRed]

    for index in heights.indices {
        let height = heights[index] * scale
        let rect = NSRect(
            x: origin.x + CGFloat(index) * (barWidth + gap),
            y: origin.y,
            width: barWidth,
            height: height
        )
        drawBlock(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height, color: colors[index], radius: 18 * scale)
    }

    let line = NSBezierPath()
    let points = [
        NSPoint(x: outer.minX + 502 * scale, y: outer.minY + 220 * scale),
        NSPoint(x: outer.minX + 592 * scale, y: outer.minY + 298 * scale),
        NSPoint(x: outer.minX + 672 * scale, y: outer.minY + 268 * scale),
        NSPoint(x: outer.minX + 772 * scale, y: outer.minY + 398 * scale)
    ]
    line.move(to: points[0])
    for point in points.dropFirst() {
        line.line(to: point)
    }
    NSColor.systemCyan.withAlphaComponent(0.88).setStroke()
    line.lineWidth = 16 * scale
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    line.stroke()

    for point in points {
        drawBlock(
            x: point.x - 18 * scale,
            y: point.y - 18 * scale,
            width: 36 * scale,
            height: 36 * scale,
            color: .white.withAlphaComponent(0.94),
            radius: 18 * scale
        )
    }
}

func drawMetricPips(in outer: NSRect, scale: CGFloat) {
    let colors: [NSColor] = [.systemBlue, .systemGreen, .systemOrange]
    for index in 0..<3 {
        drawBlock(
            x: outer.maxX - 250 * scale + CGFloat(index) * 66 * scale,
            y: outer.maxY - 156 * scale,
            width: 38 * scale,
            height: 38 * scale,
            color: colors[index].withAlphaComponent(0.92),
            radius: 19 * scale
        )
    }
}

func drawBlock(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor, radius: CGFloat) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius).fill()
}
