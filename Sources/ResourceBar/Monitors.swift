import CMetrics
import Darwin
import Foundation
import IOKit
import IOKit.ps

struct CPUSample {
    let busyTicks: Double
    let totalTicks: Double
}

struct MemoryPressureSnapshot {
    let pressurePercent: Int
    let freeLevelPercent: Int?

    var pressure: Double {
        Double(pressurePercent) / 100
    }
}

struct DiskCounters {
    let readBytes: UInt64
    let writtenBytes: UInt64
    let timestamp: Date
}

struct DiskSnapshot {
    let readBytesPerSecond: UInt64
    let writeBytesPerSecond: UInt64
}

struct ProcessorTemperatureSnapshot {
    let celsius: Double?
    let sensorCount: Int
}

struct BatterySnapshot {
    let secondsRemaining: TimeInterval?
    let isCharging: Bool
    let isOnAC: Bool
    let temperatureCelsius: Double?
    let virtualTemperatureCelsius: Double?
    let batteryPowerWatts: Double?
    let adapterInputWatts: Double?
    let adapterWatts: Double?
}

struct FanSnapshot {
    let rpms: [Double]

    var maxRPM: Double? {
        rpms.max()
    }
}

struct NetworkCounters {
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let timestamp: Date
}

struct NetworkSnapshot {
    let downBytesPerSecond: UInt64
    let upBytesPerSecond: UInt64

    var totalBytesPerSecond: UInt64 {
        downBytesPerSecond + upBytesPerSecond
    }
}

final class SystemMonitor {
    private var previousCPU: CPUSample?
    private var previousNetwork: NetworkCounters?
    private var previousDisk: DiskCounters?

    private let processorTemperatureKeys = [
        "TCMX", "TC0P", "TC0E",
        "TpxB", "Tpx9", "TpxC", "Tp2R", "Tp2G", "Te06", "Te05", "Te0S"
    ]

    func cpuUsage() -> Double {
        guard let current = readCPUSample() else {
            return 0
        }

        defer { previousCPU = current }

        guard let previousCPU else {
            return 0
        }

        let busyDelta = current.busyTicks - previousCPU.busyTicks
        let totalDelta = current.totalTicks - previousCPU.totalTicks

        guard totalDelta > 0 else {
            return 0
        }

        return max(0, min(1, busyDelta / totalDelta))
    }

    func memoryPressureSnapshot() -> MemoryPressureSnapshot {
        let freeLevel = Int(ResourceBarMemoryFreeLevel())
        if freeLevel >= 0 {
            return MemoryPressureSnapshot(
                pressurePercent: max(0, min(100, 100 - freeLevel)),
                freeLevelPercent: freeLevel
            )
        }

        return fallbackMemoryPressureSnapshot()
    }

    func diskSnapshot() -> DiskSnapshot {
        let current = readDiskCounters()
        defer { previousDisk = current }

        guard let previousDisk else {
            return DiskSnapshot(readBytesPerSecond: 0, writeBytesPerSecond: 0)
        }

        let elapsed = current.timestamp.timeIntervalSince(previousDisk.timestamp)
        guard elapsed > 0 else {
            return DiskSnapshot(readBytesPerSecond: 0, writeBytesPerSecond: 0)
        }

        let readDelta = current.readBytes >= previousDisk.readBytes
            ? current.readBytes - previousDisk.readBytes
            : 0
        let writeDelta = current.writtenBytes >= previousDisk.writtenBytes
            ? current.writtenBytes - previousDisk.writtenBytes
            : 0

        return DiskSnapshot(
            readBytesPerSecond: UInt64(Double(readDelta) / elapsed),
            writeBytesPerSecond: UInt64(Double(writeDelta) / elapsed)
        )
    }

    func fanSnapshot() -> FanSnapshot {
        let count = Int(ResourceBarFanCount())
        guard count > 0 else {
            return FanSnapshot(rpms: [])
        }

        let rpms = (0..<min(count, 8)).compactMap { index -> Double? in
            let rpm = ResourceBarFanRPM(Int32(index))
            return rpm >= 0 ? rpm : nil
        }

        return FanSnapshot(rpms: rpms)
    }

    func processorTemperatureSnapshot() -> ProcessorTemperatureSnapshot {
        var temperatures: [Double] = []

        for key in processorTemperatureKeys {
            let celsius = key.withCString { ResourceBarSMCTemperature($0) }
            if celsius > 0, celsius < 125 {
                temperatures.append(celsius)
            }
        }

        return ProcessorTemperatureSnapshot(celsius: temperatures.max(), sensorCount: temperatures.count)
    }

    func batterySnapshot() -> BatterySnapshot {
        var isCharging = false
        var isOnAC = false
        var reportedSecondsRemaining: TimeInterval?

        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                    continue
                }

                isCharging = isCharging || boolValue(description["Is Charging"])
                if let state = description["Power Source State"] as? String {
                    isOnAC = isOnAC || state == "AC Power"
                }

