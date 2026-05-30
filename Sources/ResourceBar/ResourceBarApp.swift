import AppKit

private enum RefreshPreset: String, CaseIterable {
    case efficient
    case balanced
    case fast

    var title: String {
        switch self {
        case .efficient:
            return "Efficient"
        case .balanced:
            return "Balanced"
        case .fast:
            return "Fast"
        }
    }

    var fastInterval: TimeInterval {
        switch self {
        case .efficient:
            return 5
        case .balanced:
            return 2
        case .fast:
            return 1
        }
    }

    var slowInterval: TimeInterval {
        switch self {
        case .efficient:
            return 20
        case .balanced:
            return 10
        case .fast:
            return 5
        }
    }

    var detail: String {
        "live \(Int(fastInterval))s, slow \(Int(slowInterval))s"
    }
}

final class ResourceBarApp: NSObject, NSApplicationDelegate {
    private static let refreshPresetKey = "refreshPreset"
    private static let displayModeKey = "displayMode"

    private let monitor = SystemMonitor()
    private let statusBar = NSStatusBar.system

    private lazy var statusItem = makeStatusItem()

    private let cpuMenuItem = NSMenuItem(title: "CPU Usage: --", action: nil, keyEquivalent: "")
    private let memoryMenuItem = NSMenuItem(title: "Memory Pressure: --", action: nil, keyEquivalent: "")
    private let batteryMenuItem = NSMenuItem(title: "Battery Time: --", action: nil, keyEquivalent: "")
    private let batteryPowerMenuItem = NSMenuItem(title: "Battery Power: --", action: nil, keyEquivalent: "")
    private let adapterInputMenuItem = NSMenuItem(title: "Adapter Input: --", action: nil, keyEquivalent: "")
    private let temperatureMenuItem = NSMenuItem(title: "Temperature: CPU --", action: nil, keyEquivalent: "")
    private let networkDownMenuItem = NSMenuItem(title: "Network Down: --", action: nil, keyEquivalent: "")
    private let networkUpMenuItem = NSMenuItem(title: "Network Up: --", action: nil, keyEquivalent: "")
    private let diskReadMenuItem = NSMenuItem(title: "SSD Read: --", action: nil, keyEquivalent: "")
    private let diskWriteMenuItem = NSMenuItem(title: "SSD Write: --", action: nil, keyEquivalent: "")
    private let fanMenuItem = NSMenuItem(title: "Fan: --", action: nil, keyEquivalent: "")
    private let displayModeMenu = NSMenu()
    private let refreshSpeedMenu = NSMenu()

    private var refreshTimer: Timer?
    private var displayMode = DisplayMode(
        rawValue: UserDefaults.standard.string(forKey: ResourceBarApp.displayModeKey) ?? ""
    ) ?? .full
    private var refreshPreset = RefreshPreset(
        rawValue: UserDefaults.standard.string(forKey: ResourceBarApp.refreshPresetKey) ?? ""
    ) ?? .balanced
    private var lastSlowRefresh = Date.distantPast
    private var cachedMemory = MemoryPressureSnapshot(pressurePercent: 0, freeLevelPercent: nil)
    private var cachedProcessorTemperature = ProcessorTemperatureSnapshot(celsius: nil, sensorCount: 0)
    private var cachedBattery = BatterySnapshot(
        secondsRemaining: nil,
        isCharging: false,
        isOnAC: false,
        temperatureCelsius: nil,
        virtualTemperatureCelsius: nil,
        batteryPowerWatts: nil,
        adapterInputWatts: nil,
        adapterWatts: nil
    )
    private var cachedFan = FanSnapshot(rpms: [])

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem.menu = makeMenu()

        updateMetrics(forceSlowRefresh: true)
        restartTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    @objc private func refreshFromTimer() {
        updateMetrics(forceSlowRefresh: false)
    }

    @objc private func refreshNow() {
        updateMetrics(forceSlowRefresh: true)
    }

