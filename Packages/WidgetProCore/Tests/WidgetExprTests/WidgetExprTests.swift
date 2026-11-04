import XCTest
@testable import WidgetExpr

final class WidgetExprTests: XCTestCase {

    // MARK: - Helpers

    /// 2023-11-14 22:13:20 UTC, a Tuesday.
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private var context: ExprContext {
        ExprContext(
            now: fixedNow,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            stepLimit: 10_000
        )
    }

    private func eval(_ source: String, _ variables: [String: ExprValue] = [:]) throws -> ExprValue {
        try Expression.parse(source).evaluate(in: ExprScope(variables), context: context)
    }

    private func render(_ source: String, _ variables: [String: ExprValue] = [:]) throws -> ExprValue {
        try Template.parse(source).evaluate(in: ExprScope(variables), context: context)
    }

    private func assertError(
        _ source: String,
        _ variables: [String: ExprValue] = [:],
        contains text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try eval(source, variables), file: file, line: line) { error in
            guard let exprError = error as? ExprError else {
                return XCTFail("Not an ExprError: \(error)", file: file, line: line)
            }
            XCTAssertTrue(
                exprError.message.contains(text),
                "'\(exprError.message)' should contain '\(text)'",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Literals and operators

    func testLiterals() throws {
        XCTAssertEqual(try eval("42"), 42)
        XCTAssertEqual(try eval("3.5"), 3.5)
        XCTAssertEqual(try eval(".5"), 0.5)
        XCTAssertEqual(try eval("'hi'"), "hi")
        XCTAssertEqual(try eval("\"hi\""), "hi")
        XCTAssertEqual(try eval("true"), true)
        XCTAssertEqual(try eval("false"), false)
        XCTAssertEqual(try eval("null"), .null)
    }

    func testStringEscapes() throws {
        XCTAssertEqual(try eval(#"'a\nb'"#), "a\nb")
        XCTAssertEqual(try eval(#"'it\'s'"#), "it's")
        XCTAssertEqual(try eval(#"'tab\there'"#), "tab\there")
    }

    func testArithmeticAndPrecedence() throws {
        XCTAssertEqual(try eval("1.5 + 2"), 3.5)
        XCTAssertEqual(try eval("2 + 3 * 4"), 14)
        XCTAssertEqual(try eval("(2 + 3) * 4"), 20)
        XCTAssertEqual(try eval("10 - 4 - 3"), 3)
        XCTAssertEqual(try eval("10 / 4"), 2.5)
        XCTAssertEqual(try eval("7 % 4"), 3)
        XCTAssertEqual(try eval("-3 + 5"), 2)
        XCTAssertEqual(try eval("2 * -3"), -6)
    }

    func testComparisonsAndLogic() throws {
        XCTAssertEqual(try eval("3 > 2"), true)
        XCTAssertEqual(try eval("3 <= 2"), false)
        XCTAssertEqual(try eval("'a' < 'b'"), true)
        XCTAssertEqual(try eval("1 == 1 && 2 != 3"), true)
        XCTAssertEqual(try eval("1 == 2 || 2 == 2"), true)
        XCTAssertEqual(try eval("!0"), true)
        XCTAssertEqual(try eval("!'x'"), false)
        // && and || return an operand, not just true/false.
        XCTAssertEqual(try eval("0 || 5"), 5)
        XCTAssertEqual(try eval("1 && 'y'"), "y")
        XCTAssertEqual(try eval("false || 'x'"), "x")
    }

    func testShortCircuit() throws {
        // The right side would throw (unknown name) if it were evaluated.
        XCTAssertEqual(try eval("false && nope"), false)
        XCTAssertEqual(try eval("true || nope"), true)
    }

    func testTernary() throws {
        XCTAssertEqual(try eval("x > 3 ? 'big' : 'small'", ["x": 5]), "big")
        XCTAssertEqual(try eval("x > 3 ? 'big' : 'small'", ["x": 1]), "small")
        // Right-associative chain.
        XCTAssertEqual(try eval("a ? 1 : b ? 2 : 3", ["a": false, "b": true]), 2)
        XCTAssertEqual(try eval("a ? 1 : b ? 2 : 3", ["a": false, "b": false]), 3)
    }

    func testStringConcatenation() throws {
        XCTAssertEqual(try eval("'a' + 'b'"), "ab")
        XCTAssertEqual(try eval("'n=' + 5"), "n=5")
        XCTAssertEqual(try eval("5 + 'x'"), "5x")
    }

    // MARK: - Names, members, indexes, null handling

    func testMembersAndIndexes() throws {
        let items: ExprValue = [
            ["name": "a"],
            ["name": "b"]
        ]
        let vars: [String: ExprValue] = ["items": items, "list": [1, 2, 3]]
        XCTAssertEqual(try eval("items[1].name", vars), "b")
        XCTAssertEqual(try eval("items[0]['name']", vars), "a")
        XCTAssertEqual(try eval("list.length", vars), 3)
        XCTAssertEqual(try eval("'hello'.length"), 5)
        XCTAssertEqual(try eval("items[5]", vars), .null)
        XCTAssertEqual(try eval("items[-1]", vars), .null)
    }

    func testNullPropagation() throws {
        let vars: [String: ExprValue] = ["data": .object([:]), "x": .null]
        XCTAssertEqual(try eval("data.missing.deep", vars), .null)
        XCTAssertEqual(try eval("x + 1", vars), .null)
        XCTAssertEqual(try eval("x * 2", vars), .null)
        XCTAssertEqual(try eval("x > 1", vars), false)
        XCTAssertEqual(try eval("x == null", vars), true)
    }

    func testNowIsAvailableByDefault() throws {
        XCTAssertEqual(try eval("now"), .date(fixedNow))
    }

    func testScopeAdding() throws {
        let scope = ExprScope(["a": 1]).adding("b", 2)
        let result = try Expression.parse("a + b").evaluate(in: scope, context: context)
        XCTAssertEqual(result, 3)
    }

    // MARK: - Errors

    func testErrors() {
        assertError("nope", contains: "Unknown name")
        assertError("nope(1)", contains: "Unknown function")
        assertError("(1 + 2", contains: "Expected ')'")
        assertError("1 # 2", contains: "Unexpected character")
        assertError("1 / 0", contains: "Division by zero")
        assertError("5 % 0", contains: "Division by zero")
        assertError("'a' - 1", contains: "Arithmetic needs numbers")
        assertError("'abc", contains: "Unterminated string")
        assertError("1 2", contains: "Unexpected")
        assertError("", contains: "Unexpected end of expression")
        assertError("a.", ["a": .null], contains: "property name")
        assertError("'a' < 1", contains: "Cannot compare")
        assertError("-'a'", contains: "negate")
    }

    func testErrorsCarryAPosition() {
        XCTAssertThrowsError(try Expression.parse("1 # 2")) { error in
            XCTAssertEqual((error as? ExprError)?.offset, 2)
        }
    }

    func testStepLimit() throws {
        let source = Array(repeating: "1", count: 40).joined(separator: "+")
        let expression = try Expression.parse(source)
        XCTAssertNoThrow(try expression.evaluate(in: ExprScope(), context: context))

        let tight = ExprContext(stepLimit: 50)
        XCTAssertThrowsError(try expression.evaluate(in: ExprScope(), context: tight)) { error in
            XCTAssertTrue((error as? ExprError)?.message.contains("too complex") == true)
        }
    }

    func testNestingAndLengthLimits() {
        let deep = String(repeating: "(", count: 200) + "1" + String(repeating: ")", count: 200)
        assertError(deep, contains: "nested too deeply")

        let long = String(repeating: "1+", count: 1500) + "1"
        assertError(long, contains: "too long")
    }

    // MARK: - Functions (one test each)

    func testFunctionFormatNumbers() throws {
        XCTAssertEqual(try eval("format(3.14159, '0.00')"), "3.14")
        XCTAssertEqual(try eval("format(7, '0')"), "7")
        XCTAssertEqual(try eval("format(12.5, '0.0')"), "12.5")
        XCTAssertEqual(try eval("format(1234567.891, '#,##0.0')"), "1,234,567.9")
        XCTAssertEqual(try eval("format(5, '+0.00;-0.00')"), "+5.00")
        XCTAssertEqual(try eval("format(-5, '+0.00;-0.00')"), "-5.00")
        XCTAssertEqual(try eval("format(-5, '0.0')"), "-5.0")
        XCTAssertEqual(try eval("format(-0.001, '0.00')"), "0.00")
        XCTAssertEqual(try eval("format(4.5, '0.0 pts')"), "4.5 pts")
        XCTAssertEqual(try eval("format(null, '0.00')"), "")
        XCTAssertEqual(try eval("format(5, 'abc')"), "5")
        XCTAssertEqual(try eval("format('text', '0.00')"), "text")
    }

    func testFunctionFormatDates() throws {
        let vars: [String: ExprValue] = ["d": .date(fixedNow)]
        XCTAssertEqual(try eval("format(d, 'HH:mm:ss')", vars), "22:13:20")
        XCTAssertEqual(try eval("format(d, 'HH:mm')", vars), "22:13")
        XCTAssertEqual(try eval("format(d, 'h:mm a')", vars), "10:13 PM")
        XCTAssertEqual(try eval("format(d, 'EEEE d MMMM')", vars), "Tuesday 14 November")
    }

    func testFunctionRound() throws {
        XCTAssertEqual(try eval("round(2.5)"), 3)
        XCTAssertEqual(try eval("round(-2.5)"), -3)
        XCTAssertEqual(try eval("round(3.14159, 2)"), 3.14)
        XCTAssertEqual(try eval("round(null)"), .null)
    }

    func testFunctionFloorAndCeil() throws {
        XCTAssertEqual(try eval("floor(2.9)"), 2)
        XCTAssertEqual(try eval("floor(-2.1)"), -3)
        XCTAssertEqual(try eval("ceil(2.1)"), 3)
        XCTAssertEqual(try eval("ceil(-2.9)"), -2)
    }

    func testFunctionClamp() throws {
        XCTAssertEqual(try eval("clamp(15, 0, 10)"), 10)
        XCTAssertEqual(try eval("clamp(-1, 0, 10)"), 0)
        XCTAssertEqual(try eval("clamp(5, 0, 10)"), 5)
    }

    func testFunctionMinAndMax() throws {
        let vars: [String: ExprValue] = ["nums": [4, 2, 8], "empty": .array([])]
        XCTAssertEqual(try eval("min(3, 1, 2)"), 1)
        XCTAssertEqual(try eval("max(3, 1, 2)"), 3)
        XCTAssertEqual(try eval("min(nums)", vars), 2)
        XCTAssertEqual(try eval("max(nums)", vars), 8)
        XCTAssertEqual(try eval("max(empty)", vars), .null)
    }

    func testFunctionSumAndAvg() throws {
        let vars: [String: ExprValue] = ["nums": [1, 2, 3], "pair": [2, 4], "empty": .array([])]
        XCTAssertEqual(try eval("sum(nums)", vars), 6)
        XCTAssertEqual(try eval("sum(empty)", vars), 0)
        XCTAssertEqual(try eval("avg(pair)", vars), 3)
        XCTAssertEqual(try eval("avg(empty)", vars), .null)
    }

    func testFunctionCount() throws {
        let vars: [String: ExprValue] = ["nums": [1, 2, 3], "nothing": .null]
        XCTAssertEqual(try eval("count(nums)", vars), 3)
        XCTAssertEqual(try eval("count('abc')"), 3)
        XCTAssertEqual(try eval("count(nothing)", vars), 0)
    }

    func testFunctionJoin() throws {
        let vars: [String: ExprValue] = ["words": ["a", "b"], "nums": [1, 2, 3], "nothing": .null]
        XCTAssertEqual(try eval("join(words, '-')", vars), "a-b")
        XCTAssertEqual(try eval("join(nums)", vars), "1, 2, 3")
        XCTAssertEqual(try eval("join(nothing, ',')", vars), "")
    }

    private var people: [String: ExprValue] {
        [
            "items": [
                ["name": "a", "active": true, "kind": "x"],
                ["name": "b", "active": false, "kind": "y"],
                ["name": "c", "active": true, "kind": "y"]
            ]
        ]
    }

    func testFunctionMap() throws {
        XCTAssertEqual(try eval("map(items, 'name')", people), ["a", "b", "c"])
        XCTAssertEqual(try eval("map(items, 'missing')", people), [.null, .null, .null])
        XCTAssertEqual(try eval("map(nothing, 'name')", ["nothing": .null]), .array([]))
    }

    func testFunctionFilter() throws {
        XCTAssertEqual(try eval("count(filter(items, 'active'))", people), 2)
        XCTAssertEqual(try eval("map(filter(items, 'kind', 'y'), 'name')", people), ["b", "c"])
        XCTAssertEqual(try eval("filter(nothing, 'x')", ["nothing": .null]), .array([]))
    }

    func testFunctionFirstAndLast() throws {
        let vars: [String: ExprValue] = ["nums": [1, 2, 3], "empty": .array([])]
        XCTAssertEqual(try eval("first(nums)", vars), 1)
        XCTAssertEqual(try eval("last(nums)", vars), 3)
        XCTAssertEqual(try eval("first(empty)", vars), .null)
    }

    func testFunctionUpperAndLower() throws {
        XCTAssertEqual(try eval("upper('abc')"), "ABC")
        XCTAssertEqual(try eval("lower('ABC')"), "abc")
        XCTAssertEqual(try eval("upper(null)"), .null)
    }

    func testFunctionEncode() throws {
        XCTAssertEqual(try eval("encode('AI OR LLM')"), "AI%20OR%20LLM")
        XCTAssertEqual(try eval("encode('a&b=c')"), "a%26b%3Dc")
        XCTAssertEqual(try eval("encode(null)"), "")
    }

    func testFunctionDefault() throws {
        XCTAssertEqual(try eval("default(null, 'x')"), "x")
        XCTAssertEqual(try eval("default('', 'x')"), "x")
        XCTAssertEqual(try eval("default('a', 'x')"), "a")
        XCTAssertEqual(try eval("default(0, 5)"), 0)
    }

    func testFunctionAgo() throws {
        func ago(secondsAgo: Double) throws -> ExprValue {
            let date = fixedNow.addingTimeInterval(-secondsAgo)
            return try eval("ago(d)", ["d": .date(date)])
        }
        XCTAssertEqual(try ago(secondsAgo: 30), "just now")
        XCTAssertEqual(try ago(secondsAgo: 300), "5m ago")
        XCTAssertEqual(try ago(secondsAgo: 3 * 3600), "3h ago")
        XCTAssertEqual(try ago(secondsAgo: 2 * 86_400), "2d ago")
    }

    func testWrongArgumentCounts() {
        assertError("round()", contains: "round()")
        assertError("clamp(1, 2)", contains: "clamp()")
        assertError("format(1)", contains: "format()")
    }

    // MARK: - Templates

    func testTemplateText() throws {
        XCTAssertEqual(try render("plain text"), "plain text")
        XCTAssertEqual(try render(""), "")
        XCTAssertEqual(try render("Hello {{ name }}!", ["name": "Ana"]), "Hello Ana!")
        XCTAssertEqual(try render("{{ a }}{{ b }}", ["a": 1, "b": 2]), "12")
    }

    func testSingleExpressionKeepsItsType() throws {
        XCTAssertEqual(try render("{{ items }}", ["items": [1, 2]]), [1, 2])
        XCTAssertEqual(try render("{{ 3 }}"), 3)
        XCTAssertEqual(try render("{{ x > 1 }}", ["x": 2]), true)
    }

    func testTemplateDisplayStrings() throws {
        XCTAssertEqual(try render("{{ 3 }}%"), "3%")
        XCTAssertEqual(try render("{{ 2.5 }}x"), "2.5x")
        XCTAssertEqual(try render("a{{ x }}b", ["x": .null]), "ab")
        XCTAssertEqual(try render("{{ flag }}", ["flag": true]), true)
        XCTAssertEqual(try render("is {{ flag }}", ["flag": true]), "is true")
    }

    func testTemplateBracesInsideStrings() throws {
        XCTAssertEqual(try render("{{ '}}' }}"), "}}")
    }

    func testTemplateErrors() {
        XCTAssertThrowsError(try Template.parse("{{ x")) { error in
            XCTAssertTrue((error as? ExprError)?.message.contains("Unclosed") == true)
        }
        XCTAssertThrowsError(try Template.parse("{{ }}"))
        XCTAssertThrowsError(try Template.parse("{{ 1 + }}"))
    }

    func testTemplateIsConstant() throws {
        XCTAssertTrue(try Template.parse("just text").isConstant)
        XCTAssertFalse(try Template.parse("a {{ b }}").isConstant)
    }

    // MARK: - Expressions taken from the example widgets

    func testClockExpressions() throws {
        let pattern = """
        {{ format(data.now.date, settings.hour24 ? (settings.showSeconds ? 'HH:mm:ss' : 'HH:mm') : (settings.showSeconds ? 'h:mm:ss a' : 'h:mm a')) }}
        """
        func vars(hour24: Bool, seconds: Bool) -> [String: ExprValue] {
            [
                "data": .object(["now": .object(["date": .date(fixedNow)])]),
                "settings": .object(["hour24": .bool(hour24), "showSeconds": .bool(seconds)])
            ]
        }
        XCTAssertEqual(try render(pattern, vars(hour24: true, seconds: false)), "22:13")
        XCTAssertEqual(try render(pattern, vars(hour24: true, seconds: true)), "22:13:20")
        XCTAssertEqual(try render(pattern, vars(hour24: false, seconds: false)), "10:13 PM")
        XCTAssertEqual(try render(pattern, vars(hour24: false, seconds: true)), "10:13:20 PM")

        let refresh = "{{ settings.showSeconds ? '1s' : '30s' }}"
        XCTAssertEqual(try render(refresh, vars(hour24: true, seconds: true)), "1s")
        XCTAssertEqual(try render(refresh, vars(hour24: true, seconds: false)), "30s")
    }

    func testMarketsExpressions() throws {
        let vars: [String: ExprValue] = [
            "q": ["symbol": "AAPL", "price": 189.456, "changePct": 1.234],
            "symbol": "AAPL",
            "secrets": ["apiKey": "k123"]
        ]
        XCTAssertEqual(try render("{{ format(q.changePct, '+0.00;-0.00') }}%", vars), "+1.23%")
        XCTAssertEqual(try render("{{ q.changePct >= 0 ? 'positive' : 'negative' }}", vars), "positive")
        XCTAssertEqual(
            try render("https://finnhub.io/api/v1/quote?symbol={{ symbol }}&token={{ secrets.apiKey }}", vars),
            "https://finnhub.io/api/v1/quote?symbol=AAPL&token=k123"
        )
        // Before any data has loaded the widget must not throw.
        let empty: [String: ExprValue] = ["data": ["quotes": .array([])]]
        XCTAssertEqual(try render("{{ format(data.quotes[0].price, '0.00') }}", empty), "")
        XCTAssertEqual(
            try render("{{ data.quotes[0].changePct >= 0 ? 'positive' : 'negative' }}", empty),
            "negative"
        )
    }

    func testAINewsExpressions() throws {
        let vars: [String: ExprValue] = [
            "settings": ["query": "AI OR LLM", "minPoints": 100, "briefing": true],
            "data": [
                "stories": [["title": "First"], ["title": "Second"]],
                "summary": .null
            ]
        ]
        XCTAssertEqual(
            try render(
                "https://hnrss.org/newest?q={{ encode(settings.query) }}&points={{ settings.minPoints }}",
                vars
            ),
            "https://hnrss.org/newest?q=AI%20OR%20LLM&points=100"
        )
        XCTAssertEqual(
            try render(#"{{ join(map(data.stories, 'title'), '\n') }}"#, vars),
            "First\nSecond"
        )
        // The briefing section stays hidden until the AI summary exists.
        let when = try render("{{ settings.briefing && data.summary }}", vars)
        XCTAssertFalse(when.isTruthy)
    }

    // MARK: - Every {{ }} in the example widget files must parse

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
            domain: "WidgetExprTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not find the Examples folder"]
        )
    }

    private func strings(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let array = value as? [Any] { return array.flatMap { strings(in: $0) } }
        if let object = value as? [String: Any] { return object.values.flatMap { strings(in: $0) } }
        return []
    }

    func testAllExampleTemplatesParse() throws {
        let directory = try examplesDirectory()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".widget.json") }
        XCTAssertGreaterThanOrEqual(files.count, 3)

        var checked = 0
        for file in files {
            let data = try Data(contentsOf: directory.appendingPathComponent(file))
            let json = try JSONSerialization.jsonObject(with: data)
            for text in strings(in: json) where text.contains("{{") {
                XCTAssertNoThrow(try Template.parse(text), "\(file): \(text)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 20)
    }
}
