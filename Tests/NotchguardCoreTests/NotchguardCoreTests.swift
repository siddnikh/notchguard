import XCTest
import Foundation
@testable import NotchguardCore

final class NotchguardCoreTests: XCTestCase {
    func testBuiltInParserFindsApproval() {
        let event = BuiltInOutputParser().parse(line: "\u{001B}[33mDo you want to proceed with this command?\u{001B}[0m")
        XCTAssertEqual(event?.kind, .approvalRequired)
        XCTAssertEqual(event?.summary, "Do you want to proceed with this command?")
        XCTAssertEqual(
            BuiltInOutputParser().parse(line: "Choose how you'd like Codex to proceed.")?.kind,
            .approvalRequired
        )
        XCTAssertEqual(
            BuiltInOutputParser().parse(line: "Do you want to allow Claude to fetch this content?")?.kind,
            .approvalRequired
        )
        XCTAssertEqual(
            BuiltInOutputParser().parse(line: "Use skill \"release-check\"?")?.kind,
            .approvalRequired
        )
    }

    func testBuiltInParserLeavesNormalOutputAlone() {
        XCTAssertNil(BuiltInOutputParser().parse(line: "Reading package manifest"))
        XCTAssertNil(BuiltInOutputParser().parse(line: "I approve of this implementation."))
        XCTAssertNil(BuiltInOutputParser().parse(line: "The task completed successfully in CI."))
    }

    func testTerminalTextRemovesANSIControlsAndBackspaces() {
        XCTAssertEqual(
            TerminalText.clean("\u{001B}[1mWait\u{001B}[0m\tfor itt\u{8}."),
            "Wait for it."
        )
    }

    func testTerminalOutputBufferHandlesPTYCarriageReturns() {
        var buffer = TerminalOutputBuffer()
        XCTAssertEqual(buffer.append("first\rsecond"), ["first"])
        XCTAssertEqual(buffer.append(" half\nthird"), ["second half"])
        XCTAssertEqual(buffer.flush(), "third")
    }

    func testEventGateSuppressesRedrawSpam() {
        let gate = EventGate(cooldown: 4)
        let event = AgentEvent(kind: .approvalRequired, summary: "Approve?")
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(gate.shouldDeliver(event, now: start))
        XCTAssertFalse(gate.shouldDeliver(event, now: start.addingTimeInterval(3)))
        XCTAssertTrue(gate.shouldDeliver(event, now: start.addingTimeInterval(4)))
    }

    func testPluginParserUsesConfiguredRegex() throws {
        let parser = try PluginOutputParser(manifest: .init(
            identifier: "example.review",
            name: "Review prompt",
            version: "1.0.0",
            rules: [.init(pattern: "REVIEW_NEEDED", event: .inputRequired, summary: "Review needed")]
        ))
        XCTAssertEqual(parser.parse(line: "\u{001B}[31mREVIEW_NEEDED\u{001B}[0m: docs")?.summary, "Review needed")
        XCTAssertNil(parser.parse(line: "ordinary output"))
    }

    func testPluginManifestRoundTrips() throws {
        let manifest = PluginManifest(
            identifier: "example.review",
            name: "Review prompt",
            version: "1.0.0",
            rules: [.init(pattern: "review", event: .inputRequired)]
        )
        let decoded = try JSONDecoder().decode(PluginManifest.self, from: JSONEncoder().encode(manifest))
        XCTAssertEqual(decoded, manifest)
    }

    func testPluginRejectsEmptyRules() {
        let manifest = PluginManifest(identifier: "example.empty", name: "Empty", version: "1.0.0", rules: [])
        XCTAssertThrowsError(try PluginOutputParser(manifest: manifest))
    }

    func testOverlayPayloadRoundTripsSessionContext() throws {
        let payload = OverlayPayload(
            event: AgentEvent(kind: .completed, summary: "Done"),
            session: AgentSession(
                agentName: "Claude",
                workingDirectory: URL(fileURLWithPath: "/tmp/project"),
                terminalTTY: "/dev/ttys001"
            )
        )
        XCTAssertEqual(try OverlayPayload.decode(payload.encoded()), payload)
    }

    func testMonitorReportsExitBasedCompletion() throws {
        let delivered = LockedEvents()
        let monitor = AgentMonitor(parser: BuiltInOutputParser()) { event, _ in
            delivered.append(event)
        }
        XCTAssertEqual(try monitor.run(command: "/bin/sh", arguments: ["-c", "exit 0"]), 0)
        XCTAssertEqual(delivered.values.last?.kind, .completed)
    }

    func testUpdaterRecognizesUniversalMachOHeader() throws {
        // This executes no network request: the public updater validates its
        // downloaded bytes before replacing an installed binary.
        XCTAssertTrue(SelfUpdater.isMachO(Data([0xCA, 0xFE, 0xBA, 0xBF])))
        XCTAssertFalse(SelfUpdater.isMachO(Data("not a binary".utf8)))
    }
}

private final class LockedEvents: @unchecked Sendable {
    private var events: [AgentEvent] = []
    private let lock = NSLock()

    var values: [AgentEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func append(_ event: AgentEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }
}
