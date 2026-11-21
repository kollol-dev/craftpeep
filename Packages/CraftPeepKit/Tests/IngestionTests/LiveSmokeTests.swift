import Domain
import Foundation
import Persistence
import Testing
@testable import Ingestion

/// Hits the real network, so it only runs on request:
///   CRAFTPEEP_LIVE=1 swift test --filter LiveSmokeTests
/// Use it to check the bundled catalogue before a release or after editing it.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CRAFTPEEP_LIVE"] == "1"))
struct LiveSmokeTests {
    @Test func bundledCatalogueFetchesAndSecondRefreshAddsNothing() async throws {
        let database = try AppDatabase()
        let sources = GRDBSourceRepository(database: database)
        let articles = GRDBArticleRepository(database: database)
        try await sources.seed(SourceCatalogue.bundled())
        let service = IngestionService(sources: sources, articles: articles, http: URLSessionHTTPClient())

        let clock = ContinuousClock()
        var first = RefreshReport(startedAt: .now, outcomes: [])
        let firstDuration = try await clock.measure { first = try await service.refreshAll() }
        var second = RefreshReport(startedAt: .now, outcomes: [])
        let secondDuration = try await clock.measure { second = try await service.refreshAll() }

        let names = Dictionary(uniqueKeysWithValues: try await sources.allSources().map { ($0.id, $0.name) })
        for (a, b) in zip(first.outcomes, second.outcomes) {
            print("LIVE \(names[a.sourceID] ?? "?"): \(a.status) seen=\(a.itemsSeen) new=\(a.itemsNew) \(a.bytes / 1024)KB \(a.durationMillis)ms | second: \(b.status) new=\(b.itemsNew)")
        }
        print("LIVE first: \(first.newArticles) new, \(first.failures) failed, \(firstDuration)")
        print("LIVE second: \(second.newArticles) new, \(second.notModified) not modified, \(second.failures) failed, \(secondDuration)")

        #expect(first.failures == 0)
        #expect(first.newArticles > 50)
        // A story can genuinely be published between the two runs, so allow a couple.
        #expect(second.newArticles <= 3)
        #expect(try await articles.latestStories(limit: 5, matching: nil).count == 5)
    }
}

/// Reads real JSON Feeds, to check the parser against publishers' actual output.
///   CRAFTPEEP_LIVE=1 swift test --filter LiveJSONFeedTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CRAFTPEEP_LIVE"] == "1"))
struct LiveJSONFeedTests {
    @Test(arguments: ["https://www.jsonfeed.org/feed.json", "https://daringfireball.net/feeds/json"])
    func parsesARealJSONFeed(_ address: String) async throws {
        let result = try await URLSessionHTTPClient().get(URL(string: address)!, validators: nil, accept: RSSAdapter().accept, maxBytes: IngestionService.maxResponseBytes)
        guard case .ok(let data, _) = result else { Issue.record("no content"); return }
        let articles = Normaliser.normalise(try FeedParser.parse(data), source: makeSource(url: address), now: Date())
        print("JSONFEED \(address): \(articles.count) articles; first: \(articles.first?.title ?? "-") | dated: \(articles.filter { $0.publishedAt != nil }.count)")
        #expect(!articles.isEmpty)
    }
}
