import AppKit
import CoreGraphics
import Foundation

struct DisplaySnapshot {
    let id: CGDirectDisplayID
    let key: String
    let name: String
    let isBuiltin: Bool
    let frame: CGRect
    let scale: CGFloat
    let edrHeadroom: Double
    let currentMode: DisplayModeSnapshot?
    let modes: [DisplayModeSnapshot]
    let brightness: Double?
}

struct DisplayModeSnapshot {
    let mode: CGDisplayMode
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let ioFlags: UInt32
    let ioModeID: Int32
    let pixelEncoding: String?
    let colorOutput: ColorOutputSnapshot

    var isHiDPI: Bool {
        pixelWidth > width || pixelHeight > height
    }

    var identity: String {
        [
            "\(ioModeID)",
            "\(width)",
            "\(height)",
            "\(pixelWidth)",
            "\(pixelHeight)",
            "\(Int(refreshRate.rounded()))",
            "\(ioFlags)",
            pixelEncoding ?? ""
        ].joined(separator: ":")
    }

    var resolutionTitle: String {
        var parts = ["\(width) x \(height)"]

        if isHiDPI {
            parts.append("HiDPI")
        }

        if refreshRate >= 1 {
            parts.append("@ \(Int(refreshRate.rounded())) Hz")
        }

        if pixelWidth != width || pixelHeight != height {
            parts.append("(\(pixelWidth) x \(pixelHeight))")
        }

        return parts.joined(separator: " ")
    }

    var title: String {
        "\(colorOutput.title) - \(resolutionTitle)"
    }
}

struct ColorOutputSnapshot {
    let model: String
    let bitDepth: Int?
    let sampling: String?
    let rawEncoding: String?

    var title: String {
        var parts = [model]

        if let bitDepth {
            parts.append("\(bitDepth) bpc")
        }

        if let sampling {
            parts.append(sampling)
        }

        return parts.joined(separator: " ")
    }

    var detail: String {
        guard let rawEncoding, !rawEncoding.isEmpty else {
            return title
        }

        return "\(title) (\(rawEncoding))"
    }

    static func parse(_ rawEncoding: String?) -> ColorOutputSnapshot {
        guard let rawEncoding, !rawEncoding.isEmpty else {
            return ColorOutputSnapshot(model: "Unknown", bitDepth: nil, sampling: nil, rawEncoding: nil)
        }

        let uppercased = rawEncoding.uppercased()
        let model: String

        if uppercased.contains("YCBCR") || uppercased.contains("YUV") || uppercased.contains("CBCR") {
            model = "YCbCr"
        } else if uppercased.contains("RGB") || uppercased.contains("DIRECTPIXELS") || rawEncoding.contains("R") || rawEncoding.contains("G") || rawEncoding.contains("B") {
            model = "RGB"
        } else {
            model = "Unknown"
        }

        let sampling: String?
        if uppercased.contains("444") {
            sampling = "4:4:4"
        } else if uppercased.contains("422") {
            sampling = "4:2:2"
        } else if uppercased.contains("420") {
            sampling = "4:2:0"
        } else {
            sampling = nil
        }

        let bitDepth = Self.bitDepth(from: rawEncoding, model: model)
        return ColorOutputSnapshot(model: model, bitDepth: bitDepth, sampling: sampling, rawEncoding: rawEncoding)
    }

    private static func bitDepth(from rawEncoding: String, model: String) -> Int? {
        if model == "RGB" {
            let redBits = rawEncoding.filter { $0 == "R" }.count
            let greenBits = rawEncoding.filter { $0 == "G" }.count
            let blueBits = rawEncoding.filter { $0 == "B" }.count
            let componentBits = [redBits, greenBits, blueBits].filter { $0 > 0 }

            if let minimum = componentBits.min(), minimum > 0 {
                return minimum
            }
        }

        let lowercased = rawEncoding.lowercased()
        let patterns: [(String, Int)] = [
            ("64bit", 16), ("64-bit", 16),
            ("32bit", 8), ("32-bit", 8),
            ("30bit", 10), ("30-bit", 10),
            ("24bit", 8), ("24-bit", 8),
            ("12bit", 12), ("12-bit", 12), ("12 bpc", 12),
            ("10bit", 10), ("10-bit", 10), ("10 bpc", 10),
            ("8bit", 8), ("8-bit", 8), ("8 bpc", 8)
        ]

        for (pattern, value) in patterns where lowercased.contains(pattern) {
            return value
        }

        return nil
    }
}

struct DDCControl {
    let title: String
    let code: UInt8
    let defaultMaximum: UInt16

    static let brightness = DDCControl(title: "Monitor Brightness", code: 0x10, defaultMaximum: 100)
}

struct DDCValue {
    let current: UInt16
    let maximum: UInt16

    var normalized: Double {
        guard maximum > 0 else {
            return 0
        }

        return Double(current) / Double(maximum)
    }
}

final class ModeAction: NSObject {
    let displayID: CGDirectDisplayID
    let mode: CGDisplayMode

    init(displayID: CGDirectDisplayID, mode: CGDisplayMode) {
        self.displayID = displayID
        self.mode = mode
    }
}

final class DisplayAction: NSObject {
    let displayID: CGDirectDisplayID

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }
}
