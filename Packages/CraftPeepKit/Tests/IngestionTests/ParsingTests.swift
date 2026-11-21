import Domain
import Foundation
import Testing
@testable import Ingestion

func fixture(_ name: String) throws -> Data {
    let parts = name.split(separator: ".")
    let url = try #require(
        Bundle.module.url(forResource: String(parts[0]), withExtension: String(parts[1]), subdirectory: "Fixtures"),
        "missing fixture \(name)"
    )
    return try Data(contentsOf: url)
}

let testNow = Date(timeIntervalSince1970: 1_794_310_000) // 10 November 2026, mid-morning UTC

func makeSource(id: Int64 = 1, kind: SourceKind = .rss, url: String = "https://example.com/feed") -> Source {
    Source(id: id, kind: kind, name: "Example", url: url, siteURL: "https://example.com", tier: .reporting)
}

@Suite struct FeedParserTests {
    @Test func parsesRSS2() throws {
        let items = try FeedParser.parse(fixture("rss2.xml"))
        // The item with no title is dropped by the parser; the bad link survives until normalisation.
        #expect(items.count == 5)

        let first = try #require(items.first)
        #expect(first.externalID == "example-1001")
        #expect(first.url.hasPrefix("https://www.example.com/2026/11/widget-2/"))
        #expect(first.title == "Acme ships <b>Widget</b> 2.0 & open-sources the runtime")
        #expect(first.author == "Ada Example")
        #expect(first.publishedAt == Date(timeIntervalSince1970: 1_794_303_000))
        // description wins over content:encoded
        #expect(first.excerpt?.contains("runtime") == true)
        #expect(first.excerpt?.contains("Full body") == false)
    }

    @Test func missingDateStaysMissing() throws {
        let items = try FeedParser.parse(fixture("rss2.xml"))
        #expect(items[1].title == "Story with no date")
        #expect(items[1].publishedAt == nil)
    }

    @Test func guidPermalinkIsUsedWhenLinkIsAbsent() throws {
        let items = try FeedParser.parse(fixture("rss2.xml"))
        #expect(items[2].url == "https://example.com/guid-permalink")
        #expect(items[2].publishedAt != nil) // "GMT" zone form
    }

    @Test func parsesAtom() throws {
        let items = try FeedParser.parse(fixture("atom.xml"))
        #expect(items.count == 2)

        #expect(items[0].title == "Introducing Model <em>Seven</em>")
        #expect(items[0].url == "https://lab.example.org/blog/model-seven") // alternate, not self
        #expect(items[0].externalID == "tag:lab.example.org,2026:7")
        #expect(items[0].author?.contains("Grace Example") == true)
        #expect(items[0].publishedAt != nil) // fractional seconds

        #expect(items[1].url == "https://lab.example.org/blog/second")
        #expect(items[1].publishedAt == Date(timeIntervalSince1970: 1_794_222_000)) // from <updated>, +01:00
        #expect(items[1].excerpt?.contains("markup") == true) // text inside nested XHTML
    }

    @Test func truncatedFeedKeepsCompleteItems() throws {
        let items = try FeedParser.parse(fixture("truncated.xml"))
        #expect(items.map(\.title) == ["Complete item before the break"])
    }

    @Test func htmlPageIsNotAFeed() throws {
        #expect(throws: IngestionError.notAFeed) {
            try FeedParser.parse(fixture("not-a-feed.html"))
        }
    }

    @Test func garbageIsRejected() {
        #expect(throws: IngestionError.self) {
            try FeedParser.parse(Data("this is not xml at all".utf8))
        }
        #expect(throws: IngestionError.self) {
            try FeedParser.parse(Data())
        }
    }

    @Test func brokenFeedWithNoItemsIsMalformed() {
        let data = Data("<rss><channel><item><title>Half".utf8)
        #expect(throws: IngestionError.self) { try FeedParser.parse(data) }
    }

    @Test func itemLimitIsEnforced() throws {
        let entries = (1...50).map { "<item><title>T\($0)</title><link>https://example.com/\($0)</link></item>" }
        let data = Data("<rss><channel>\(entries.joined())</channel></rss>".utf8)
        #expect(try FeedParser.parse(data, itemLimit: 10).count == 10)
    }

    @Test func externalEntitiesAreNotResolved() throws {
        let xml = """
            <?xml version="1.0"?>
            <!DOCTYPE rss [<!ENTITY secret SYSTEM "file:///etc/passwd">]>
            <rss><channel><item><title>Leak &secret; test</title><link>https://example.com/x</link></item></channel></rss>
            """
        let items = (try? FeedParser.parse(Data(xml.utf8))) ?? []
        for item in items {
            #expect(!item.title.contains("root:"))
        }
    }
}

