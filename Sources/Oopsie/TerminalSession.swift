import AppKit
import SwiftUI
import SwiftTerm

/// Owns the live terminal view so it survives the menu bar window closing and reopening.
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    private(set) var view: LocalProcessTerminalView?
    /// Bumps every time a fresh terminal view is created, so SwiftUI re-embeds it.
    private(set) var generation = 0
    var onExit: (() -> Void)?

    func start(machine name: String) {
        stop()
        guard let exe = ContainerCLI.executablePath else { return }

        let term = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 540, height: 320))
        Self.applyTheme(to: term)
        term.processDelegate = self

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        let envList = env.map { "\($0.key)=\($0.value)" }

        term.startProcess(
            executable: exe,
            args: ContainerCLI.shellArguments(for: name),
            environment: envList,
            execName: "container"
        )
        view = term
        generation += 1
    }

    func stop() {
        guard let term = view else { return }
        term.processDelegate = nil
        term.terminate()
        term.removeFromSuperview()
        view = nil
    }

    func focus() {
        guard let term = view else { return }
        term.window?.makeFirstResponder(term)
    }

    // MARK: Clipboard (menu bar apps have no Edit menu, so wire it up ourselves)

    var isFocused: Bool {
        guard let term = view, let responder = term.window?.firstResponder else { return false }
        return responder === term
    }

    func paste() { view?.paste(self) }
    func copy() { view?.copy(self) }
    func selectAll() { view?.selectAll(self) }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onExit?() }
        }
    }

    // MARK: Theme — "Grape Soda"

    private static func rgb(_ hex: UInt32) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16((hex >> 16) & 0xFF) * 257,
            green: UInt16((hex >> 8) & 0xFF) * 257,
            blue: UInt16(hex & 0xFF) * 257
        )
    }

    static func applyTheme(to term: LocalProcessTerminalView) {
        term.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        term.nativeBackgroundColor = NSColor(srgbRed: 0.090, green: 0.075, blue: 0.122, alpha: 1)
        term.nativeForegroundColor = NSColor(srgbRed: 0.93, green: 0.91, blue: 0.97, alpha: 1)
        term.caretColor = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.62, alpha: 1)
        term.optionAsMetaKey = true
        term.installColors([
            rgb(0x2A2438), rgb(0xFF5C8A), rgb(0x7EE787), rgb(0xFFD166),
            rgb(0x7AA2F7), rgb(0xC792EA), rgb(0x5EE6EB), rgb(0xD8D0E8),
            rgb(0x5B5170), rgb(0xFF85A8), rgb(0xA6F4AE), rgb(0xFFE29A),
            rgb(0xA3C0FF), rgb(0xDDB6F2), rgb(0x9AF2F5), rgb(0xFFFFFF),
        ])
    }
}

/// Embeds the session's terminal view in SwiftUI.
struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.wantsLayer = true
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        guard let term = session.view else { return }
        if term.superview !== host {
            host.subviews.forEach { $0.removeFromSuperview() }
            term.frame = host.bounds
            term.autoresizingMask = [.width, .height]
            host.addSubview(term)
        }
        Task { @MainActor in session.focus() }
    }
}
