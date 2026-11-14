// SPDX-License-Identifier: Apache-2.0

import AppKit

/// A Mac folder mounted into a machine.
struct SharedFolder: Codable, Equatable {
    let hostPath: String
    let machinePath: String
}

@MainActor
final class OopsieStore: ObservableObject {
    enum Engine: Equatable {
        case checking, missingCLI, stopped, running
    }

    @Published private(set) var engine: Engine = .checking
    @Published private(set) var machines: [Machine] = []
    @Published private(set) var setup: [String: SetupState] = [:]
    /// Machines with an action in progress (start, stop, remove).
    @Published private(set) var working: Set<String> = []
    /// What a long app-wide task is doing right now, e.g. "Downloading Ubuntu…".
    @Published private(set) var activity: String?
    @Published private(set) var lastError: String?
    /// Shared folders by machine name. `container list` doesn't report mounts, so we remember them.
    @Published private(set) var folders: [String: SharedFolder] {
        didSet { Self.saveFolders(folders) }
    }

    private let notifier = Notifier()

    init() {
        folders = Self.loadFolders()
        notifier.onOpen = { [weak self] id in self?.openSSH(id) }
        Task { await pollForever() }
    }

    var hasRunningMachine: Bool { machines.contains { $0.isRunning } }

    // MARK: Polling

    private func pollForever() async {
        while true {
            await refresh()
            let settling = activity != nil || !working.isEmpty
                || machines.contains { $0.isRunning && setup[$0.id] != .ready }
            try? await Task.sleep(for: .seconds(settling ? 2 : 5))
        }
    }

    /// Reads the machine list. Only publishes values that changed, so an open menu isn't disturbed.
    func refresh() async {
        guard ContainerCLI.isInstalled else {
            set(\.engine, .missingCLI)
            set(\.machines, [])
            return
        }
        guard let list = await ContainerCLI.listMachines() else {
            set(\.engine, .stopped)
            set(\.machines, [])
            return
        }
        set(\.engine, .running)
        set(\.machines, list)

        var next: [String: SetupState] = [:]
        for machine in list where machine.isRunning {
            let known = setup[machine.id]
            let state = known == .ready ? .ready : await ContainerCLI.setupState(of: machine.id)
            next[machine.id] = state
            if known == .pending { notifyIfDone(machine, state) }
        }
        set(\.setup, next)

        let alive = Set(list.map(\.id))
        set(\.folders, folders.filter { alive.contains($0.key) })
    }

    /// Tells the user when a machine that was setting up is ready (or failed).
    private func notifyIfDone(_ machine: Machine, _ state: SetupState) {
        switch state {
        case .ready:
            notifier.post(title: "\(machine.id) is ready",
                          body: "Click to SSH in. IP address: \(machine.ip ?? "unknown").",
                          machine: machine.id)
        case .failed:
            notifier.post(title: "\(machine.id) has no SSH",
                          body: "SSH setup failed. Use Open Root Shell instead.",
                          machine: machine.id)
        case .pending:
            break
        }
    }

    private func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<OopsieStore, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    // MARK: App-wide actions

    func startEngine() {
        guard activity == nil else { return }
        Task {
            activity = "Starting container engine…"
            let result = await ContainerCLI.startEngine()
            if !result.ok { lastError = "Engine didn't start. \(result.summary)" }
            activity = nil
            await refresh()
        }
    }

    /// Asks for a Mac folder, then creates a machine with that folder mounted in /root.
    func newMachineWithFolder() {
        guard activity == nil, ContainerCLI.isInstalled else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Share Folder"
        panel.message = "Choose a folder to share with the new machine. It shows up in /root."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        newMachine(sharing: url)
    }

    func newMachine(sharing folderURL: URL? = nil) {
        guard activity == nil, ContainerCLI.isInstalled else { return }

        var folder: SharedFolder?
        if let folderURL {
            let path = folderURL.standardizedFileURL.path
            guard !path.contains(":") else {
                lastError = "Can't share a folder whose path contains \":\"."
                return
            }
            folder = SharedFolder(hostPath: path, machinePath: "/root/" + Self.safeName(folderURL.lastPathComponent))
        }

        lastError = nil
        Task {
            defer { activity = nil }

            if let error = SSH.ensureKey() { lastError = error; return }

            if !(await ContainerCLI.isEngineRunning()) {
                activity = "Starting container engine…"
                let started = await ContainerCLI.startEngine()
                guard started.ok else { lastError = "Engine didn't start. \(started.summary)"; return }
            }

            if !(await ContainerCLI.hasImage()) {
                activity = "Downloading Ubuntu…"
                let pulled = await ContainerCLI.pullImage()
                guard pulled.ok else { lastError = "Couldn't download Ubuntu. \(pulled.summary)"; return }
            }

            activity = "Creating machine…"
            let name = ContainerCLI.newMachineName()
            let created = await ContainerCLI.createMachine(
                named: name,
                authorizedKeys: SSH.authorizedKeys(),
                mount: folder.map { ($0.hostPath, $0.machinePath) }
            )
            guard created.ok else { lastError = "Couldn't create machine. \(created.summary)"; return }
            if let folder { folders[name] = folder }
            setup[name] = .pending   // so we notify when it's ready
            await refresh()
        }
    }

    // MARK: Machine actions

    func start(_ id: String) {
        perform(on: id, "start") { await ContainerCLI.start(id) }
    }

    func stop(_ id: String) {
        perform(on: id, "stop") { await ContainerCLI.stop(id) }
    }

    func remove(_ id: String) {
        perform(on: id, "remove") { await ContainerCLI.delete(id) }
    }

    func openSSH(_ id: String) {
        guard let ip = ip(of: id) else { return }
        TerminalLauncher.open(SSH.command(ip: ip))
    }

    func openShell(_ id: String) {
        guard let command = ContainerCLI.shellCommand(for: id) else { return }
        TerminalLauncher.open(command)
    }

    func openFolder(_ id: String) {
        guard let folder = folders[id] else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: folder.hostPath))
    }

    func copySSHCommand(_ id: String) {
        guard let ip = ip(of: id) else { return }
        copy(SSH.command(ip: ip))
    }

    func copyIP(_ id: String) {
        guard let ip = ip(of: id) else { return }
        copy(ip)
    }

    private func ip(of id: String) -> String? {
        machines.first { $0.id == id }?.ip
    }

    /// A folder name that is safe as a single path component in the machine.
    static func safeName(_ name: String) -> String {
        let cleaned = String(name.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "-" })
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".-")).isEmpty ? "shared" : cleaned
    }

    private static let foldersKey = "sharedFolders"

    private static func loadFolders() -> [String: SharedFolder] {
        guard let data = UserDefaults.standard.data(forKey: foldersKey),
              let folders = try? JSONDecoder().decode([String: SharedFolder].self, from: data)
        else { return [:] }
        return folders
    }

    private static func saveFolders(_ folders: [String: SharedFolder]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(folders), forKey: foldersKey)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func perform(on id: String, _ verb: String, _ action: @escaping () async -> CommandResult) {
        guard !working.contains(id) else { return }
        lastError = nil
        working.insert(id)
        Task {
            let result = await action()
            if !result.ok { lastError = "Couldn't \(verb) \(id). \(result.summary)" }
            working.remove(id)
            await refresh()
        }
    }
}
