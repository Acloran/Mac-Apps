import AppKit
import CoreGraphics

private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, _, userInfo in
    guard let userInfo else {
        return
    }

    let app = Unmanaged<DisplayBarApp>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        app.handleDisplayConfigurationChanged()
    }
}

final class DisplayBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let displayManager = DisplayManager()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        configureStatusItem()
        menu.delegate = self
        statusItem.menu = menu

        displayManager.restoreColorSyncSettings()
        displayManager.restoreHDRBoostedDisplays()
        refreshTooltip()

        CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        displayManager.disableHDRBoostForTermination()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    func handleDisplayConfigurationChanged() {
        displayManager.restoreHDRBoostedDisplays()
        refreshTooltip()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(systemSymbolName: "display", accessibilityDescription: "DisplayBar") {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = "D"
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let titleItem = NSMenuItem(title: "DisplayBar", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let displays = displayManager.displays()
        if displayManager.isBetterDisplayRunning() {
            let warningItem = NSMenuItem(title: "BetterDisplay is running and may override changes", action: nil, keyEquivalent: "")
            warningItem.isEnabled = false
            menu.addItem(warningItem)
            menu.addItem(.separator())
        }

        if displays.isEmpty {
            let emptyItem = NSMenuItem(title: "No displays found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for display in displays {
                let item = NSMenuItem(title: display.name, action: nil, keyEquivalent: "")
                item.submenu = makeDisplayMenu(for: display)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Refresh Displays", action: #selector(refreshDisplays), key: "r"))
        menu.addItem(actionItem(title: "Open Displays Settings", action: #selector(openDisplaysSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit DisplayBar", action: #selector(quit), key: "q"))
    }

    private func makeDisplayMenu(for display: DisplaySnapshot) -> NSMenu {
        let displayMenu = NSMenu()

        let infoItem = NSMenuItem(title: displayDetail(display), action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        displayMenu.addItem(infoItem)

        let colorModesItem = NSMenuItem(title: colorModeSummary(display), action: nil, keyEquivalent: "")
        colorModesItem.isEnabled = false
        displayMenu.addItem(colorModesItem)

        if display.edrHeadroom > 1 {
            let edrItem = NSMenuItem(
                title: String(format: "EDR Boost Headroom: %.1fx", min(display.edrHeadroom, 4)),
                action: nil,
                keyEquivalent: ""
            )
            edrItem.isEnabled = false
            displayMenu.addItem(edrItem)
        }

        displayMenu.addItem(.separator())
        displayMenu.addItem(sliderItem(
            title: displayManager.isHDRBoostEnabled(for: display.id) ? "Brightness (Boosted 100%)" : "Brightness",
            value: display.brightness ?? 1,
            minValue: 0,
            maxValue: 1,
            formatter: MenuValueFormatter.percent
        ) { [weak self] value in
            self?.displayManager.setBrightness(value, for: display.id)
        })

        displayMenu.addItem(.separator())
        let modeItem = NSMenuItem(title: "Color Mode / Bit Depth", action: nil, keyEquivalent: "")
        modeItem.submenu = makeModeMenu(for: display)
        displayMenu.addItem(modeItem)

        if display.isBuiltin {
            displayMenu.addItem(.separator())
            let hdrItem = actionItem(
                title: "Boost 100% Brightness",
                action: #selector(toggleHDRBoost(_:)),
                key: ""
            )
            hdrItem.representedObject = DisplayAction(displayID: display.id)
            hdrItem.state = displayManager.isHDRBoostEnabled(for: display.id) ? .on : .off
            hdrItem.isEnabled = display.edrHeadroom > 1
            displayMenu.addItem(hdrItem)
        }

        return displayMenu
    }

    private func makeModeMenu(for display: DisplaySnapshot) -> NSMenu {
        let modeMenu = NSMenu()
        let currentIdentity = display.currentMode?.identity

        for mode in display.modes {
            let item = NSMenuItem(title: mode.title, action: #selector(setDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ModeAction(displayID: display.id, mode: mode.mode)
            item.state = mode.identity == currentIdentity ? .on : .off
            item.toolTip = mode.colorOutput.detail
            modeMenu.addItem(item)
        }

        return modeMenu
    }

    private func sliderItem(
        title: String,
        value: Double,
        minValue: Double,
        maxValue: Double,
        formatter: @escaping (Double) -> String,
        onChange: @escaping (Double) -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = SliderMenuItemView(
            title: title,
            value: value,
            minValue: minValue,
            maxValue: maxValue,
            formatter: formatter,
            onChange: onChange
        )
        return item
    }

    private func actionItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func displayDetail(_ display: DisplaySnapshot) -> String {
        let modeTitle = display.currentMode?.title ?? "unknown mode"
        let role = display.isBuiltin ? "built-in" : "external"
        return "\(modeTitle), \(role), \(String(format: "%.1fx", display.scale)) scale"
    }

    private func colorModeSummary(_ display: DisplaySnapshot) -> String {
        let uniqueModes = Set(display.modes.map { $0.colorOutput.title }).sorted()

        if uniqueModes.isEmpty {
            return "Color modes exposed: none"
        }

        if uniqueModes.count == 1, let onlyMode = uniqueModes.first {
            return "Only \(onlyMode) exposed by macOS"
        }

        return "Color modes exposed: \(uniqueModes.joined(separator: ", "))"
    }

    private func refreshTooltip() {
        let details = displayManager.displays().map { display in
            "\(display.name): \(display.currentMode?.title ?? "unknown")"
        }
        statusItem.button?.toolTip = details.isEmpty ? "DisplayBar" : details.joined(separator: "\n")
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ModeAction else {
            return
        }

        displayManager.setDisplayMode(action.mode, for: action.displayID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshTooltip()
        }
    }

    @objc private func toggleHDRBoost(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? DisplayAction else {
            return
        }

        let enabled = !displayManager.isHDRBoostEnabled(for: action.displayID)
        displayManager.setHDRBoost(enabled, for: action.displayID)
        sender.state = enabled ? .on : .off
    }

    @objc private func refreshDisplays() {
        handleDisplayConfigurationChanged()
    }

    @objc private func openDisplaysSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
            return
        }

        let legacyURL = URL(fileURLWithPath: "/System/Library/PreferencePanes/Displays.prefPane")
        NSWorkspace.shared.open(legacyURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