@Suite struct FeedDateParserTests {
    let parser = FeedDateParser()

    @Test(arguments: [
        "Tue, 10 Nov 2026 09:30:00 +0000",
        "Tue, 10 Nov 2026 09:30:00 GMT",
        "10 Nov 2026 09:30:00 +0000",
        "2026-11-10T09:30:00Z",
        "2026-11-10T09:30:00.000Z",
        "2026-11-10T10:30:00+01:00"
    ])
    func acceptedFormats(_ text: String) {
        #expect(parser.parse(text) == Date(timeIntervalSince1970: 1_794_303_000))
    }

    @Test func rejectsNonsense() {
        #expect(parser.parse("yesterday") == nil)
        #expect(parser.parse("") == nil)
    }
}

@Suite struct HTMLTextTests {
    @Test func stripsTagsScriptsAndEntities() {
        let html = "<p>The <a href=\"https://x\">runtime</a> is out.</p><script>alert(\"x\")</script><style>p{}</style><p>Benchmarks&nbsp;included &amp; verified &#8212; &#x2026;</p>"
        #expect(HTMLText.plain(html) == "The runtime is out. Benchmarks included & verified — …")
    }

    @Test func leavesPlainTextAlone() {
        #expect(HTMLText.plain("  a < b and  c > d \n") == "a < b and c > d")
        #expect(HTMLText.plain("AT&T; R&D") == "AT&T; R&D")
    }

    @Test func unclosedScriptSwallowsTheRest() {
        #expect(HTMLText.plain("Safe <script>evil()") == "Safe")
    }

    @Test func controlCharacterReferencesAreNotDecoded() {
        #expect(HTMLText.plain("a&#0;b&#27;c") == "a&#0;b&#27;c")
    }

    @Test func truncatesAtWordBoundary() {
        #expect(HTMLText.truncate("one two three four", to: 9) == "one two…")
        #expect(HTMLText.truncate("short", to: 9) == "short")
    }
}

@Suite struct URLCanonicaliserTests {
    @Test(arguments: [
        ("https://www.Example.com/2026/11/widget-2/?utm_source=rss&utm_medium=feed#comments", "https://example.com/2026/11/widget-2"),
        ("http://example.com:80/a/", "https://example.com/a"),
        ("https://example.com/", "https://example.com"),
        ("https://example.com/a?b=2&a=1&fbclid=zzz", "https://example.com/a?a=1&b=2"),
        ("https://news.ycombinator.com/item?id=40000002", "https://news.ycombinator.com/item?id=40000002"),
        ("  https://example.com/a  ", "https://example.com/a")
    ])
    func canonicalises(_ input: String, _ expected: String) {
        #expect(URLCanonicaliser.canonical(input) == expected)
    }

    @Test(arguments: ["javascript:alert(1)", "file:///etc/passwd", "ftp://example.com/x", "/relative", "", "mailto:a@example.com", "https://"])
    func rejectsNonWebURLs(_ input: String) {
        #expect(URLCanonicaliser.canonical(input) == nil)
    }

    @Test func resolvesRelativeLinks() {
        #expect(URLCanonicaliser.webURL("/posts/a", relativeTo: "https://example.com")?.absoluteString == "https://example.com/posts/a")
        #expect(URLCanonicaliser.webURL("javascript:alert(1)", relativeTo: "https://example.com") == nil)
    }
}