                if reportedSecondsRemaining == nil,
                   let minutes = intValue(description["Time to Empty"]),
                   minutes > 0,
                   minutes < 65535 {
                    reportedSecondsRemaining = TimeInterval(minutes * 60)
                }
            }
        }

        let rawEstimate = IOPSGetTimeRemainingEstimate()
        let secondsRemaining: TimeInterval?
        if let reportedSecondsRemaining {
            secondsRemaining = reportedSecondsRemaining
        } else if rawEstimate > 0 {
            secondsRemaining = rawEstimate
        } else {
            secondsRemaining = nil
        }

        let hardware = batteryHardwareSnapshot()
        return BatterySnapshot(
            secondsRemaining: secondsRemaining,
            isCharging: isCharging,
            isOnAC: isOnAC,
            temperatureCelsius: hardware.physicalTemperature,
            virtualTemperatureCelsius: hardware.virtualTemperature,
            batteryPowerWatts: hardware.batteryPowerWatts,
            adapterInputWatts: hardware.adapterInputWatts,
            adapterWatts: hardware.adapterWatts
        )
    }

    private func fallbackMemoryPressureSnapshot() -> MemoryPressureSnapshot {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryPressureSnapshot(pressurePercent: 0, freeLevelPercent: nil)
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let bytesPerPage = UInt64(pageSize)

        let appBackedPages = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let usedBytes = appBackedPages * bytesPerPage
        let pressure = Double(min(usedBytes, ProcessInfo.processInfo.physicalMemory)) / Double(ProcessInfo.processInfo.physicalMemory)

        return MemoryPressureSnapshot(pressurePercent: Int((pressure * 100).rounded()), freeLevelPercent: nil)
    }

    func networkSnapshot() -> NetworkSnapshot {
        let current = readNetworkCounters()
        defer { previousNetwork = current }

        guard let previousNetwork else {
            return NetworkSnapshot(downBytesPerSecond: 0, upBytesPerSecond: 0)
        }

        let elapsed = current.timestamp.timeIntervalSince(previousNetwork.timestamp)
        guard elapsed > 0 else {
            return NetworkSnapshot(downBytesPerSecond: 0, upBytesPerSecond: 0)
        }

        let receivedDelta = current.receivedBytes >= previousNetwork.receivedBytes
            ? current.receivedBytes - previousNetwork.receivedBytes
            : 0
        let sentDelta = current.sentBytes >= previousNetwork.sentBytes
            ? current.sentBytes - previousNetwork.sentBytes
            : 0

        return NetworkSnapshot(
            downBytesPerSecond: UInt64(Double(receivedDelta) / elapsed),
            upBytesPerSecond: UInt64(Double(sentDelta) / elapsed)
        )
    }

    private func readCPUSample() -> CPUSample? {
        var load = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let user = Double(load.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3)
        let total = user + system + idle + nice

        return CPUSample(busyTicks: total - idle, totalTicks: total)
    }

    private func readNetworkCounters() -> NetworkCounters {
        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaceAddresses) == 0, let firstAddress = interfaceAddresses else {
            return NetworkCounters(receivedBytes: 0, sentBytes: 0, timestamp: Date())
        }

        defer { freeifaddrs(interfaceAddresses) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            let interface = current.pointee
            guard let address = interface.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard isInternetFacingInterface(name) else {
                continue
            }

            guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else {
                continue
            }

            receivedBytes += UInt64(data.ifi_ibytes)
            sentBytes += UInt64(data.ifi_obytes)
        }

        return NetworkCounters(receivedBytes: receivedBytes, sentBytes: sentBytes, timestamp: Date())
    }

    private func readDiskCounters() -> DiskCounters {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
        guard result == KERN_SUCCESS else {
            return DiskCounters(readBytes: 0, writtenBytes: 0, timestamp: Date())
        }

        defer { IOObjectRelease(iterator) }

        var bestReadBytes: UInt64 = 0
        var bestWrittenBytes: UInt64 = 0
        var bestTotalBytes: UInt64 = 0

        while true {
            let service = IOIteratorNext(iterator)
            if service == IO_OBJECT_NULL {
                break
            }

            defer { IOObjectRelease(service) }

            guard
                let unmanagedStats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0),
                let stats = unmanagedStats.takeRetainedValue() as? [String: Any],
                let readBytes = uint64Value(stats["Bytes (Read)"]),
                let writtenBytes = uint64Value(stats["Bytes (Write)"])
            else {
                continue
            }

            let totalBytes = readBytes + writtenBytes
            if totalBytes > bestTotalBytes {
                bestReadBytes = readBytes
                bestWrittenBytes = writtenBytes
                bestTotalBytes = totalBytes
            }
        }

        return DiskCounters(readBytes: bestReadBytes, writtenBytes: bestWrittenBytes, timestamp: Date())
    }

    private func batteryHardwareSnapshot() -> (physicalTemperature: Double?, virtualTemperature: Double?, batteryPowerWatts: Double?, adapterInputWatts: Double?, adapterWatts: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return (nil, nil, nil, nil, nil)
        }

        defer { IOObjectRelease(service) }

        return (
            physicalTemperature: batteryTemperature(service: service, key: "Temperature"),
            virtualTemperature: batteryVirtualTemperature(service: service),
            batteryPowerWatts: batteryPowerWatts(service: service),
            adapterInputWatts: adapterInputWatts(service: service),
            adapterWatts: adapterWatts(service: service)
        )
    }

    private func batteryTemperature(service: io_object_t, key: String) -> Double? {
        guard let number = registryProperty(service: service, key: key) as? NSNumber else {
            return nil
        }

        return number.doubleValue / 10 - 273.15
    }

    private func batteryVirtualTemperature(service: io_object_t) -> Double? {
        guard let number = registryProperty(service: service, key: "VirtualTemperature") as? NSNumber else {
            return nil
        }

        let celsius = number.doubleValue / 100
        guard celsius > -40, celsius < 125 else {
            return nil
        }

        return celsius
    }

    private func batteryPowerWatts(service: io_object_t) -> Double? {
        if let telemetry = registryProperty(service: service, key: "PowerTelemetryData") as? [String: Any],
           let milliwatts = signedDoubleValue(telemetry["BatteryPower"]),
           abs(milliwatts) > 0 {
            // PowerTelemetryData uses the battery's perspective: negative while charging,
            // positive while discharging. ResourceBar exposes positive as watts into
            // the battery and negative as watts out of it.
            return -milliwatts / 1000
        }

        let voltageMillivolts = doubleValue(registryProperty(service: service, key: "Voltage"))
            ?? doubleValue(registryProperty(service: service, key: "AppleRawBatteryVoltage"))
        let amperageMilliamps = signedDoubleValue(registryProperty(service: service, key: "InstantAmperage"))
            ?? signedDoubleValue(registryProperty(service: service, key: "Amperage"))

        guard
            let voltageMillivolts,
            let amperageMilliamps,
            voltageMillivolts > 0,
            abs(amperageMilliamps) > 0
        else {
            return nil
        }

        return voltageMillivolts * amperageMilliamps / 1_000_000
    }

    private func adapterInputWatts(service: io_object_t) -> Double? {
        guard let telemetry = registryProperty(service: service, key: "PowerTelemetryData") as? [String: Any] else {
            return nil
        }

        if let milliwatts = signedDoubleValue(telemetry["SystemPowerIn"]), milliwatts >= 0 {
            return milliwatts / 1000
        }

        guard
            let voltageMillivolts = signedDoubleValue(telemetry["SystemVoltageIn"]),
            let currentMilliamps = signedDoubleValue(telemetry["SystemCurrentIn"]),
            voltageMillivolts >= 0,
            currentMilliamps >= 0
        else {
            return nil
        }

        return voltageMillivolts * currentMilliamps / 1_000_000
    }

    private func adapterWatts(service: io_object_t) -> Double? {
        if let details = registryProperty(service: service, key: "AdapterDetails") as? [String: Any],
           let watts = watts(fromAdapterDetails: details) {
            return watts
        }

        if let rawDetails = registryProperty(service: service, key: "AppleRawAdapterDetails") as? [[String: Any]] {
            for details in rawDetails {
                if let watts = watts(fromAdapterDetails: details) {
                    return watts
                }
            }
        }

        return nil
    }

    private func watts(fromAdapterDetails details: [String: Any]) -> Double? {
        if let watts = doubleValue(details["Watts"]), watts > 0 {
            return watts
        }

        guard
            let voltageMillivolts = doubleValue(details["AdapterVoltage"]),
            let currentMilliamps = doubleValue(details["Current"]),
            voltageMillivolts > 0,
            currentMilliamps > 0
        else {
            return nil
        }

        return voltageMillivolts * currentMilliamps / 1_000_000
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }

        return value as? Int
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let number = value as? NSNumber {
            return number.boolValue
        }

        return (value as? Bool) ?? false
    }

    private func uint64Value(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }

        return value as? UInt64
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let value = value as? Double {
            return value
        }

        if let value = value as? Int {
            return Double(value)
        }

        if let value = value as? UInt64 {
            return Double(value)
        }

        return nil
    }

    private func signedDoubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            let unsignedValue = number.uint64Value
            if unsignedValue > UInt64(Int64.max) {
                return Double(Int64(bitPattern: unsignedValue))
            }

            return number.doubleValue
        }

        if let value = value as? UInt64 {
            return Double(Int64(bitPattern: value))
        }

        if let value = value as? Int64 {
            return Double(value)
        }

        if let value = value as? Int {
            return Double(value)
        }

        if let value = value as? Double {
            return value
        }

        return nil
    }

    private func registryProperty(service: io_object_t, key: String) -> Any? {
        guard let unmanagedValue = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }

        return unmanagedValue.takeRetainedValue()
    }

    private func isInternetFacingInterface(_ name: String) -> Bool {
        let ignoredPrefixes = [
            "awdl",
            "bridge",
            "gif",
            "llw",
            "lo",
            "p2p",
            "stf",
            "utun"
        ]

        return !ignoredPrefixes.contains { name.hasPrefix($0) }
    }
}
