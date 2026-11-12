import AppKit
import Combine

/// The whole UI: a status item with a native NSMenu.
///
/// Menu items are created once and then updated in place. Rebuilding the menu on
/// every poll would close any submenu the user has open.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let store: OopsieStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var observation: AnyCancellable?

    private let header = HeaderView()
    private let headerItem = NSMenuItem()
    private let errorItem = NSMenuItem()
    private let machinesHeader = NSMenuItem.sectionHeader(title: "Machines")
    private let emptyItem = NSMenuItem()
    private let startEngineItem: ActionItem
    private let installItem: ActionItem
    private let newItem: ActionItem
    private let newWithFolderItem: ActionItem
    private let quitItem: ActionItem
    private let separators = (0..<3).map { _ in NSMenuItem.separator() }
    private var machineEntries: [String: MachineEntry] = [:]

    init(store: OopsieStore) {
        self.store = store
        startEngineItem = ActionItem("Start Engine", symbol: "play.circle") { store.startEngine() }
        installItem = ActionItem("Install container…", symbol: "arrow.down.circle") {
            NSWorkspace.shared.open(URL(string: "https://github.com/apple/container/releases")!)
        }
        newItem = ActionItem("New Machine", symbol: "plus") { store.newMachine() }
        newWithFolderItem = ActionItem("New Machine with Folder…", symbol: "folder.badge.plus") {
            store.newMachineWithFolder()
        }
        quitItem = ActionItem("Quit Oopsie", symbol: nil) { NSApp.terminate(nil) }
        super.init()

        headerItem.view = header
        emptyItem.title = "No machines yet"
        emptyItem.isEnabled = false
        installItem.subtitle = "Or run: brew install container"
        errorItem.image = Icons.symbol("exclamationmark.triangle.fill", color: .systemOrange)
        errorItem.target = self
        errorItem.action = #selector(copyError)
        errorItem.toolTip = "Click to copy the full message"

        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        // GCD's main queue also runs while a menu is open; RunLoop.main would not.
        observation = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
        render()
    }

    func menuWillOpen(_ menu: NSMenu) {
        Task { await store.refresh() }
    }

    @objc private func copyError() {
        guard let error = store.lastError else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(error, forType: .string)
    }

    // MARK: Rendering

    private func render() {
        statusItem.button?.image = Icons.statusBar(filled: store.hasRunningMachine)
        header.update(subtitle: headerSubtitle, busy: store.activity != nil)

        if let error = store.lastError {
            errorItem.title = error.count > 60 ? String(error.prefix(60)) + "…" : error
        }
        newItem.isEnabled = store.activity == nil && store.engine != .missingCLI
        newWithFolderItem.isEnabled = newItem.isEnabled
        startEngineItem.isEnabled = store.activity == nil

        var items: [NSMenuItem] = [headerItem, separators[0]]
        if store.lastError != nil { items.append(errorItem) }

        switch store.engine {
        case .checking:
            break
        case .missingCLI:
            items.append(installItem)
        case .stopped:
            items.append(startEngineItem)
        case .running:
            items.append(machinesHeader)
            if store.machines.isEmpty { items.append(emptyItem) }
            for machine in store.machines {
                let entry = machineEntries[machine.id] ?? MachineEntry(id: machine.id, store: store)
                machineEntries[machine.id] = entry
                entry.update(machine: machine, setup: store.setup[machine.id],
                             folder: store.folders[machine.id], busy: store.working.contains(machine.id))
                items.append(entry.item)
            }
        }
        let alive = Set(store.machines.map(\.id))
        machineEntries = machineEntries.filter { alive.contains($0.key) }

        items += [separators[1], newItem, newWithFolderItem, separators[2], quitItem]
        Icons.replaceItems(of: menu, with: items)
    }

    private var headerSubtitle: String {
        if let activity = store.activity { return activity }
        switch store.engine {
        case .checking: return "Checking…"
        case .missingCLI: return "Apple's container tool is not installed"
        case .stopped: return "Container engine is stopped"
        case .running:
            let total = store.machines.count
            let running = store.machines.filter(\.isRunning).count
            if total == 0 { return "Ready" }
            return "\(total) machine\(total == 1 ? "" : "s") · \(running) running"
        }
    }
}

// MARK: - Machine entry

/// One machine's top-level item and its submenu of actions.
@MainActor
private final class MachineEntry {
    let item = NSMenuItem()
    private let submenu = NSMenu()
    private var layout = ""

    private let ssh, copySSH, copyIP, shell, folder, stop, start, remove: ActionItem
    private let failedNote = NSMenuItem()

