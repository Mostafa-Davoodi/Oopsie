// SPDX-License-Identifier: Apache-2.0

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

/// One Linux machine (an `oopsie-*` container).
struct Machine: Identifiable, Equatable {
    let id: String
    let isRunning: Bool
    /// Raw state from `container list`, e.g. "running" or "stopped".
    let state: String
    let ip: String?

    /// The distro the machine was made from, or nil if Oopsie doesn't know it.
    var distro: Distro? { Distro.of(machine: id) }
}

/// How far a running machine is with its SSH setup.
enum SetupState: Equatable {
    case pending, ready, failed
}

/// A thin wrapper around Apple's `container` CLI (github.com/apple/container).
enum ContainerCLI {
    static let namePrefix = "oopsie-"

    static var executablePath: String? {
        // For development: point Oopsie at another `container` binary or a fake one.
        if let custom = ProcessInfo.processInfo.environment["OOPSIE_CONTAINER"],
           FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
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
        return Shell.run(exe, args)
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

    static func hasImage(_ distro: Distro) async -> Bool {
        await run(["image", "inspect", distro.image]).ok
    }

    static func pullImage(_ distro: Distro) async -> CommandResult {
        await run(["image", "pull", "--arch", distro.arch, distro.image])
    }

    // MARK: - Machines

    /// A new name like `oopsie-fedora-1a2b`.
    static func newMachineName(for distro: Distro) -> String {
        let hex = String(UInt32.random(in: 0...0xFFFF), radix: 16)
        return namePrefix + distro.id + "-" + String(repeating: "0", count: 4 - hex.count) + hex
    }

    /// Lists all `oopsie-*` machines. Returns nil when the engine can't be reached.
    static func listMachines() async -> [Machine]? {
        let result = await run(["list", "--all", "--format", "json"])
        guard result.ok else { return nil }
        return parseList(result.stdout)
    }

    static func parseList(_ json: String) -> [Machine]? {
        guard let data = json.data(using: .utf8),
              let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return nil }

        return items.compactMap { item -> Machine? in
            let config = item["configuration"] as? [String: Any]
            guard let id = (config?["id"] ?? item["id"]) as? String, id.hasPrefix(namePrefix) else { return nil }
            let status = item["status"]
            let state = (status as? String)
                ?? ((status as? [String: Any])?["state"] as? String)
                ?? (item["state"] as? String)
                ?? "unknown"
            var withoutConfig = item
            withoutConfig["configuration"] = nil
            return Machine(
                id: id,
                isRunning: state.lowercased() == "running",
                state: state.lowercased(),
                ip: findIPv4(in: withoutConfig)
            )
        }
        .sorted { $0.id < $1.id }
    }

