import AppKit

/// Oopsie's own SSH key, plus the commands that use it.
enum SSH {
    static var sshDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
    }

    static var privateKey: URL { sshDirectory.appendingPathComponent("oopsie_ed25519") }
    static var publicKey: URL { sshDirectory.appendingPathComponent("oopsie_ed25519.pub") }

    /// Creates ~/.ssh/oopsie_ed25519 the first time. Returns an error message on failure.
    static func ensureKey() -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: privateKey.path), fm.fileExists(atPath: publicKey.path) { return nil }
        do {
            try fm.createDirectory(at: sshDirectory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            return "Couldn't create ~/.ssh: \(error.localizedDescription)"
        }
        try? fm.removeItem(at: privateKey)
        try? fm.removeItem(at: publicKey)
        let result = Shell.run("/usr/bin/ssh-keygen",
                               ["-q", "-t", "ed25519", "-N", "", "-C", "oopsie", "-f", privateKey.path])
        return result.ok ? nil : "Couldn't create an SSH key. \(result.summary)"
    }

    /// Oopsie's public key plus the user's own ~/.ssh/id_*.pub keys,
    /// so a plain `ssh root@<ip>` works too.
    static func authorizedKeys() -> String {
        var keys: [String] = []
        if let own = try? String(contentsOf: publicKey, encoding: .utf8) { keys.append(own) }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: sshDirectory.path)) ?? []
        for file in files.sorted() where file.hasPrefix("id_") && file.hasSuffix(".pub") {
            if let key = try? String(contentsOf: sshDirectory.appendingPathComponent(file), encoding: .utf8) {
                keys.append(key)
            }
        }
        return keys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n") + "\n"
    }

    /// Machines are throwaway and IPs get reused, so don't record host keys.
    static func command(ip: String) -> String {
        "ssh -i ~/.ssh/oopsie_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@\(ip)"
    }
}

/// Opens a command in a new Terminal.app window.
enum TerminalLauncher {
    static func open(_ command: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oopsie-\(UUID().uuidString.prefix(8)).command")
        let script = "#!/bin/sh\nrm -f \"$0\"\nclear\nexec \(command)\n"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            NSSound.beep()
        }
    }
}