    init(id: String, store: OopsieStore) {
        ssh = ActionItem("SSH in Terminal", symbol: "terminal") { store.openSSH(id) }
        copySSH = ActionItem("Copy SSH Command", symbol: "doc.on.doc") { store.copySSHCommand(id) }
        copyIP = ActionItem("Copy IP Address", symbol: "network") { store.copyIP(id) }
        shell = ActionItem("Open Root Shell", symbol: "apple.terminal") { store.openShell(id) }
        shell.subtitle = "Without SSH"
        folder = ActionItem("Open Shared Folder", symbol: "folder") { store.openFolder(id) }
        stop = ActionItem("Stop", symbol: "stop.circle") { store.stop(id) }
        start = ActionItem("Start", symbol: "play.circle") { store.start(id) }
        remove = ActionItem("Remove", symbol: "trash") { store.remove(id) }
        failedNote.title = "SSH setup failed"
        failedNote.subtitle = "See /var/log/oopsie-setup.log"
        failedNote.image = Icons.symbol("exclamationmark.triangle", color: .systemOrange)
        failedNote.isEnabled = false

        item.title = id
        item.submenu = submenu
        submenu.autoenablesItems = false
    }

    func update(machine: Machine, setup: SetupState?, folder shared: SharedFolder?, busy: Bool) {
        let sshReady = machine.isRunning && setup == .ready && machine.ip != nil

        let (status, color): (String, NSColor) = {
            if busy { return ("Working…", .systemOrange) }
            guard machine.isRunning else { return (machine.state.capitalized, .tertiaryLabelColor) }
            switch setup {
            case .ready: return ("Running · \(machine.ip ?? "no IP")", .systemGreen)
            case .failed: return ("Running · SSH unavailable", .systemRed)
            default: return ("Setting up SSH…", .systemOrange)
            }
        }()
        if item.subtitle != status { item.subtitle = status }
        item.image = Icons.dot(color)

        ssh.isEnabled = sshReady
        copySSH.isEnabled = sshReady
        copyIP.isEnabled = machine.ip != nil
        if let shared {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let host = shared.hostPath.hasPrefix(home) ? "~" + shared.hostPath.dropFirst(home.count) : shared.hostPath
            let text = "\(host) → \(shared.machinePath)"
            if folder.subtitle != text { folder.subtitle = text }
        }
        stop.isEnabled = !busy
        start.isEnabled = !busy
        remove.isEnabled = !busy

        // Only rebuild the submenu when its shape changes, so an open submenu stays open.
        let next = "\(machine.isRunning)-\(setup == .failed)-\(shared != nil)"
        guard next != layout else { return }
        layout = next
        var items: [NSMenuItem] = []
        if machine.isRunning {
            items += [ssh, copySSH, copyIP, shell]
            if setup == .failed { items.append(failedNote) }
            if shared != nil { items += [.separator(), folder] }
            items += [.separator(), stop]
        } else {
            items.append(start)
            if shared != nil { items += [.separator(), folder] }
        }
        items += [.separator(), remove]
        Icons.replaceItems(of: submenu, with: items)
    }
}

// MARK: - Header

/// "Oopsie" with the app icon, a status line and a spinner.
private final class HeaderView: NSView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "Oopsie")
    private let subtitle = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 50))
        autoresizingMask = [.width]

        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        for view in [icon, labels, spinner] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -8),
            spinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(subtitle text: String, busy: Bool) {
        if subtitle.stringValue != text { subtitle.stringValue = text }
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
}

// MARK: - Helpers

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String?, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { handler() }
}

@MainActor
private enum Icons {
    /// A one-colour version of the app icon: a starburst with a ">_" prompt.
    /// Filled when a machine is running, outlined when not.
    static func statusBar(filled: Bool) -> NSImage? {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let points = 12
            let burst = NSBezierPath()
            for i in 0..<(points * 2) {
                let inset: CGFloat = filled ? 0 : 0.7
                let radius: CGFloat = (i.isMultiple(of: 2) ? 8.6 : 6.1) - inset
                let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
                let point = NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                i == 0 ? burst.move(to: point) : burst.line(to: point)
            }
            burst.close()

            let prompt = NSBezierPath()
            prompt.move(to: NSPoint(x: 5.6, y: 6.3))
            prompt.line(to: NSPoint(x: 8.2, y: 8.7))
            prompt.line(to: NSPoint(x: 5.6, y: 11.1))
            prompt.move(to: NSPoint(x: 9.6, y: 11.3))
            prompt.line(to: NSPoint(x: 12.6, y: 11.3))
            prompt.lineWidth = 1.5
            prompt.lineCapStyle = .round
            prompt.lineJoinStyle = .round

            NSColor.black.set()
            if filled {
                burst.fill()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                prompt.stroke()
            } else {
                burst.lineWidth = 1.2
                burst.lineJoinStyle = .round
                burst.stroke()
                prompt.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Oopsie"
        return image
    }

    static func symbol(_ name: String, color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [color]))
    }

    private static var dots: [NSColor: NSImage] = [:]

    static func dot(_ color: NSColor) -> NSImage {
        if let cached = dots[color] { return cached }
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        dots[color] = image
        return image
    }

    /// Replaces a menu's items only if they differ, so open submenus stay open.
    static func replaceItems(of menu: NSMenu, with items: [NSMenuItem]) {
        guard !menu.items.elementsEqual(items, by: ===) else { return }
        menu.removeAllItems()
        items.forEach(menu.addItem)
    }
}
