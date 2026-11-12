import AppKit
import SwiftUI

@main
struct OopsieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = OopsieStore.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
        } label: {
            MenuBarIcon()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        OopsieStore.shared.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        OopsieStore.shared.shutdown()
    }
}

struct MenuBarIcon: View {
    @EnvironmentObject private var store: OopsieStore

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        if store.flashIcon { return "burst.fill" }
        switch store.phase {
        case .spawning: return "hourglass"
        case .running, .shellExited: return "terminal.fill"
        default: return "burst"
        }
    }
}