    private func updateMetrics(forceSlowRefresh: Bool) {
        let cpuUsage = monitor.cpuUsage()
        let network = monitor.networkSnapshot()
        let disk = monitor.diskSnapshot()
        refreshSlowMetrics(force: forceSlowRefresh)

        let snapshot = StatusStripSnapshot(
            cpuUsage: cpuUsage,
            processorTemperature: cachedProcessorTemperature,
            memoryPressure: cachedMemory,
            battery: cachedBattery,
            disk: disk,
            network: network
        )

        if let button = statusItem.button {
            button.image = StatusStripRenderer.image(for: snapshot, mode: displayMode, appearance: button.effectiveAppearance)
        }

        cpuMenuItem.title = "CPU Usage: \(MetricFormatter.percent(cpuUsage))"
        memoryMenuItem.title = memoryDetail(cachedMemory)
        batteryMenuItem.title = batteryDetail(cachedBattery)
        batteryPowerMenuItem.title = batteryPowerDetail(cachedBattery)
        adapterInputMenuItem.title = adapterInputDetail(cachedBattery)
        temperatureMenuItem.title = temperatureDetail(cachedProcessorTemperature, battery: cachedBattery)
        networkDownMenuItem.title = "Network Down: \(MetricFormatter.compactMegabytesPerSecond(network.downBytesPerSecond))"
        networkUpMenuItem.title = "Network Up: \(MetricFormatter.compactMegabytesPerSecond(network.upBytesPerSecond))"
        diskReadMenuItem.title = "SSD Read: \(MetricFormatter.compactMegabytesPerSecond(disk.readBytesPerSecond))"
        diskWriteMenuItem.title = "SSD Write: \(MetricFormatter.compactMegabytesPerSecond(disk.writeBytesPerSecond))"
        fanMenuItem.title = fanDetail(cachedFan)

        statusItem.button?.toolTip = [
            cpuMenuItem.title,
            memoryMenuItem.title,
            batteryMenuItem.title,
            batteryPowerMenuItem.title,
            adapterInputMenuItem.title,
            temperatureMenuItem.title,
            networkDownMenuItem.title,
            networkUpMenuItem.title,
            diskReadMenuItem.title,
            diskWriteMenuItem.title,
            fanMenuItem.title
        ].joined(separator: "\n")
    }

    private func refreshSlowMetrics(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSlowRefresh) >= refreshPreset.slowInterval else {
            return
        }

