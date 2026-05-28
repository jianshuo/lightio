import AppKit

@main
enum LightioMain {
    static func main() {
        NSLog("lightio: main() entered")
        let app = NSApplication.shared
        NSLog("lightio: NSApp.shared obtained")
        let delegate = AppDelegate()
        NSLog("lightio: AppDelegate created")
        app.delegate = delegate
        NSLog("lightio: delegate set")
        app.setActivationPolicy(.accessory)
        NSLog("lightio: activation policy set, about to run()")
        app.run()
        NSLog("lightio: app.run() returned (should never happen)")
    }
}