@Suite struct NormaliserTests {
    @Test func cleansAndValidatesRSSItems() throws {
        let raw = try FeedParser.parse(fixture("rss2.xml"))
        let articles = Normaliser.normalise(raw, source: makeSource(), now: testNow)

        // Dropped: javascript: link. Kept: 4.
        #expect(articles.map(\.title) == [
            "Acme ships Widget 2.0 & open-sources the runtime",
            "Story with no date",
            "Permalink only in guid",
            "Relative link"
        ])

        let first = articles[0]
        #expect(first.canonicalURL == "https://example.com/2026/11/widget-2")
        #expect(first.excerpt == "The runtime is now on GitHub. Benchmarks included.")
        #expect(first.retrievedAt == testNow)
        #expect(first.contentHash.count == 64)

        #expect(articles[1].publishedAt == nil)
        #expect(articles[3].url == "https://example.com/posts/relative")
        #expect(articles[3].publishedAt == nil) // year 2099 is not believed
    }

    @Test func duplicateLinksWithinOneFeedCollapse() {
        let raw = [
            RawItem(url: "https://example.com/a?utm_source=x", title: "A"),
            RawItem(url: "https://www.example.com/a/", title: "A again")
        ]
        #expect(Normaliser.normalise(raw, source: makeSource(), now: testNow).count == 1)
    }

    @Test func longFieldsAreCapped() throws {
        let raw = RawItem(
            url: "https://example.com/long",
            title: String(repeating: "word ", count: 200),
            excerpt: String(repeating: "text ", count: 500)
        )
        let article = try #require(Normaliser.normalise(raw, source: makeSource(), now: testNow))
        #expect(article.title.count <= Normaliser.titleLimit + 1)
        #expect((article.excerpt?.count ?? 0) <= Normaliser.excerptLimit + 1)
    }

    @Test func titleMadeOnlyOfMarkupIsDropped() {
        let raw = RawItem(url: "https://example.com/x", title: "<img src=x onerror=alert(1)>")
        #expect(Normaliser.normalise(raw, source: makeSource(), now: testNow) == nil)
    }
}

@Suite struct HackerNewsAdapterTests {
    @Test func parsesSearchResponse() throws {
        let source = makeSource(kind: .hackerNews, url: "https://hn.algolia.com/api/v1/search?tags=front_page")
        let raw = try HackerNewsAdapter().parse(fixture("hackernews.json"), source: source)
        #expect(raw.count == 3) // the untitled hit is skipped

        #expect(raw[0].url == "https://example.com/2026/11/widget-2/")
        #expect(raw[0].discussionURL == "https://news.ycombinator.com/item?id=40000001")
        #expect(raw[0].score == 640)
        #expect(raw[0].commentCount == 211)
        #expect(raw[0].publishedAt == Date(timeIntervalSince1970: 1_794_303_000))

        // A text post links to its own discussion.
        #expect(raw[1].url == "https://news.ycombinator.com/item?id=40000002")

        let articles = Normaliser.normalise(raw, source: source, now: testNow)
        #expect(articles[1].excerpt == "I read too many tabs.")
        #expect(articles[2].score == nil) // negative points discarded
        #expect(articles[2].commentCount == 3)
    }

    @Test func rejectsUnexpectedJSON() {
        let source = makeSource(kind: .hackerNews)
        #expect(throws: IngestionError.self) {
            try HackerNewsAdapter().parse(Data("{\"error\":\"rate limited\"}".utf8), source: source)
        }
        #expect(throws: IngestionError.self) {
            try HackerNewsAdapter().parse(Data("<html>".utf8), source: source)
        }
    }
}

@Suite struct SourceCatalogueTests {
    @Test func bundledCatalogueIsValid() throws {
        let definitions = try SourceCatalogue.bundled()
        #expect(definitions.count >= 10)
        #expect(Set(definitions.map(\.url)).count == definitions.count)
        for definition in definitions {
            #expect(definition.url.hasPrefix("https://"), "\(definition.name) must use https")
            #expect(definition.refreshSeconds >= 900, "\(definition.name) polls too often")
            #expect(!definition.name.isEmpty)
        }
        #expect(definitions.contains { $0.kind == .hackerNews })
    }
}
