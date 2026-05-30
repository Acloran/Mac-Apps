import AppKit
import ApplicationServices
import CMetrics
import CoreGraphics
import Foundation
import IOKit

final class DisplayManager {
    private let hdrDefaultsKey = "DisplayBar.hdrBoostDisplays"
    private let edrKeeper = EDRKeepAliveController()

    private var hdrBoostDisplayKeys: Set<String>

    init() {
        hdrBoostDisplayKeys = Set(UserDefaults.standard.stringArray(forKey: hdrDefaultsKey) ?? [])
        UserDefaults.standard.removeObject(forKey: "DisplayBar.softwareColorSettings")
    }

    func displays() -> [DisplaySnapshot] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }

        return ids.prefix(Int(count)).map(displaySnapshot).sorted { left, right in
            if left.isBuiltin != right.isBuiltin {
                return left.isBuiltin
            }

            return left.frame.minX < right.frame.minX
        }
    }

    func displayKey(for displayID: CGDirectDisplayID) -> String {
        let vendor = CGDisplayVendorNumber(displayID)
        let product = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        return "\(vendor)-\(product)-\(serial)-\(displayID)"
    }

    func brightness(for displayID: CGDirectDisplayID) -> Double? {
        let framebuffer = framebufferService(for: displayID)
        var value: Float = 0

        if ResourceBarDisplayGetBrightness(framebuffer, &value) == 1 {
            return normalized(Double(value), min: 0, max: 1)
        }

        if ResourceBarDisplayServicesGetBrightness(displayID, &value) == 1 {
            return normalized(Double(value), min: 0, max: 1)
        }

        var coreDisplayValue: Double = 0
        if ResourceBarCoreDisplayGetUserBrightness(displayID, &coreDisplayValue) == 1 {
            return normalized(coreDisplayValue, min: 0, max: 1)
        }

        if !isBuiltin(displayID), let ddc = ddcValue(displayID: displayID, control: .brightness) {
            return ddc.normalized
        }

        return nil
    }

    @discardableResult
    func setBrightness(_ value: Double, for displayID: CGDirectDisplayID) -> Bool {
        let clampedValue = normalized(value, min: 0, max: 1)
        let framebuffer = framebufferService(for: displayID)
        var applied = false

        if ResourceBarDisplaySetBrightness(framebuffer, Float(clampedValue)) == 1 {
            applied = true
        }

        if ResourceBarDisplayServicesSetBrightness(displayID, Float(clampedValue)) == 1 {
            applied = true
        }

        if ResourceBarCoreDisplaySetUserBrightness(displayID, clampedValue) == 1 {
            applied = true
        }

        if isHDRBoostEnabled(for: displayID), isBuiltin(displayID) {
            let boostedLinearBrightness = max(0.01, clampedValue * hdrBoostMultiplier(for: displayID))
            ResourceBarCoreDisplaySetDynamicSliderFactor(displayID, hdrBoostMultiplier(for: displayID))
            edrKeeper.enable(displayID: displayID, headroom: edrHeadroom(for: displayID), brightness: clampedValue)

            if ResourceBarCoreDisplaySetLinearBrightness(displayID, boostedLinearBrightness) == 1 {
                applied = true
            }

            if ResourceBarCoreDisplaySetDynamicLinearBrightness(displayID, boostedLinearBrightness) == 1 {
                applied = true
            }
        }

        if !isBuiltin(displayID) {
            let maximum = ddcValue(displayID: displayID, control: .brightness)?.maximum ?? DDCControl.brightness.defaultMaximum
            let rawValue = UInt16((Double(maximum) * clampedValue).rounded())
            if ResourceBarDDCSetVCP(framebuffer, DDCControl.brightness.code, rawValue) == 1 {
                applied = true
            }
        }

        return applied
    }

    func ddcValue(displayID: CGDirectDisplayID, control: DDCControl) -> DDCValue? {
        let framebuffer = framebufferService(for: displayID)
        var current: UInt16 = 0
        var maximum: UInt16 = 0

        guard ResourceBarDDCGetVCP(framebuffer, control.code, &current, &maximum) == 1 else {
            return nil
        }

        return DDCValue(current: current, maximum: maximum > 0 ? maximum : control.defaultMaximum)
    }

    func restoreColorSyncSettings() {
        CGDisplayRestoreColorSyncSettings()
    }

    func isBetterDisplayRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "pro.betterdisplay.BetterDisplay").isEmpty
    }

    func isHDRBoostEnabled(for displayID: CGDirectDisplayID) -> Bool {
        hdrBoostDisplayKeys.contains(displayKey(for: displayID))
    }

    func setHDRBoost(_ enabled: Bool, for displayID: CGDirectDisplayID) {
        let key = displayKey(for: displayID)
        let currentBrightness = brightness(for: displayID) ?? 1

        if enabled {
            hdrBoostDisplayKeys.insert(key)
            setBrightness(currentBrightness, for: displayID)
        } else {
            hdrBoostDisplayKeys.remove(key)
            ResourceBarCoreDisplaySetDynamicSliderFactor(displayID, 1)
            ResourceBarCoreDisplaySetLinearBrightness(displayID, 1)
            ResourceBarCoreDisplaySetDynamicLinearBrightness(displayID, 1)
            edrKeeper.disable(displayID: displayID)
            setBrightness(currentBrightness, for: displayID)
        }

        UserDefaults.standard.set(Array(hdrBoostDisplayKeys), forKey: hdrDefaultsKey)
    }

    func restoreHDRBoostedDisplays() {
        for display in displays() where isHDRBoostEnabled(for: display.id) {
            setBrightness(display.brightness ?? 1, for: display.id)
        }
    }

    func disableHDRBoostForTermination() {
        let savedHDRBoostKeys = hdrBoostDisplayKeys

        for display in displays() where isHDRBoostEnabled(for: display.id) {
            let currentBrightness = brightness(for: display.id) ?? 1
            hdrBoostDisplayKeys.remove(display.key)
            ResourceBarCoreDisplaySetDynamicSliderFactor(display.id, 1)
            ResourceBarCoreDisplaySetLinearBrightness(display.id, 1)
            ResourceBarCoreDisplaySetDynamicLinearBrightness(display.id, 1)
            edrKeeper.disable(displayID: display.id)
            setBrightness(currentBrightness, for: display.id)
        }

        hdrBoostDisplayKeys = savedHDRBoostKeys
    }

    @discardableResult
    func setDisplayMode(_ mode: CGDisplayMode, for displayID: CGDirectDisplayID) -> Bool {
        CGDisplaySetDisplayMode(displayID, mode, nil) == .success
    }

    private func displaySnapshot(for displayID: CGDirectDisplayID) -> DisplaySnapshot {
        let currentMode = CGDisplayCopyDisplayMode(displayID).map(modeSnapshot)
        let modes = allModes(for: displayID)
        let screen = screen(for: displayID)

        return DisplaySnapshot(
            id: displayID,
            key: displayKey(for: displayID),
            name: displayName(for: displayID, screen: screen),
            isBuiltin: isBuiltin(displayID),
            frame: CGDisplayBounds(displayID),
            scale: screen?.backingScaleFactor ?? 1,
            edrHeadroom: edrHeadroom(for: displayID, screen: screen),
            currentMode: currentMode,
            modes: modes,
            brightness: brightness(for: displayID)
        )
    }

    private func allModes(for displayID: CGDirectDisplayID) -> [DisplayModeSnapshot] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let rawModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] ?? []
        var seen = Set<String>()

        return rawModes.map(modeSnapshot)
            .filter { mode in
                if seen.contains(mode.identity) {
                    return false
                }

                seen.insert(mode.identity)
                return true
            }
            .sorted { left, right in
                if left.isHiDPI != right.isHiDPI {
                    return left.isHiDPI
                }

                let leftArea = left.width * left.height
                let rightArea = right.width * right.height
                if leftArea != rightArea {
                    return leftArea > rightArea
                }

                return left.refreshRate > right.refreshRate
            }
    }

    private func modeSnapshot(_ mode: CGDisplayMode) -> DisplayModeSnapshot {
        let pixelEncoding = pixelEncoding(for: mode)
        return DisplayModeSnapshot(
            mode: mode,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate,
            ioFlags: mode.ioFlags,
            ioModeID: mode.ioDisplayModeID,
            pixelEncoding: pixelEncoding,
            colorOutput: ColorOutputSnapshot.parse(pixelEncoding)
        )
    }

    private func pixelEncoding(for mode: CGDisplayMode) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        let copied = buffer.withUnsafeMutableBufferPointer { pointer in
            ResourceBarDisplayModePixelEncoding(
                Unmanaged.passUnretained(mode).toOpaque(),
                pointer.baseAddress,
                UInt32(pointer.count)
            )
        }

        guard copied == 1 else {
            return nil
        }

        return String(cString: buffer)
    }

    private func framebufferService(for displayID: CGDirectDisplayID) -> UInt32 {
        ResourceBarDisplayFramebufferService(displayID)
    }

    private func isBuiltin(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(displayID) != 0
    }

    private func displayName(for displayID: CGDirectDisplayID, screen: NSScreen?) -> String {
        if let localizedName = screen?.localizedName, !localizedName.isEmpty {
            return localizedName
        }

        return "Display \(displayID)"
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }

            return number.uint32Value == displayID
        }
    }

    private func edrHeadroom(for displayID: CGDirectDisplayID, screen: NSScreen? = nil) -> Double {
        let candidateScreen = screen ?? self.screen(for: displayID)
        guard let candidateScreen else {
            return 1
        }

        let currentHeadroom = Double(candidateScreen.maximumExtendedDynamicRangeColorComponentValue)
        if #available(macOS 14.0, *) {
            let potentialHeadroom = Double(candidateScreen.maximumPotentialExtendedDynamicRangeColorComponentValue)
            return max(1, currentHeadroom, potentialHeadroom)
        }

        return max(1, currentHeadroom)
    }

    private func hdrBoostMultiplier(for displayID: CGDirectDisplayID) -> Double {
        guard isHDRBoostEnabled(for: displayID) else {
            return 1
        }

        return normalized(edrHeadroom(for: displayID), min: 1.25, max: 2.5)
    }

    private func normalized(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
