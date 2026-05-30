import AppKit

enum DisplayMode: String, CaseIterable {
    case full
    case reduced
    case tiny

    var title: String {
        switch self {
        case .full:
            return "Full"
        case .reduced:
            return "Reduced"
        case .tiny:
            return "Tiny"
        }
    }
}

struct StatusStripSnapshot {
    let cpuUsage: Double
    let processorTemperature: ProcessorTemperatureSnapshot
    let memoryPressure: MemoryPressureSnapshot
    let battery: BatterySnapshot
    let disk: DiskSnapshot
    let network: NetworkSnapshot
}

enum StatusStripRenderer {
    static let height: CGFloat = 24

    static func width(for mode: DisplayMode) -> CGFloat {
        switch mode {
        case .full:
            return 224
        case .reduced:
            return 105
        case .tiny:
            return 52
        }
    }

    static func image(for snapshot: StatusStripSnapshot, mode: DisplayMode, appearance: NSAppearance) -> NSImage {
        let size = NSSize(width: width(for: mode), height: height)
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = dark ? NSColor.white.withAlphaComponent(0.94) : NSColor.black.withAlphaComponent(0.84)
        let secondaryColor = dark ? NSColor.white.withAlphaComponent(0.62) : NSColor.black.withAlphaComponent(0.58)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.4, weight: .semibold)
        let labelFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)

        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            switch mode {
            case .full:
                drawFull(snapshot, font: font, labelFont: labelFont, textColor: textColor, secondaryColor: secondaryColor)
            case .reduced:
                drawReduced(snapshot, font: font, labelFont: labelFont, textColor: textColor, secondaryColor: secondaryColor)
            case .tiny:
                drawTiny(snapshot, font: font, labelFont: labelFont, textColor: textColor, secondaryColor: secondaryColor)
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    private static func drawFull(_ snapshot: StatusStripSnapshot, font: NSFont, labelFont: NSFont, textColor: NSColor, secondaryColor: NSColor) {
        drawReduced(snapshot, font: font, labelFont: labelFont, textColor: textColor, secondaryColor: secondaryColor)

        draw("D", x: 106, y: 13, font: labelFont, color: .systemBlue)
        draw(MetricFormatter.compactMegabytesPerSecond(snapshot.network.downBytesPerSecond), x: 118, y: 12, font: font, color: textColor)
        draw("U", x: 106, y: 2, font: labelFont, color: .systemRed)
        draw(MetricFormatter.compactMegabytesPerSecond(snapshot.network.upBytesPerSecond), x: 118, y: 1, font: font, color: textColor)

        draw("R", x: 164, y: 13, font: labelFont, color: .systemGreen)
        draw(MetricFormatter.compactMegabytesPerSecond(snapshot.disk.readBytesPerSecond), x: 176, y: 12, font: font, color: textColor)
        draw("W", x: 164, y: 2, font: labelFont, color: .systemOrange)
        draw(MetricFormatter.compactMegabytesPerSecond(snapshot.disk.writeBytesPerSecond), x: 176, y: 1, font: font, color: textColor)
    }

    private static func drawReduced(_ snapshot: StatusStripSnapshot, font: NSFont, labelFont: NSFont, textColor: NSColor, secondaryColor: NSColor) {
        draw("CPU", x: 0, y: 13, font: labelFont, color: secondaryColor)
        draw(MetricFormatter.fixedPercent(snapshot.cpuUsage), x: 21, y: 12, font: font, color: percentColor(snapshot.cpuUsage, warning: 0.75, critical: 0.9, fallback: textColor))
        draw(MetricFormatter.temperature(snapshot.processorTemperature.celsius), x: 21, y: 1, font: font, color: processorTemperatureColor(snapshot.processorTemperature.celsius, fallback: textColor))

        draw("MP", x: 47, y: 13, font: labelFont, color: secondaryColor)
        draw(MetricFormatter.fixedPercent(snapshot.memoryPressure.pressurePercent), x: 72, y: 12, font: font, color: percentColor(snapshot.memoryPressure.pressure, warning: 0.7, critical: 0.9, fallback: textColor))

        draw("BAT", x: 47, y: 2, font: labelFont, color: secondaryColor)
        draw(batteryTime(snapshot.battery), x: 72, y: 1, font: font, color: textColor)
    }

    private static func drawTiny(_ snapshot: StatusStripSnapshot, font: NSFont, labelFont: NSFont, textColor: NSColor, secondaryColor: NSColor) {
        draw("CPU", x: 0, y: 13, font: labelFont, color: secondaryColor)
        draw(MetricFormatter.fixedPercent(snapshot.cpuUsage), x: 24, y: 12, font: font, color: percentColor(snapshot.cpuUsage, warning: 0.75, critical: 0.9, fallback: textColor))

        draw("MP", x: 0, y: 2, font: labelFont, color: secondaryColor)
        draw(MetricFormatter.fixedPercent(snapshot.memoryPressure.pressurePercent), x: 24, y: 1, font: font, color: percentColor(snapshot.memoryPressure.pressure, warning: 0.7, critical: 0.9, fallback: textColor))
    }

    private static func draw(_ text: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        text.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }

    private static func batteryTime(_ battery: BatterySnapshot) -> String {
        if battery.isOnAC, let watts = battery.batteryPowerWatts, watts < -0.25 {
            return " OUT "
        }

        if battery.isCharging {
            return " CHG "
        }

        if battery.isOnAC, battery.secondsRemaining == nil {
            return "  AC "
        }

        return MetricFormatter.compactMinutes(battery.secondsRemaining)
    }

    private static func percentColor(_ ratio: Double, warning: Double, critical: Double, fallback: NSColor) -> NSColor {
        if ratio >= critical {
            return .systemRed
        }

        if ratio >= warning {
            return .systemOrange
        }

        return fallback
    }

    private static func processorTemperatureColor(_ celsius: Double?, fallback: NSColor) -> NSColor {
        guard let celsius else {
            return fallback
        }

        if celsius >= 95 {
            return .systemRed
        }

        if celsius >= 80 {
            return .systemOrange
        }

        return fallback
    }
}
