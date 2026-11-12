import AppKit
import SwiftUI

@MainActor
final class OopsieStore: ObservableObject {
    static let shared = OopsieStore()

    enum Phase: Equatable {
        case idle
        case spawning
        case running
        case shellExited
        case destroyed
        case failed(String)
        case missingCLI
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var spawnMessage = Quips.spawning.randomElement()!
    @Published private(set) var machineName: String?
    @Published private(set) var bornAt: Date?
    @Published private(set) var isBreaking = false
    @Published private(set) var boomID = 0
    @Published private(set) var boomLine = Quips.destroyed.randomElement()!
    @Published private(set) var idleLine = Quips.idle.randomElement()!
    @Published private(set) var flashIcon = false
    @Published private(set) var destroyedCount: Int {
        didSet { UserDefaults.standard.set(destroyedCount, forKey: "destroyedCount") }
    }

    let terminal = TerminalSession()
    private var keyMonitor: Any?

    private init() {
        destroyedCount = UserDefaults.standard.integer(forKey: "destroyedCount")
        terminal.onExit = { [weak self] in self?.shellDidExit() }
    }

    var isAlive: Bool { machineName != nil }
    var rank: String { Quips.rank(for: destroyedCount) }

    // MARK: Lifecycle

    func bootstrap() {
        installKeyMonitor()
        guard ContainerCLI.isInstalled else { phase = .missingCLI; return }
        Task.detached(priority: .background) {
            // Tidy up after crashes, and warm the engine + image so the first spawn is snappy.
            if await ContainerCLI.isEngineRunning() {
                await ContainerCLI.cleanUpStrays()
                if !(await ContainerCLI.hasImage()) { _ = await ContainerCLI.pullImage() }
            }
        }
    }

    func recheckCLI() {
        if ContainerCLI.isInstalled {
            phase = .idle
            idleLine = Quips.idle.randomElement()!
        }
    }

    /// Called from applicationWillTerminate. Disposable means disposable.
    func shutdown() {
        guard let name = machineName else { return }
        terminal.stop()
        ContainerCLI.destroySync(machine: name)
    }

    // MARK: Spawn

    func spawn() {
        switch phase {
        case .idle, .destroyed, .failed: break
        default: return
        }
        guard ContainerCLI.isInstalled else { phase = .missingCLI; return }

        spawnMessage = Quips.spawning.randomElement()!
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { phase = .spawning }

        Task {
            if !(await ContainerCLI.isEngineRunning()) {
                say("Waking up the container engine…")
                let started = await ContainerCLI.startEngine()
                guard started.ok else { return fail("The container engine wouldn't wake up. \(started.summary)") }
            }

            if !(await ContainerCLI.hasImage()) {
                say("Fetching Ubuntu. First time only, promise…")
                let pulled = await ContainerCLI.pullImage()
                guard pulled.ok else { return fail("Couldn't download Ubuntu. \(pulled.summary)") }
            }

            say(Quips.spawning.randomElement()!)
            let name = ContainerCLI.newMachineName()
            let started = await ContainerCLI.startMachine(named: name)
            guard started.ok else { return fail("Linux refused to boot. \(started.summary)") }

            await ContainerCLI.decorate(machine: name)

            machineName = name
            bornAt = Date()
            terminal.start(machine: name)
            NSSound(named: "Pop")?.play()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { phase = .running }
        }
    }

    func reconnect() {
        guard let name = machineName else { return }
        terminal.start(machine: name)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { phase = .running }
    }

    private func say(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) { spawnMessage = message }
    }

    private func fail(_ message: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { phase = .failed(message) }
    }

    private func shellDidExit() {
        guard phase == .running, !isBreaking else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { phase = .shellExited }
    }

    // MARK: Oopsie!

    func oopsie() {
        guard let name = machineName, !isBreaking else { return }
        guard phase == .running || phase == .shellExited else { return }

        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        withAnimation(.linear(duration: 0.42)) { isBreaking = true }

        Task {
            try? await Task.sleep(for: .milliseconds(420))
            terminal.stop()
            machineName = nil
            bornAt = nil
            NSSound(named: "Funk")?.play()
            boomLine = Quips.destroyed.randomElement()!
            boomID += 1
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                destroyedCount += 1
                phase = .destroyed
            }
            isBreaking = false
            flashMenuBarIcon()

            // The UI has already moved on; do the actual deletion in the background.
            await ContainerCLI.destroy(machine: name)
        }
    }

    private func flashMenuBarIcon() {
        flashIcon = true
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            flashIcon = false
        }
    }

    // MARK: Keyboard

    /// Menu bar apps have no main menu, so ⌘C/⌘V never reach the terminal on their own.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command else { return event }

            switch event.keyCode {
            case 51: // ⌘⌫  → Oopsie!
                if self.isAlive { self.oopsie(); return nil }
            case 36: // ⌘↩  → Spawn / Do It Again
                if !self.isAlive { self.spawn(); return nil }
            default:
                break
            }

            guard self.terminal.isFocused, let key = event.charactersIgnoringModifiers else { return event }
            switch key {
            case "v": self.terminal.paste(); return nil
            case "c": self.terminal.copy(); return nil
            case "a": self.terminal.selectAll(); return nil
            default: return event
            }
        }
    }
}
