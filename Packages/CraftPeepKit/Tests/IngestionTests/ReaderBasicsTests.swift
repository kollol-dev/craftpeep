import Domain
import Foundation
import Persistence
import Testing
@testable import Ingestion

@Suite struct JSONFeedTests {
    @Test func parsesJSONFeed() throws {
        let items = try FeedParser.parse(fixture("jsonfeed.json"))
        // Dropped: an item with no link, an item with neither title nor text, and a non-object.
        #expect(items.count == 3)

        #expect(items[0].title == "Notes on <em>Kestrel</em> 2.0")
        #expect(items[0].excerpt == "What changed in the query planner.")      // summary wins
        #expect(items[0].author == "Ada Example")
        #expect(items[0].publishedAt == Date(timeIntervalSince1970: 1_794_303_000))

        #expect(items[1].externalID == "4242")                                  // numeric ids are allowed
        #expect(items[1].title.hasPrefix("A short post with no title. It still needs"))
        #expect(items[1].author == "Grace Example")                             // JSON Feed 1.0 "author"
        #expect(items[1].publishedAt != nil)                                    // from date_modified

        #expect(items[2].url == "https://other.example.org/article")            // external_url when no url
    }

    @Test func cleansLikeAnyOtherFeed() throws {
        let articles = Normaliser.normalise(try FeedParser.parse(fixture("jsonfeed.json")), source: makeSource(), now: testNow)
        #expect(articles[0].title == "Notes on Kestrel 2.0")
        #expect(articles[0].canonicalURL == "https://blog.example.net/2026/11/kestrel")
        #expect(articles[1].title.count <= 121)
        #expect(articles[2].excerpt == "Commentary here.")
    }

    @Test func otherJSONIsNotAFeed() {
        #expect(throws: IngestionError.notAFeed) { try FeedParser.parse(Data(#"{"hits":[]}"#.utf8)) }
        #expect(throws: IngestionError.notAFeed) { try FeedParser.parse(Data(#"{"version":"https://example.com/v1","items":[]}"#.utf8)) }
        #expect(throws: IngestionError.self) { try FeedParser.parse(Data("{ not json".utf8)) }
    }

    @Test func leadingWhitespaceAndByteOrderMarkStillRead() throws {
        let body = #"{"version":"https://jsonfeed.org/version/1","items":[{"id":"1","url":"https://a.example/1","title":"T"}]}"#
        #expect(try FeedParser.parse(Data(("\u{FEFF}\n  " + body).utf8)).count == 1)
    }

    @Test func itemLimitApplies() throws {
        let items = (0..<50).map { #"{"id":"\#($0)","url":"https://a.example/\#($0)","title":"T\#($0)"}"# }.joined(separator: ",")
        let data = Data(#"{"version":"https://jsonfeed.org/version/1.1","items":[\#(items)]}"#.utf8)
        #expect(try FeedParser.parse(data, itemLimit: 7).count == 7)
    }
}

@Suite struct OPMLTests {
    @Test func readsNestedOutlinesWithAnyAttributeCase() throws {
        let feeds = try OPML.parse(fixture("subscriptions.opml"))
        #expect(feeds.map(\.xmlURL) == [
            "https://example.com/feed", "http://old.example.org/rss.xml", "https://example.com/feed",
            "https://caps.example.net/atom.xml", "https://untitled.example.net/feed.json",
            "file:///etc/passwd", "javascript:alert(1)", "https://markup.example.com/feed?a=1&b=2"
        ])
        #expect(feeds[3].title == "Uppercase Attributes")
        #expect(feeds[7].title == "Name & <markup>")
    }