    /// Finds the first `ipv4Address` (or older `address`) value, without its "/24" suffix.
    static func findIPv4(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            for key in ["ipv4Address", "address"] {
                if let text = dict[key] as? String, let ip = ipv4(from: text) { return ip }
            }
            for nested in dict.values {
                if let ip = findIPv4(in: nested) { return ip }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let ip = findIPv4(in: nested) { return ip }
            }
        }
        return nil
    }

    private static func ipv4(from text: String) -> String? {
        let address = String(text.split(separator: "/").first ?? "")
        let parts = address.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else { return nil }
        return address
    }

    /// Creates and starts a machine. Its main process installs and runs sshd,
    /// so SSH keeps working for as long as the machine runs (and after a restart).
    /// `mount` is an optional (Mac folder, machine path) pair to bind-mount.
    static func createMachine(named name: String, distro: Distro, authorizedKeys: String,
                              mount: (host: String, machine: String)? = nil) async -> CommandResult {
        await run(createArguments(named: name, distro: distro, authorizedKeys: authorizedKeys, mount: mount))
    }

    static func createArguments(named name: String, distro: Distro, authorizedKeys: String,
                                mount: (host: String, machine: String)? = nil) -> [String] {
        let keys = Data(authorizedKeys.utf8).base64EncodedString()
        var args = ["run", "--detach", "--name", name, "--env", "OOPSIE_KEYS=\(keys)"]
        // arm64 is the default on Apple silicon. x86-64 images run with Rosetta.
        if distro.arch != "arm64" { args += ["--arch", distro.arch] }
        if let mount { args += ["--volume", "\(mount.host):\(mount.machine)"] }
        return args + [distro.image, "sh", "-c", setupScript]
    }

    static func start(_ name: String) async -> CommandResult {
        await run(["start", name])
    }

    static func stop(_ name: String) async -> CommandResult {
        await run(["stop", name])
    }

    static func delete(_ name: String) async -> CommandResult {
        let result = await run(["delete", "--force", name])
        if result.ok { return result }
        // Older CLIs: stop first, then delete.
        _ = await run(["stop", "--time", "0", name])
        return await run(["delete", name])
    }

    static func setupState(of name: String) async -> SetupState {
        let check = "if [ -f /run/oopsie-ready ]; then echo ready; elif [ -f /run/oopsie-failed ]; then echo failed; fi"
        let result = await run(["exec", name, "sh", "-c", check])
        switch result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "ready": return .ready
        case "failed": return .failed
        default: return .pending
        }
    }

    /// Command line for a root shell without SSH. Uses bash, or sh where there is no bash (Alpine).
    static func shellCommand(for name: String) -> String? {
        guard let exe = executablePath else { return nil }
        let shell = "command -v bash >/dev/null && exec bash || exec sh"
        return "\(Shell.quote(exe)) exec --interactive --tty \(Shell.quote(name)) sh -c \(Shell.quote(shell))"
    }

    /// The machine's main process. It runs on every start, so it must be safe to run again.
    /// It installs the SSH server with whichever package manager the distro has.
    static let setupScript = #"""
    rm -f /run/oopsie-ready /run/oopsie-failed
    trap 'exit 0' TERM INT
    idle() { while :; do sleep 3600 & wait $!; done; }
    fail() { touch /run/oopsie-failed; idle; }
    log=/var/log/oopsie-setup.log

    install_sshd() {
      if command -v apt-get > /dev/null; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update && apt-get install -y --no-install-recommends openssh-server
      elif command -v dnf > /dev/null; then
        dnf install -y --setopt=install_weak_deps=False openssh-server
      elif command -v pacman > /dev/null; then
        # pacman's download sandbox needs kernel features the machine may not have.
        nosandbox=$(pacman -Sh 2>/dev/null | grep -q -- --disable-sandbox && echo --disable-sandbox)
        pacman -Syu --noconfirm --needed $nosandbox openssh
      elif command -v apk > /dev/null; then
        apk add --no-cache openssh-server openssh-keygen
      elif command -v zypper > /dev/null; then
        zypper --non-interactive install openssh-server
      else
        echo "No known package manager (apt-get, dnf, pacman, apk or zypper)."
        return 1
      fi
    }

    find_sshd() { command -v sshd || echo /usr/sbin/sshd; }
    sshd=$(find_sshd)
    if [ ! -x "$sshd" ]; then
      install_sshd > "$log" 2>&1 || fail
      sshd=$(find_sshd)
    fi

    mkdir -p /run/sshd /root/.ssh && chmod 700 /root/.ssh
    echo "$OOPSIE_KEYS" | base64 -d > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
    # sshd refuses keys for a locked root account ("!" password), which some images have.
    sed -i 's/^root:![^:]*:/root:*:/' /etc/shadow 2>/dev/null
    # pam_loginuid can't work in a container. When it is required, it ends every SSH login.
    sed -i 's/^session\([[:space:]]*\)required\([[:space:]]*\)pam_loginuid/session\1optional\2pam_loginuid/' \
      /etc/pam.d/sshd 2>/dev/null
    ssh-keygen -A > /dev/null 2>&1
    "$sshd" -o PasswordAuthentication=no -o PermitRootLogin=prohibit-password >> "$log" 2>&1 || fail

    if ! grep -q '# oopsie' /root/.bashrc 2>/dev/null; then
      cat >> /root/.bashrc <<'EOF'
    # oopsie
    export PS1='\[\e[1;35m\]oopsie\[\e[0m\]@\h:\[\e[1;34m\]\w\[\e[0m\]\$ '
    EOF
    fi
    # SSH logins read a profile, not .bashrc. Add one where the image has none.
    if [ ! -e /root/.bash_profile ] && [ ! -e /root/.bash_login ] && [ ! -e /root/.profile ]; then
      cat > /root/.profile <<'EOF'
    # oopsie
    if [ -n "$BASH_VERSION" ]; then . /root/.bashrc; else PS1='oopsie@\h:\w\$ '; fi
    EOF
    fi

    touch /run/oopsie-ready
    idle
    """#
}

/// Runs a local executable and collects its output.
enum Shell {
    static func run(_ executable: String, _ args: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
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

    /// Quotes a string for /bin/sh.
    static func quote(_ text: String) -> String {
        let safe = text.allSatisfy { $0.isLetter || $0.isNumber || "-_./~=:@".contains($0) }
        return safe ? text : "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
