import Foundation

enum MetricFormatter {
    static func percent(_ ratio: Double) -> String {
        let value = max(0, min(999, Int((ratio * 100).rounded())))
        return "\(value)%"
    }

    static func fixedPercent(_ ratio: Double) -> String {
        let value = max(0, min(999, Int((ratio * 100).rounded())))
        return String(format: "%3d%%", value)
    }

    static func fixedPercent(_ value: Int) -> String {
        String(format: "%3d%%", max(0, min(999, value)))
    }

    static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = Double(value)
        var unitIndex = 0

        while amount >= 1024, unitIndex < units.count - 1 {
            amount /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(amount)) \(units[unitIndex])"
        }

        if amount >= 10 {
            return "\(Int(amount.rounded())) \(units[unitIndex])"
        }

        return String(format: "%.1f %@", amount, units[unitIndex])
    }

    static func rate(_ bytesPerSecond: UInt64) -> String {
        "\(bytes(bytesPerSecond))/s"
    }

    static func fixedMegabytesPerSecond(_ bytesPerSecond: UInt64) -> String {
        let megabytes = Double(bytesPerSecond) / 1_048_576

        if megabytes >= 100 {
            return String(format: "%4.0f", min(megabytes, 9999))
        }

        return String(format: "%4.1f", megabytes)
    }

    static func compactMegabytesPerSecond(_ bytesPerSecond: UInt64) -> String {
        let megabytes = Double(bytesPerSecond) / 1_048_576

        if megabytes >= 100 {
            return String(format: "%3.0fMB/s", min(megabytes, 999))
        }

        return String(format: "%3.1fMB/s", megabytes)
    }

    static func compactRPM(_ rpm: Double?) -> String {
        guard let rpm, rpm >= 0 else {
            return "---RPM"
        }

        if rpm >= 10_000 {
            return String(format: "%2.0fkRPM", rpm / 1000)
        }

        if rpm >= 1000 {
            return String(format: "%3.1fkRPM", rpm / 1000)
        }

        return String(format: "%3.0fRPM", rpm)
    }

    static func watts(_ watts: Double) -> String {
        if watts >= 10 {
            return String(format: "%.0f W", watts)
        }

        if watts >= 1 {
            return String(format: "%.1f W", watts)
        }

        return String(format: "%.2f W", watts)
    }

    static func compactMinutes(_ seconds: TimeInterval?) -> String {
        guard let seconds else {
            return "  -- "
        }

        let minutes = max(0, Int((seconds / 60).rounded()))
        let hours = min(minutes / 60, 99)
        let remainingMinutes = minutes % 60
        return String(format: "%2d:%02d", hours, remainingMinutes)
    }

    static func temperature(_ celsius: Double?) -> String {
        guard let celsius else {
            return "--C"
        }

        return String(format: "%2.0fC", celsius)
    }
}
