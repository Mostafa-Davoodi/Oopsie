// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import Oopsie

final class ParseListTests: XCTestCase {
    func testCurrentFormatWithStatusObject() throws {
        // The shape `scripts/fake-container list` prints.
        let json = #"""
        [{"status":{"state":"running","networks":[{"ipv4Address":"192.168.64.3/24"}]},"configuration":{"id":"oopsie-1a2b"}},
         {"status":{"state":"stopped","networks":[]},"configuration":{"id":"oopsie-77f0"}}]
        """#
        let machines = try XCTUnwrap(ContainerCLI.parseList(json))
        XCTAssertEqual(machines, [
            Machine(id: "oopsie-1a2b", isRunning: true, state: "running", ip: "192.168.64.3"),
            Machine(id: "oopsie-77f0", isRunning: false, state: "stopped", ip: nil),
        ])
    }

    func testOlderFormatWithStatusStringAndAddressKey() throws {
        let json = #"[{"id":"oopsie-00ff","status":"Running","networks":[{"address":"192.168.64.9/24"}]}]"#
        let machines = try XCTUnwrap(ContainerCLI.parseList(json))
        XCTAssertEqual(machines, [
            Machine(id: "oopsie-00ff", isRunning: true, state: "running", ip: "192.168.64.9"),
        ])
    }

    func testStateAtTopLevel() throws {
        let json = #"[{"id":"oopsie-0001","state":"stopped"}]"#
        let machines = try XCTUnwrap(ContainerCLI.parseList(json))
        XCTAssertEqual(machines.first?.state, "stopped")
        XCTAssertEqual(machines.first?.isRunning, false)
    }

    func testMissingStateIsUnknown() throws {
        let json = #"[{"id":"oopsie-0002"}]"#
        let machines = try XCTUnwrap(ContainerCLI.parseList(json))
        XCTAssertEqual(machines.first?.state, "unknown")
        XCTAssertEqual(machines.first?.isRunning, false)
    }

    func testIgnoresContainersOopsieDidNotMake() throws {
        let json = #"""
        [{"configuration":{"id":"postgres"},"status":"running"},
         {"configuration":{"id":"oopsie-aaaa"},"status":"running"}]
        """#
        let machines = try XCTUnwrap(ContainerCLI.parseList(json))
        XCTAssertEqual(machines.map(\.id), ["oopsie-aaaa"])
    }

    func testSortsByName() throws {
        let json = #"[{"id":"oopsie-ffff","status":"stopped"},{"id":"oopsie-0000","status":"stopped"}]"#
        let machines = try XCTUnwrap(ContainerCLI.parseList(json))
        XCTAssertEqual(machines.map(\.id), ["oopsie-0000", "oopsie-ffff"])
    }

    func testIgnoresAddressesInsideConfiguration() throws {
        // The configuration can mention addresses that aren't the machine's own IP.
        let json = #"[{"configuration":{"id":"oopsie-cafe","networks":[{"address":"10.0.0.5/24"}]},"status":"stopped"}]"#
        let machines = try XCTUnwrap(ContainerCLI.parseList(json))
        XCTAssertNil(machines.first?.ip)
    }

    func testEmptyList() {
        XCTAssertEqual(ContainerCLI.parseList("[]"), [])
    }

    func testInvalidJSONReturnsNil() {
        XCTAssertNil(ContainerCLI.parseList("not json"))
        XCTAssertNil(ContainerCLI.parseList(#"{"id":"oopsie-1234"}"#))
        XCTAssertNil(ContainerCLI.parseList(""))
    }
}

final class FindIPv4Tests: XCTestCase {
    func testStripsPrefixLength() {
        let value: [String: Any] = ["ipv4Address": "192.168.64.3/24"]
        XCTAssertEqual(ContainerCLI.findIPv4(in: value), "192.168.64.3")
    }

    func testAcceptsAddressWithoutPrefixLength() {
        let value: [String: Any] = ["address": "192.168.64.3"]
        XCTAssertEqual(ContainerCLI.findIPv4(in: value), "192.168.64.3")
    }

    func testFindsNestedAddress() {
        let value: [String: Any] = ["status": ["networks": [["ipv4Address": "10.0.0.2/16"]]]]
        XCTAssertEqual(ContainerCLI.findIPv4(in: value), "10.0.0.2")
    }

    func testRejectsIPv6() {
        let value: [String: Any] = ["address": "fe80::1/64"]
        XCTAssertNil(ContainerCLI.findIPv4(in: value))
    }

    func testRejectsInvalidIPv4() {
        XCTAssertNil(ContainerCLI.findIPv4(in: ["ipv4Address": "300.1.1.1/24"] as [String: Any]))
        XCTAssertNil(ContainerCLI.findIPv4(in: ["ipv4Address": "192.168.64"] as [String: Any]))
        XCTAssertNil(ContainerCLI.findIPv4(in: ["ipv4Address": "a.b.c.d"] as [String: Any]))
    }

    func testNoAddress() {
        XCTAssertNil(ContainerCLI.findIPv4(in: ["state": "running"] as [String: Any]))
        XCTAssertNil(ContainerCLI.findIPv4(in: [Any]()))
    }
}

final class MachineNameTests: XCTestCase {
    func testNewMachineNameIsPrefixDistroAndFourHexDigits() {
        for distro in Distro.all {
            for _ in 0..<50 {
                let name = ContainerCLI.newMachineName(for: distro)
                let start = ContainerCLI.namePrefix + distro.id + "-"
                XCTAssertTrue(name.hasPrefix(start), name)
                let suffix = name.dropFirst(start.count)
                XCTAssertEqual(suffix.count, 4, name)
                XCTAssertTrue(suffix.allSatisfy(\.isHexDigit), name)
            }
        }
    }

    func testNewMachineNameReadsBackAsItsDistro() {
        for distro in Distro.all {
            XCTAssertEqual(Distro.of(machine: ContainerCLI.newMachineName(for: distro)), distro)
        }
    }
}

final class DistroTests: XCTestCase {
    func testIDsAreUniqueAndFitInAMachineName() {
        let ids = Distro.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids {
            XCTAssertFalse(id.isEmpty)
            XCTAssertTrue(id.allSatisfy { $0.isLowercase || $0.isNumber }, id)
        }
    }

    func testDefaultIsUbuntu() {
        XCTAssertEqual(Distro.default, .ubuntu)
        XCTAssertTrue(Distro.all.contains(.default))
    }

    func testWithID() {
        XCTAssertEqual(Distro.withID("arch"), .arch)
        XCTAssertNil(Distro.withID("gentoo"))
    }

    func testOnlyX86ImagesUseRosetta() {
        XCTAssertTrue(Distro.arch.usesRosetta)
        XCTAssertTrue(Distro.cachyos.usesRosetta)
        XCTAssertFalse(Distro.ubuntu.usesRosetta)
        XCTAssertFalse(Distro.alpine.usesRosetta)
        for distro in Distro.all {
            XCTAssertTrue(["arm64", "amd64"].contains(distro.arch), distro.id)
        }
    }

    func testMachineNameWithoutDistroIsUbuntu() {
        // Machines made before Oopsie had distros.
        XCTAssertEqual(Distro.of(machine: "oopsie-1a2b"), .ubuntu)
    }

    func testMachineNameWithDistro() {
        XCTAssertEqual(Distro.of(machine: "oopsie-fedora-00ff"), .fedora)
        XCTAssertEqual(Distro.of(machine: "oopsie-cachyos-beef"), .cachyos)
    }

    func testUnknownMachineNames() {
        XCTAssertNil(Distro.of(machine: "oopsie-gentoo-1a2b"))
        XCTAssertNil(Distro.of(machine: "oopsie-a-b-c"))
        XCTAssertNil(Distro.of(machine: "postgres"))
    }

    func testMachineKnowsItsDistro() {
        let machine = Machine(id: "oopsie-alpine-0001", isRunning: false, state: "stopped", ip: nil)
        XCTAssertEqual(machine.distro, .alpine)
    }
}

final class CreateArgumentsTests: XCTestCase {
    func testNativeDistroHasNoArchFlag() {
        let args = ContainerCLI.createArguments(named: "oopsie-debian-0001", distro: .debian, authorizedKeys: "key\n")
        XCTAssertFalse(args.contains("--arch"))
        XCTAssertEqual(Array(args.prefix(4)), ["run", "--detach", "--name", "oopsie-debian-0001"])
        XCTAssertEqual(Array(args.suffix(4)), [Distro.debian.image, "sh", "-c", ContainerCLI.setupScript])
    }

    func testX86DistroRunsWithRosetta() throws {
        let args = ContainerCLI.createArguments(named: "oopsie-arch-0001", distro: .arch, authorizedKeys: "key\n")
        let index = try XCTUnwrap(args.firstIndex(of: "--arch"))
        XCTAssertEqual(args[index + 1], "amd64")
        XCTAssertTrue(args.contains(Distro.arch.image))
    }

    func testKeysAreBase64AndMountIsAdded() {
        let args = ContainerCLI.createArguments(named: "oopsie-ubuntu-0001", distro: .ubuntu, authorizedKeys: "ssh-ed25519 AAAA\n",
                                                mount: (host: "/Users/me/My Project", machine: "/root/My-Project"))
        XCTAssertTrue(args.contains("OOPSIE_KEYS=" + Data("ssh-ed25519 AAAA\n".utf8).base64EncodedString()))
        XCTAssertTrue(args.contains("/Users/me/My Project:/root/My-Project"))
    }

    func testSetupScriptKnowsEveryPackageManager() {
        for tool in ["apt-get", "dnf", "pacman", "apk", "zypper"] {
            XCTAssertTrue(ContainerCLI.setupScript.contains("command -v \(tool)"), tool)
        }
    }

    func testRootShellFallsBackToSh() {
        let command = ContainerCLI.shellCommand(for: "oopsie-alpine-0001")
        // Nil on machines without the container CLI, like CI.
        if let command {
            XCTAssertTrue(command.contains("exec bash || exec sh"), command)
        }
    }
}

final class CommandResultTests: XCTestCase {
    func testSummaryPrefersStderr() {
        let result = CommandResult(status: 1, stdout: "some output", stderr: "  Error: no such image  \n")
        XCTAssertEqual(result.summary, "Error: no such image")
    }

    func testSummaryUsesLastNonEmptyStdoutLine() {
        let result = CommandResult(status: 1, stdout: "first\nlast\n\n", stderr: "")
        XCTAssertEqual(result.summary, "last")
    }

    func testSummaryFallsBackToExitCode() {
        let result = CommandResult(status: 3, stdout: "", stderr: "")
        XCTAssertEqual(result.summary, "exit code 3")
        XCTAssertFalse(result.ok)
    }
}

final class ShellQuoteTests: XCTestCase {
    func testSafeTextIsUnchanged() {
        XCTAssertEqual(Shell.quote("/opt/homebrew/bin/container"), "/opt/homebrew/bin/container")
        XCTAssertEqual(Shell.quote("oopsie-1a2b"), "oopsie-1a2b")
    }

    func testSpacesAreQuoted() {
        XCTAssertEqual(Shell.quote("/Users/me/My Folder"), "'/Users/me/My Folder'")
    }

    func testSingleQuotesAreEscaped() {
        XCTAssertEqual(Shell.quote("it's"), #"'it'\''s'"#)
    }

    func testShellCharactersAreQuoted() {
        XCTAssertEqual(Shell.quote("a;rm -rf ~"), "'a;rm -rf ~'")
        XCTAssertEqual(Shell.quote("$(whoami)"), "'$(whoami)'")
    }
}

@MainActor
final class SafeNameTests: XCTestCase {
    func testReplacesUnsafeCharacters() {
        XCTAssertEqual(OopsieStore.safeName("My Project"), "My-Project")
        XCTAssertEqual(OopsieStore.safeName("a/b"), "a-b")
    }

    func testKeepsSafeCharacters() {
        XCTAssertEqual(OopsieStore.safeName("app_v1.2-beta"), "app_v1.2-beta")
        XCTAssertEqual(OopsieStore.safeName("café"), "café")
    }

    func testFallsBackToSharedWhenNothingIsLeft() {
        XCTAssertEqual(OopsieStore.safeName(""), "shared")
        XCTAssertEqual(OopsieStore.safeName("..."), "shared")
        XCTAssertEqual(OopsieStore.safeName("---"), "shared")
        XCTAssertEqual(OopsieStore.safeName("   "), "shared")
    }
}
