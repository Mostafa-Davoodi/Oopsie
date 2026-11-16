// SPDX-License-Identifier: Apache-2.0

/// A Linux distribution that Oopsie can make machines from.
struct Distro: Equatable, Identifiable {
    /// Short name. It is also part of the machine name: `oopsie-<id>-1a2b`. No "-" allowed.
    let id: String
    /// Name shown in the menu.
    let name: String
    let image: String
    /// CPU architecture of the image. Apple silicon runs "arm64" natively and "amd64" with Rosetta.
    let arch: String

    /// True when the machine runs x86-64 code through Rosetta (slower than native).
    var usesRosetta: Bool { arch == "amd64" }

    static let ubuntu = Distro(id: "ubuntu", name: "Ubuntu", image: "docker.io/library/ubuntu:latest", arch: "arm64")
    static let debian = Distro(id: "debian", name: "Debian", image: "docker.io/library/debian:latest", arch: "arm64")
    static let fedora = Distro(id: "fedora", name: "Fedora", image: "docker.io/library/fedora:latest", arch: "arm64")
    static let alpine = Distro(id: "alpine", name: "Alpine", image: "docker.io/library/alpine:latest", arch: "arm64")
    // Arch Linux and CachyOS only publish x86-64 images.
    static let arch = Distro(id: "arch", name: "Arch Linux", image: "docker.io/library/archlinux:latest", arch: "amd64")
    static let cachyos = Distro(id: "cachyos", name: "CachyOS", image: "docker.io/cachyos/cachyos:latest", arch: "amd64")

    /// In menu order.
    static let all: [Distro] = [ubuntu, debian, fedora, alpine, arch, cachyos]
    static let `default` = ubuntu

    static func withID(_ id: String) -> Distro? {
        all.first { $0.id == id }
    }

    /// The distro a machine was made from, read from its name.
    /// `oopsie-1a2b` is from before Oopsie had distros, so it is Ubuntu.
    /// Returns nil for a distro this version of Oopsie doesn't know.
    static func of(machine name: String) -> Distro? {
        guard name.hasPrefix(ContainerCLI.namePrefix) else { return nil }
        let parts = name.dropFirst(ContainerCLI.namePrefix.count).split(separator: "-", omittingEmptySubsequences: false)
        switch parts.count {
        case 1: return .ubuntu
        case 2: return withID(String(parts[0]))
        default: return nil
        }
    }
}
