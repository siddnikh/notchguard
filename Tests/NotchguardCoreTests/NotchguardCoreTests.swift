import XCTest
@testable import NotchguardCore

final class NotchguardCoreTests: XCTestCase {
    func testBuiltInParserFindsApproval() {
        let event = BuiltInOutputParser().parse(line: "Do you want to proceed with this command?")
        XCTAssertEqual(event?.kind, .approvalRequired)
    }

    func testBuiltInParserLeavesNormalOutputAlone() {
        XCTAssertNil(BuiltInOutputParser().parse(line: "Reading package manifest"))
    }

    func testPluginParserUsesConfiguredRegex() throws {
        let parser = try PluginOutputParser(manifest: .init(
            identifier: "example.review",
            name: "Review prompt",
            version: "1.0.0",
            rules: [.init(pattern: "REVIEW_NEEDED", event: .inputRequired, summary: "Review needed")]
        ))
        XCTAssertEqual(parser.parse(line: "REVIEW_NEEDED: docs")?.summary, "Review needed")
        XCTAssertNil(parser.parse(line: "ordinary output"))
    }

    func testPluginManifestRoundTrips() throws {
        let manifest = PluginManifest(identifier: "example.review", name: "Review prompt", version: "1.0.0", rules: [])
        let decoded = try JSONDecoder().decode(PluginManifest.self, from: JSONEncoder().encode(manifest))
        XCTAssertEqual(decoded, manifest)
    }
}

