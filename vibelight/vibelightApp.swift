import AppKit

@main
enum VibelightMain {
    static func main() {
        NSLog("vibelight: main() entered")
        let app = NSApplication.shared
        NSLog("vibelight: NSApp.shared obtained")
        let delegate = AppDelegate()
        NSLog("vibelight: AppDelegate created")
        app.delegate = delegate
        NSLog("vibelight: delegate set")
        app.setActivationPolicy(.accessory)
        NSLog("vibelight: activation policy set, about to run()")
        app.run()
        NSLog("vibelight: app.run() returned (should never happen)")
    }
}
