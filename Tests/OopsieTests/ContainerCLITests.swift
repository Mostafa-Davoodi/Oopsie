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
    func testNewMachineNameIsPrefixAndFourHexDigits() {
        for _ in 0..<200 {
            let name = ContainerCLI.newMachineName()
            XCTAssertTrue(name.hasPrefix(ContainerCLI.namePrefix), name)
            let suffix = name.dropFirst(ContainerCLI.namePrefix.count)
            XCTAssertEqual(suffix.count, 4, name)
            XCTAssertTrue(suffix.allSatisfy(\.isHexDigit), name)
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