        cachedMemory = monitor.memoryPressureSnapshot()
        cachedProcessorTemperature = monitor.processorTemperatureSnapshot()
        cachedBattery = monitor.batterySnapshot()
        cachedFan = monitor.fanSnapshot()
        lastSlowRefresh = now
    }

    private func restartTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: refreshPreset.fastInterval,
            target: self,
            selector: #selector(refreshFromTimer),
            userInfo: nil,
            repeats: true
        )
        refreshTimer?.tolerance = max(0.2, refreshPreset.fastInterval * 0.25)
    }

    @objc private func setRefreshSpeed(_ sender: NSMenuItem) {
        guard
            let rawPreset = sender.representedObject as? String,
            let preset = RefreshPreset(rawValue: rawPreset)
        else {
            return
        }

        refreshPreset = preset
        UserDefaults.standard.set(preset.rawValue, forKey: Self.refreshPresetKey)
        updateRefreshSpeedMenu()
        restartTimer()
        updateMetrics(forceSlowRefresh: true)
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        guard
            let rawMode = sender.representedObject as? String,
            let mode = DisplayMode(rawValue: rawMode)
        else {
            return
        }

        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.displayModeKey)
        updateDisplayModeMenu()
        updateStatusItemLength()
        updateMetrics(forceSlowRefresh: true)
    }

    @objc private func openActivityMonitor() {
        let candidatePaths = [
            "/System/Applications/Utilities/Activity Monitor.app",
            "/Applications/Utilities/Activity Monitor.app"
        ]

        for path in candidatePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = statusBar.statusItem(withLength: StatusStripRenderer.width(for: displayMode))
        item.length = StatusStripRenderer.width(for: displayMode)
        guard let button = item.button else {
            return item
        }

        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.alignment = .center
        button.contentTintColor = nil

        return item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "ResourceBar", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false

        [
            cpuMenuItem,
            memoryMenuItem,
            batteryMenuItem,
            batteryPowerMenuItem,
            adapterInputMenuItem,
            temperatureMenuItem,
            networkDownMenuItem,
            networkUpMenuItem,
            diskReadMenuItem,
            diskWriteMenuItem,
            fanMenuItem
        ].forEach { $0.isEnabled = false }

        configureDisplayModeMenu()
        configureRefreshSpeedMenu()

        menu.addItem(titleItem)
        menu.addItem(.separator())
        menu.addItem(cpuMenuItem)
        menu.addItem(memoryMenuItem)
        menu.addItem(batteryMenuItem)
        menu.addItem(batteryPowerMenuItem)
        menu.addItem(adapterInputMenuItem)
        menu.addItem(temperatureMenuItem)
        menu.addItem(fanMenuItem)
        menu.addItem(.separator())
        menu.addItem(networkDownMenuItem)
        menu.addItem(networkUpMenuItem)
        menu.addItem(diskReadMenuItem)
        menu.addItem(diskWriteMenuItem)
        menu.addItem(.separator())
        let displayModeItem = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        displayModeItem.submenu = displayModeMenu
        menu.addItem(displayModeItem)
        let refreshSpeedItem = NSMenuItem(title: "Refresh Speed", action: nil, keyEquivalent: "")
        refreshSpeedItem.submenu = refreshSpeedMenu
        menu.addItem(refreshSpeedItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "a"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ResourceBar", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }

        return menu
    }

    private func updateStatusItemLength() {
        statusItem.length = StatusStripRenderer.width(for: displayMode)
    }

    private func configureDisplayModeMenu() {
        displayModeMenu.removeAllItems()

        for mode in DisplayMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(setDisplayMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            displayModeMenu.addItem(item)
        }

        updateDisplayModeMenu()
    }

    private func updateDisplayModeMenu() {
        for item in displayModeMenu.items {
            item.state = (item.representedObject as? String) == displayMode.rawValue ? .on : .off
        }
    }

    private func configureRefreshSpeedMenu() {
        refreshSpeedMenu.removeAllItems()

        for preset in RefreshPreset.allCases {
            let item = NSMenuItem(
                title: "\(preset.title) (\(preset.detail))",
                action: #selector(setRefreshSpeed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            refreshSpeedMenu.addItem(item)
        }

        updateRefreshSpeedMenu()
    }

    private func updateRefreshSpeedMenu() {
        for item in refreshSpeedMenu.items {
            item.state = (item.representedObject as? String) == refreshPreset.rawValue ? .on : .off
        }
    }

    private func memoryDetail(_ memory: MemoryPressureSnapshot) -> String {
        if let freeLevel = memory.freeLevelPercent {
            return "Memory Pressure: \(memory.pressurePercent)% (available level \(freeLevel)%)"
        }

        return "Memory Pressure: \(memory.pressurePercent)%"
    }

    private func batteryDetail(_ battery: BatterySnapshot) -> String {
        let time: String

        if battery.isOnAC, let watts = battery.batteryPowerWatts, watts < -0.25 {
            time = "supplementing adapter"
        } else if battery.isCharging {
            time = "charging"
        } else if battery.isOnAC, battery.secondsRemaining == nil {
            time = "AC power"
        } else {
            time = "\(MetricFormatter.compactMinutes(battery.secondsRemaining)) remaining"
        }

        return "Battery Time: \(time)"
    }

    private func batteryPowerDetail(_ battery: BatterySnapshot) -> String {
        let power = batteryPowerDescription(battery.batteryPowerWatts, isCharging: battery.isCharging)
        return "Battery Power: \(power)"
    }

    private func adapterInputDetail(_ battery: BatterySnapshot) -> String {
        guard battery.isOnAC else {
            return "Adapter Input: not connected"
        }

        let actual = battery.adapterInputWatts.map(MetricFormatter.watts) ?? "-- W"
        if let adapterWatts = battery.adapterWatts {
            return "Adapter Input: \(actual) actual (\(MetricFormatter.watts(adapterWatts)) max)"
        }

        return "Adapter Input: \(actual) actual"
    }

    private func batteryPowerDescription(_ watts: Double?, isCharging: Bool) -> String {
        guard let watts else {
            return isCharging ? "-- W into battery" : "not charging"
        }

        if watts > 0.25 {
            return "\(MetricFormatter.watts(watts)) into battery"
        }

        if watts < -0.25 {
            return "\(MetricFormatter.watts(abs(watts))) out of battery"
        }

        return "holding near 0 W"
    }

    private func temperatureDetail(_ processor: ProcessorTemperatureSnapshot, battery: BatterySnapshot) -> String {
        let processorTemperature = MetricFormatter.temperature(processor.celsius)
        let batteryTemperature = MetricFormatter.temperature(battery.temperatureCelsius)
        let virtualTemperature = MetricFormatter.temperature(battery.virtualTemperatureCelsius)
        return "Temperature: CPU \(processorTemperature), battery \(batteryTemperature), virtual \(virtualTemperature), thermal \(thermalStateDescription(ProcessInfo.processInfo.thermalState))"
    }

    private func fanDetail(_ fan: FanSnapshot) -> String {
        guard !fan.rpms.isEmpty else {
            return "Fan: unavailable"
        }

        let values = fan.rpms.enumerated().map { index, rpm in
            "F\(index) \(Int(rpm.rounded())) RPM"
        }.joined(separator: ", ")

        return "Fan: \(values)"
    }

    private func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}
