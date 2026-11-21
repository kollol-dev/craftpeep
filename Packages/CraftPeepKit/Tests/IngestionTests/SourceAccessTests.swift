import Domain
import Foundation
import Persistence
import Testing
@testable import Ingestion

@Suite struct FailureMessageTests {
    @Test func statusesSayWhatHappenedAndWhetherRetryingHelps() {
        #expect(IngestionError.httpStatus(410).description.contains("removed this feed"))
        #expect(IngestionError.httpStatus(404).description.contains("not found"))
        #expect(IngestionError.httpStatus(429).description.contains("limiting or blocking"))
        #expect(IngestionError.httpStatus(502).description.contains("usually temporary"))
        #expect(IngestionError.httpStatus(403).description.contains("refused access"))
        #expect(IngestionError.httpStatus(418).description == "Server returned HTTP 418")
        let redirect = IngestionError.insecureRedirect(host: "feeds.example.com").description
        #expect(redirect.hasPrefix(IngestionError.insecureRedirectMessage))
        #expect(redirect.contains("feeds.example.com"))
    }
}

@Suite struct SourceAccessTests {
    @Test func theHTTPAllowanceAndTrustLevelAreStoredPerSource() async throws {
        let sources = GRDBSourceRepository(database: try AppDatabase())
        try await sources.seed([SourceDefinition(kind: .rss, name: "Blog", url: "https://blog.example/feed", tier: .unverified)])
        var source = try #require(try await sources.allSources().first)
        #expect(!source.allowsInsecureHTTP)

        try await sources.record(FetchOutcome(sourceID: source.id, at: testNow, status: .failed(message: "x")))
        try await sources.record(FetchOutcome(sourceID: source.id, at: testNow, status: .failed(message: "x")))
        try await sources.setAllowsInsecureHTTP(true, sourceID: source.id)
        try await sources.setTier(.official, sourceID: source.id)
        source = try #require(try await sources.allSources().first)
        #expect(source.allowsInsecureHTTP)
        #expect(source.failCount == 0)                 // allowing http means "try again now"
        #expect(source.isDue(at: testNow))
        #expect(source.tier == .official)
        #expect(!source.isUserAdded)                   // changing the level does not make a catalogue source removable

        try await sources.setAllowsInsecureHTTP(false, sourceID: source.id)
        #expect(try await sources.allSources().first?.allowsInsecureHTTP == false)
    }

    @Test func ingestionPassesTheAllowanceToTheNetworkOnlyForThatSource() async throws {
        let harness = try await Harness()
        try await harness.scriptAllHealthy()
        let lab = try #require(try await harness.sources.allSources().first { $0.url == Harness.atomURL })
        try await harness.sources.setAllowsInsecureHTTP(true, sourceID: lab.id)

        _ = try await harness.service.refreshAll()
        let calls = await harness.http.calls
        #expect(calls.first { $0.url == Harness.atomURL }?.allowInsecure == true)
        #expect(calls.filter { $0.url != Harness.atomURL }.allSatisfy { !$0.allowInsecure })
    }

    @Test func plainHTTPIsRefusedUnlessAllowed() async throws {
        let client = URLSessionHTTPClient()
        await #expect(throws: IngestionError.insecureURL("http://example.invalid/feed")) {
            try await client.get(URL(string: "http://example.invalid/feed")!, validators: nil, accept: "*/*", maxBytes: 1000)
        }
        await #expect(throws: IngestionError.self) {
            try await client.get(URL(string: "ftp://example.invalid/feed")!, validators: nil, accept: "*/*", maxBytes: 1000, allowInsecure: true)
        }
    }
}

/// A real feed whose https address redirects to plain http (Search Engine Roundtable, seen 21 November 2026).
///   CRAFTPEEP_LIVE=1 swift test --filter LiveInsecureRedirectTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CRAFTPEEP_LIVE"] == "1"))
struct LiveInsecureRedirectTests {
    let address = URL(string: "https://www.seroundtable.com/index.xml")!

    @Test func aRedirectToHTTPIsStoppedAndNamedUnlessAllowed() async throws {
        do {
            _ = try await URLSessionHTTPClient().get(address, validators: nil, accept: RSSAdapter().accept, maxBytes: IngestionService.maxResponseBytes)
            Issue.record("the redirect to http was followed without permission")
        } catch let error as IngestionError {
            print("LIVE without permission: \(error)")
            guard case .insecureRedirect = error else { Issue.record("unexpected \(error)"); return }
        }

        let result = try await URLSessionHTTPClient().get(address, validators: nil, accept: RSSAdapter().accept, maxBytes: IngestionService.maxResponseBytes, allowInsecure: true)
        guard case .ok(let data, _) = result else { Issue.record("no content"); return }
        let items = try FeedParser.parse(data)
        print("LIVE with permission: \(items.count) items, first: \(items.first?.title ?? "-")")
        #expect(!items.isEmpty)
    }
}
