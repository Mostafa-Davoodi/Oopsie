import Foundation

/// The result of running a `container` subcommand.
struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { status == 0 }

    /// Last meaningful line of output, for showing in the UI when something fails.
    var summary: String {
        let text = stderr.isEmpty ? stdout : stderr
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? "exit code \(status)"
    }
}

/// A thin wrapper around Apple's `container` CLI (github.com/apple/container).
enum ContainerCLI {
    /// The one and only distro. No config, remember?
    static let image = "docker.io/library/ubuntu:latest"
    static let namePrefix = "oopsie-"

    static var executablePath: String? {
        let candidates = [
            "/usr/local/bin/container",
            "/opt/homebrew/bin/container",
            "/usr/bin/container",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool { executablePath != nil }

    // MARK: - Running commands

    static func run(_ args: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(args))
            }
        }
    }

    /// Blocking variant. Reads stdout and stderr concurrently so chatty commands
    /// (like image pulls) can't fill a pipe and deadlock.
    static func runSync(_ args: [String]) -> CommandResult {
        guard let exe = executablePath else {
            return CommandResult(status: -1, stdout: "", stderr: "container CLI not found")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do { try process.run() } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        let errBox = DataBox()
        let errHandle = err.fileHandleForReading
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errHandle.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errBox.data, as: UTF8.self)
        )
    }

    // MARK: - Engine

    static func isEngineRunning() async -> Bool {
        await run(["system", "status"]).ok
    }

    static func startEngine() async -> CommandResult {
        // Non-interactive: accept the default kernel instead of prompting on stdin.
        await run(["system", "start", "--enable-kernel-install"])
    }

    // MARK: - Images

    static func hasImage() async -> Bool {
        await run(["image", "inspect", image]).ok
    }

    static func pullImage() async -> CommandResult {
        await run(["image", "pull", image])
    }

    // MARK: - Machines

    static func newMachineName() -> String {
        let hex = String(UInt32.random(in: 0...0xFFFF), radix: 16)
        return namePrefix + String(repeating: "0", count: 4 - hex.count) + hex
    }

    /// Starts a long-lived container we can exec shells into.
    static func startMachine(named name: String) async -> CommandResult {
        await run(["run", "--detach", "--name", name, image, "sleep", "infinity"])
    }

    /// Gives the shell a little personality: colourful prompt and a welcome note.
    static func decorate(machine name: String) async {
        let snippet = #"""

        # --- Oopsie ---
        export PS1='\[\e[1;38;5;205m\]oopsie\[\e[0m\]@\[\e[38;5;141m\]\h\[\e[0m\]:\[\e[1;38;5;117m\]\w\[\e[0m\]\$ '
        printf '\n  \e[1;38;5;205mOopsie!\e[0m  A fresh Ubuntu box with zero consequences.\n'
        printf '  \e[2mInstall things. Delete things. Nothing in here can touch your Mac.\e[0m\n\n'
        """#
        let b64 = Data(snippet.utf8).base64EncodedString()
        _ = await run(["exec", name, "sh", "-c", "echo \(b64) | base64 -d >> /root/.bashrc"])
    }

    static func destroy(machine name: String) async {
        destroySync(machine: name)
    }

    static func destroySync(machine name: String) {
        if runSync(["delete", "--force", name]).ok { return }
        // Older CLIs: stop first, then delete.
        _ = runSync(["stop", "--time", "0", name])
        _ = runSync(["delete", name])
    }

    /// Removes any machines left behind by a crash or a force-quit.
    static func cleanUpStrays() async {
        let list = await run(["list", "--all", "--quiet"])
        guard list.ok else { return }
        let strays = list.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(namePrefix) }
        for name in strays { await destroy(machine: name) }
    }

    /// Arguments for the interactive shell the terminal runs.
    static func shellArguments(for name: String) -> [String] {
        ["exec", "--interactive", "--tty", name, "bash"]
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
