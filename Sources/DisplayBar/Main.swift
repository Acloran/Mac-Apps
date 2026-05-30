import AppKit

private var appDelegate: DisplayBarApp?

@main
enum DisplayBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = DisplayBarApp()
        appDelegate = delegate

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