    @Test func plansSafeDeduplicatedUnverifiedSources() throws {
        let plan = OPML.plan(try OPML.parse(fixture("subscriptions.opml")))

        #expect(plan.definitions.map(\.url) == [
            "https://example.com/feed", "https://old.example.org/rss.xml", "https://caps.example.net/atom.xml",
            "https://untitled.example.net/feed.json", "https://markup.example.com/feed?a=1&b=2"
        ])
        #expect(plan.upgradedToHTTPS == 1)
        #expect(plan.skipped.count == 2)                                      // file: and javascript:
        #expect(plan.definitions.allSatisfy { $0.tier == .unverified && $0.kind == .rss })
        #expect(plan.definitions[0].name == "Example Tech")
        #expect(plan.definitions[0].siteURL == "https://example.com/")
        #expect(plan.definitions[3].name == "No title either")                 // empty title falls back to text
        #expect(plan.definitions[4].name == "Name & <markup>")                 // stored as plain text, shown as text
    }

    @Test func rejectsWhatIsNotOPML() {
        #expect(throws: IngestionError.self) { try OPML.parse(Data("<rss><channel/></rss>".utf8)) }
        #expect(throws: IngestionError.self) { try OPML.parse(Data("not xml".utf8)) }
        #expect(throws: IngestionError.self) { try OPML.parse(Data(count: OPML.maximumBytes + 1)) }
    }

    @Test func externalEntitiesAreNotResolved() throws {
        let xml = """
            <?xml version="1.0"?>
            <!DOCTYPE opml [<!ENTITY secret SYSTEM "file:///etc/passwd">]>
            <opml version="2.0"><body><outline text="&secret;" xmlUrl="https://a.example/feed"/></body></opml>
            """
        let feeds = (try? OPML.parse(Data(xml.utf8))) ?? []
        #expect(feeds.allSatisfy { !($0.title ?? "").contains("root:") })
    }

    @Test func exportsFeedSourcesAndReadsBack() throws {
        let sources = [
            Source(id: 1, kind: .rss, name: "Tom & Jerry's \"Blog\" <3", url: "https://a.example/feed?x=1&y=2", siteURL: "https://a.example", tier: .unverified),
            Source(id: 2, kind: .hackerNews, name: "Hacker News", url: "https://hn.algolia.com/api/v1/search", tier: .community),
            Source(id: 3, kind: .rss, name: "Off but kept", url: "https://b.example/rss", tier: .official, enabled: false)
        ]
        let data = OPML.document(for: sources, now: testNow)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix(#"<?xml version="1.0" encoding="UTF-8"?>"#))
        #expect(text.contains("<dateCreated>Tue, 10 Nov 2026"))
        #expect(!text.contains("hn.algolia.com"))                           // not a feed

        let back = try OPML.parse(data)
        #expect(back == [
            OPMLFeed(title: "Tom & Jerry's \"Blog\" <3", xmlURL: "https://a.example/feed?x=1&y=2", htmlURL: "https://a.example"),
            OPMLFeed(title: "Off but kept", xmlURL: "https://b.example/rss", htmlURL: nil)
        ])
    }

    @Test func controlCharactersCannotBreakTheExport() throws {
        let sources = [Source(id: 1, kind: .rss, name: "Bad\u{0}name\u{7}", url: "https://a.example/feed", tier: .unverified)]
        let back = try OPML.parse(OPML.document(for: sources))
        #expect(back.first?.title == "Badname")
    }

    @Test func importedFeedsAlreadyPresentAreNotAddedTwice() async throws {
        let sources = GRDBSourceRepository(database: try AppDatabase())
        try await sources.seed([SourceDefinition(kind: .rss, name: "Catalogue copy", url: "https://example.com/feed", tier: .reporting)])
        var added = 0
        for definition in OPML.plan(try OPML.parse(fixture("subscriptions.opml"))).definitions {
            if try await sources.addUserSource(definition) { added += 1 }
        }
        #expect(added == 4)
        let stored = try await sources.allSources()
        #expect(stored.first { $0.url == "https://example.com/feed" }?.tier == .reporting)   // the existing source is untouched
    }
}


@Suite struct OPMLFolderTests {
    let file = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0"><body>
          <outline text="1. AI Labs (first-hand launches)" title="1. AI Labs (first-hand launches)">
            <outline type="rss" text="Lab One" xmlUrl="https://one.example/feed"/>
            <outline text="Nested group">
              <outline type="rss" text="Deep" xmlUrl="https://deep.example/feed"/>
            </outline>
            <outline type="rss" text="Lab Two" xmlUrl="https://two.example/feed"/>
          </outline>
          <outline type="rss" text="Loose" xmlUrl="https://loose.example/feed"/>
        </body></opml>
        """

    @Test func keepsTheNearestFolderForEachFeed() throws {
        let feeds = try OPML.parse(Data(file.utf8))
        #expect(feeds.map(\.folder) == ["1. AI Labs (first-hand launches)", "Nested group", "1. AI Labs (first-hand launches)", nil])
        #expect(OPML.plan(feeds).definitions.map(\.folder) == feeds.map(\.folder))
    }

    @Test func exportWritesFoldersAndReadsBack() throws {
        let sources = [
            Source(id: 1, kind: .rss, name: "B", url: "https://b.example/feed", tier: .reporting, folder: "News & Views"),
            Source(id: 2, kind: .rss, name: "A", url: "https://a.example/feed", tier: .reporting, folder: "AI"),
            Source(id: 3, kind: .rss, name: "C", url: "https://c.example/feed", tier: .reporting)
        ]
        let back = try OPML.parse(OPML.document(for: sources))
        #expect(back.map(\.xmlURL) == ["https://a.example/feed", "https://b.example/feed", "https://c.example/feed"])   // folders sorted, loose last
        #expect(back.map(\.folder) == ["AI", "News & Views", nil])
    }

    @Test func catalogueEntriesAllHaveAFolder() throws {
        let definitions = try SourceCatalogue.bundled()
        #expect(definitions.allSatisfy { $0.folder != nil })
        #expect(Set(definitions.compactMap(\.folder)) == ["Community", "Tech News", "AI Labs", "Developer", "Analysis"])
    }
}
