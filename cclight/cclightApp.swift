import AppKit

@main
enum CCLightMain {
    static func main() {
        NSLog("cclight: main() entered")
        let app = NSApplication.shared
        NSLog("cclight: NSApp.shared obtained")
        let delegate = AppDelegate()
        NSLog("cclight: AppDelegate created")
        app.delegate = delegate
        NSLog("cclight: delegate set")
        app.setActivationPolicy(.accessory)
        NSLog("cclight: activation policy set, about to run()")
        app.run()
        NSLog("cclight: app.run() returned (should never happen)")
    }
}
