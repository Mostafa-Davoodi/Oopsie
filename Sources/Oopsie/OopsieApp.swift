import AppKit

@main
enum OopsieApp {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menu: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = MenuController(store: OopsieStore())
    }
}
