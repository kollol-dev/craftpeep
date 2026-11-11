import XCTest
@testable import WidgetSpec

final class WidgetSpecTests: XCTestCase {

    // MARK: - Helpers

    /// Walks up from this file until it finds an `Examples` folder.
    /// Works whether the package sits at the repo root or in Packages/CraftPeepKit.
    private func examplesDirectory(from file: String = #filePath) throws -> URL {
        var directory = URL(fileURLWithPath: file).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("Examples")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "WidgetSpecTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not find the Examples folder"]
        )
    }

    private func loadExample(_ fileName: String) throws -> WidgetDefinition {
        let url = try examplesDirectory().appendingPathComponent(fileName)
        return try WidgetSpecLoader.load(from: url)
    }

    private func decode(_ json: String) throws -> WidgetDefinition {
        try WidgetSpecLoader.decode(Data(json.utf8))
    }

    private func minimalSpec(
        spec: String = "0.1",
        extra: String = "",
        view: String = #"{"default":{"type":"text","text":"hi"}}"#
    ) -> String {
        """
        {"spec":"\(spec)","id":"com.test.widget","name":"Test","version":"1.0.0"\(extra),"view":\(view)}
        """
    }

    // MARK: - Basics

    func testSpecVersion() {
        XCTAssertEqual(WidgetSpecInfo.version, "0.2")
        XCTAssertEqual(WidgetSpecInfo.supportedVersions, ["0.1", "0.2"])
    }

    func testMinimalSpecDecodes() throws {
        let widget = try decode(minimalSpec())
        XCTAssertEqual(widget.id, "com.test.widget")
        XCTAssertEqual(widget.view["default"]?.type, .text)
    }

    // MARK: - Example files

    func testAllExamplesDecodeAndValidate() throws {
        let directory = try examplesDirectory()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".widget.json") }
        XCTAssertGreaterThanOrEqual(files.count, 3)
        for file in files {
            XCTAssertNoThrow(try loadExample(file), "\(file) should decode and validate")
        }
    }

    func testClockExample() throws {
        let widget = try loadExample("clock.widget.json")
        XCTAssertEqual(widget.id, "com.craftpeep.clock")
        XCTAssertEqual(widget.settings?.count, 2)
        XCTAssertEqual(widget.data?["now"]?.type, .time)
        XCTAssertEqual(widget.view["default"]?.type, .vstack)
        XCTAssertEqual(widget.view["default"]?.children?.count, 2)
    }

    func testMarketsExample() throws {
        let widget = try loadExample("markets.widget.json")
        XCTAssertEqual(widget.permissions?.network, ["finnhub.io"])
        XCTAssertEqual(widget.settings?.last?.type, .secret)

        let quotes = try XCTUnwrap(widget.data?["quotes"])
        XCTAssertEqual(quotes.type, .http)
        XCTAssertEqual(quotes.loopVariable, "symbol")
        XCTAssertEqual(quotes.map?["price"], "{{ response.c }}")

        let list = try XCTUnwrap(widget.view["default"]?.children?.last)
        XCTAssertEqual(list.type, .list)
        XCTAssertEqual(list.loopVariable, "q")
        XCTAssertEqual(list.item?.value.type, .hstack)
    }

    func testAINewsExample() throws {
        let widget = try loadExample("ai-news.widget.json")
        XCTAssertEqual(widget.permissions?.ai, true)
        XCTAssertEqual(widget.data?["stories"]?.type, .rss)
        XCTAssertEqual(widget.data?["summary"]?.type, .ai)
        XCTAssertEqual(widget.data?["summary"]?.maxTokens, 120)
        XCTAssertNotNil(widget.view["large"])
    }

    // MARK: - Rejection cases

    func testRejectsMalformedJSON() {
        XCTAssertThrowsError(try decode("{ not json")) { error in
            guard case WidgetSpecError.malformed = error else {
                return XCTFail("Expected .malformed, got \(error)")
            }
        }
    }

    func testRejectsMissingSpecField() {
        XCTAssertThrowsError(try decode(#"{"id":"com.test.w"}"#)) { error in
            guard case WidgetSpecError.invalid(let issues) = error else {
                return XCTFail("Expected .invalid, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.contains("spec") })
        }
    }

    func testRejectsNewerSpecVersion() {
        XCTAssertThrowsError(try decode(minimalSpec(spec: "0.9"))) { error in
            guard case WidgetSpecError.unsupportedSpecVersion(let found, let supported) = error else {
                return XCTFail("Expected .unsupportedSpecVersion, got \(error)")
            }
            XCTAssertEqual(found, "0.9")
            XCTAssertEqual(supported, "0.2")
        }
    }

    func testRejectsMissingDefaultView() {
        let json = minimalSpec(view: #"{"small":{"type":"text","text":"hi"}}"#)
        XCTAssertThrowsError(try decode(json)) { error in
            guard case WidgetSpecError.invalid(let issues) = error else {
                return XCTFail("Expected .invalid, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.contains("'default'") })
        }
    }

    func testRejectsUnknownComponentType() {
        let json = minimalSpec(view: #"{"default":{"type":"banana"}}"#)
        XCTAssertThrowsError(try decode(json)) { error in
            guard case WidgetSpecError.malformed = error else {
                return XCTFail("Expected .malformed, got \(error)")
            }
        }
    }

    func testRejectsBadIdAndVersion() {
        let json = #"{"spec":"0.1","id":"Bad Id","name":"T","version":"one","view":{"default":{"type":"text"}}}"#
        XCTAssertThrowsError(try decode(json)) { error in
            guard case WidgetSpecError.invalid(let issues) = error else {
                return XCTFail("Expected .invalid, got \(error)")
            }
            XCTAssertEqual(issues.count, 2)
        }
    }

    func testRejectsHostMissingFromPermissions() {
        let extra = #","data":{"feed":{"type":"rss","url":"https://example.com/feed"}}"#
        XCTAssertThrowsError(try decode(minimalSpec(extra: extra))) { error in
            guard case WidgetSpecError.invalid(let issues) = error else {
                return XCTFail("Expected .invalid, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.contains("example.com") })
        }
    }

    func testAcceptsHostListedInPermissions() throws {
        let extra = #","permissions":{"network":["example.com"]},"data":{"feed":{"type":"rss","url":"https://example.com/feed"}}"#
        XCTAssertNoThrow(try decode(minimalSpec(extra: extra)))
    }

    func testRejectsAISourceWithoutPermission() {
        let extra = #","data":{"s":{"type":"ai","prompt":"Summarise"}}"#
        XCTAssertThrowsError(try decode(minimalSpec(extra: extra))) { error in
            guard case WidgetSpecError.invalid(let issues) = error else {
                return XCTFail("Expected .invalid, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.contains("permissions.ai") })
        }
    }

    func testRejectsListWithoutItem() {
        let json = minimalSpec(view: #"{"default":{"type":"list","each":"{{ data.x }}"}}"#)
        XCTAssertThrowsError(try decode(json)) { error in
            guard case WidgetSpecError.invalid(let issues) = error else {
                return XCTFail("Expected .invalid, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.contains("'item'") })
        }
    }

    func testRejectsDuplicateSettingKeys() {
        let extra = #","settings":[{"key":"a","type":"string","label":"A"},{"key":"a","type":"number","label":"B"}]"#
        XCTAssertThrowsError(try decode(minimalSpec(extra: extra))) { error in
            guard case WidgetSpecError.invalid(let issues) = error else {
                return XCTFail("Expected .invalid, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.contains("duplicate") })
        }
    }

    // MARK: - Spec 0.2

    private func querySpec(spec: String = "0.2", source: String) -> String {
        minimalSpec(spec: spec, extra: #","data":{"stories":\#(source)}"#)
    }

    private func issues(_ json: String) -> [String] {
        do {
            _ = try decode(json)
            return []
        } catch WidgetSpecError.invalid(let issues) {
            return issues
        } catch {
            return ["unexpected error: \(error)"]
        }
    }

    func testQuerySourceDecodesAndNeedsNoPermissions() throws {
        let widget = try decode(querySpec(source: #"{"type":"query","from":"stories","where":{"subject":"{{ settings.subject }}","kinds":["shipping"],"entities":["Swift"],"sinceHours":48,"saved":false},"sort":"latest","limit":5}"#))
        let source = try XCTUnwrap(widget.data?["stories"])
        XCTAssertEqual(source.type, .query)
        XCTAssertEqual(source.from, "stories")
        XCTAssertEqual(source.sort, "latest")
        XCTAssertEqual(source.filter?.kinds, ["shipping"])
        XCTAssertEqual(source.filter?.sinceHours, 48)
        XCTAssertNil(widget.permissions)
    }

    func testQuerySourceIsRejectedInSpec01() {
        XCTAssertTrue(issues(querySpec(spec: "0.1", source: #"{"type":"query","from":"stories"}"#)).contains { $0.contains("spec 0.2") })
    }

    func testQuerySourceRulesAreEnforced() {
        func problems(_ source: String) -> String { issues(querySpec(source: source)).joined(separator: "\n") }
        XCTAssertTrue(problems(#"{"type":"query","from":"articles"}"#).contains("'from' must be"))
        XCTAssertTrue(problems(#"{"type":"query"}"#).contains("'from' must be"))
        XCTAssertTrue(problems(#"{"type":"query","from":"stories","sort":"random"}"#).contains("sort must be"))
        XCTAssertTrue(problems(#"{"type":"query","from":"stories","limit":500}"#).contains("limit must be"))
        XCTAssertTrue(problems(#"{"type":"query","from":"stories","where":{"sinceHours":0}}"#).contains("sinceHours"))
        XCTAssertTrue(problems(#"{"type":"query","from":"stories","where":{"kinds":["gossip"]}}"#).contains("unknown kind 'gossip'"))
        XCTAssertTrue(problems(#"{"type":"query","from":"stories","where":{"subject":"sports"}}"#).contains("unknown subject"))
    }

    func testCommandAndFilePermissionsAreRefused() {
        let commands = issues(minimalSpec(extra: #","permissions":{"commands":true}"#))
        XCTAssertTrue(commands.contains { $0.contains("cannot run commands") })
        // Asking for it switched off is still asking for something that does not exist.
        XCTAssertTrue(issues(minimalSpec(extra: #","permissions":{"commands":false}"#)).contains { $0.contains("commands") })
        let files = issues(minimalSpec(spec: "0.2", extra: #","permissions":{"files":["~/Documents"]}"#))
        XCTAssertTrue(files.contains { $0.contains("cannot read files") })
    }
}
