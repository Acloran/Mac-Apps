import AppKit
import CoreImage
import MetalKit
import QuartzCore

final class EDRKeepAliveController {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]

    func enable(displayID: CGDirectDisplayID, headroom: Double, brightness: Double) {
        guard let screen = screen(for: displayID) else {
            return
        }

        let boost = boostAmount(headroom: headroom, brightness: brightness)
        guard boost > 0 else {
            disable(displayID: displayID)
            return
        }

        if let window = windows[displayID],
           let view = window.contentView as? EDROverlayView {
            view.update(boost: boost)
            return
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.level = .mainMenu
        window.hidesOnDeactivate = false
        window.contentView = EDROverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), boost: boost)
        window.orderFrontRegardless()
        windows[displayID] = window
    }

    func disable(displayID: CGDirectDisplayID) {
        guard let window = windows.removeValue(forKey: displayID) else {
            return
        }

        window.orderOut(nil)
        window.close()
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }

            return number.uint32Value == displayID
        }
    }

    private func boostAmount(headroom: Double, brightness: Double) -> Float {
        let clampedHeadroom = max(1, min(4, headroom))
        let clampedBrightness = max(0, min(1, brightness))
        return Float((clampedHeadroom - 1) * clampedBrightness)
    }
}

private final class EDROverlayView: MTKView, MTKViewDelegate {
    private let edrColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    private var commandQueue: MTLCommandQueue?
    private var renderContext: CIContext?
    private var image: CIImage?
    private var boost: Float

    init(frame: CGRect, boost: Float) {
        self.boost = max(0, min(3, boost))
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        configureMetal()
        rebuildImage()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(boost: Float) {
        let nextBoost = max(0, min(3, boost))
        guard abs(nextBoost - self.boost) > 0.005 else {
            return
        }

        self.boost = nextBoost
        rebuildImage()
    }

    private func configureMetal() {
        guard let device else {
            return
        }

        commandQueue = device.makeCommandQueue()
        if let commandQueue {
            renderContext = CIContext(mtlCommandQueue: commandQueue, options: [
                .name: "DisplayBarEDRContext",
                .workingColorSpace: edrColorSpace ?? CGColorSpaceCreateDeviceRGB(),
                .workingFormat: CIFormat.RGBAf,
                .cacheIntermediates: false,
                .allowLowPower: false
            ])
        }

        delegate = self
        framebufferOnly = false
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 3
        colorPixelFormat = .rgba16Float
        colorspace = edrColorSpace

        guard let layer = layer as? CAMetalLayer else {
            return
        }

        layer.isOpaque = false
        layer.compositingFilter = "multiplyBlendMode"
        if #available(macOS 14.0, *) {
            layer.wantsExtendedDynamicRangeContent = true
        }
    }

    private func rebuildImage() {
        guard let edrColorSpace,
              let white = CIColor(red: 1, green: 1, blue: 1, alpha: 1, colorSpace: edrColorSpace),
              let colorControls = CIFilter(name: "CIColorControls") else {
            return
        }

        colorControls.setValue(CIImage(color: white), forKey: kCIInputImageKey)
        colorControls.setValue(1.0, forKey: kCIInputContrastKey)
        colorControls.setValue(boost, forKey: kCIInputBrightnessKey)
        image = colorControls.outputImage?.cropped(to: CGRect(origin: .zero, size: drawableSize))
    }

    func draw(in view: MTKView) {
        guard let image,
              let edrColorSpace,
              let commandQueue,
              let renderContext,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let drawable = currentDrawable else {
            return
        }

        let bounds = CGRect(origin: .zero, size: drawableSize)
        renderContext.render(
            image,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: edrColorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        rebuildImage()
    }
}
