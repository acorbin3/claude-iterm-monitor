import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var monitor: SessionMonitor!
    var menuBarController: MenuBarController!

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = SessionMonitor()
        menuBarController = MenuBarController(monitor: monitor)
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }
}
