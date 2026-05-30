import AppKit

private var appDelegate: ResourceBarApp?

@main
enum ResourceBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = ResourceBarApp()
        appDelegate = delegate

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
