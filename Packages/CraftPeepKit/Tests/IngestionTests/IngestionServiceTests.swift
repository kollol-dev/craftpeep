import Domain
import Foundation
import Persistence
import Testing
@testable import Ingestion

/// Scripted network: each URL has a queue of responses, served in order (the last one repeats).
actor FakeHTTPClient: HTTPClient {
    enum Reply: Sendable {
        case result(HTTPResult)
        case failure(IngestionError)
    }

    struct Call: Sendable, Equatable {
        var url: String
        var validators: HTTPValidators?
    }

    private var replies: [String: [Reply]] = [:]
    private(set) var calls: [Call] = []

    func script(_ url: String, _ sequence: [Reply]) {
        replies[url] = sequence
    }

    func get(_ url: URL, validators: HTTPValidators?, accept: String, maxBytes: Int) async throws -> HTTPResult {
        let key = url.absoluteString
        calls.append(Call(url: key, validators: validators))
        guard var queue = replies[key], let next = queue.first else {
            throw IngestionError.httpStatus(404)
        }
        if queue.count > 1 {
            queue.removeFirst()
            replies[key] = queue
        }
        switch next {
        case .result(let result):
            if case .ok(let data, _) = result, data.count > maxBytes {
                throw IngestionError.tooLarge(limitBytes: maxBytes)
            }
            return result
        case .failure(let error):
            throw error
        }
    }
}

struct Harness {
    let sources: GRDBSourceRepository
    let articles: GRDBArticleRepository
    let http = FakeHTTPClient()
    let service: IngestionService

    static let rssURL = "https://example.com/feed"
    static let atomURL = "https://lab.example.org/atom"
    static let hnURL = "https://hn.algolia.com/api/v1/search?tags=front_page"

    init() async throws {
        let database = try AppDatabase()
        sources = GRDBSourceRepository(database: database)
        articles = GRDBArticleRepository(database: database)
        service = IngestionService(sources: sources, articles: articles, http: http, now: { testNow })
        try await sources.seed([
            SourceDefinition(kind: .rss, name: "Example Tech", url: Self.rssURL, siteURL: "https://example.com", tier: .reporting),
            SourceDefinition(kind: .rss, name: "Example Lab", url: Self.atomURL, siteURL: "https://lab.example.org", tier: .official),
            SourceDefinition(kind: .hackerNews, name: "Hacker News", url: Self.hnURL, tier: .community)
        ])
    }

    func scriptAllHealthy() async throws {
        let validators = HTTPValidators(etag: "\"v1\"", lastModified: "Tue, 10 Nov 2026 09:00:00 GMT")
        await http.script(Self.rssURL, [.result(.ok(data: try fixture("rss2.xml"), validators: validators)), .result(.notModified)])
        await http.script(Self.atomURL, [.result(.ok(data: try fixture("atom.xml"), validators: HTTPValidators()))])
        await http.script(Self.hnURL, [.result(.ok(data: try fixture("hackernews.json"), validators: HTTPValidators()))])
    }
}

@Suite struct IngestionServiceTests {
    @Test func firstRefreshStoresEverything() async throws {
        let harness = try await Harness()
        try await harness.scriptAllHealthy()

        let report = try await harness.service.refreshAll()

        #expect(report.failures == 0)
        #expect(report.outcomes.count == 3)
        #expect(report.newArticles == 4 + 2 + 3)
        #expect(try await harness.articles.articleCount() == 9)
    }

    @Test func secondRefreshAddsNoDuplicatesAndSendsValidators() async throws {
        let harness = try await Harness()
        try await harness.scriptAllHealthy()

        _ = try await harness.service.refreshAll()
        let second = try await harness.service.refreshAll()

        #expect(second.newArticles == 0)
        #expect(second.notModified == 1) // the RSS feed answered 304
        #expect(second.failures == 0)
        #expect(try await harness.articles.articleCount() == 9)

        let rssCalls = await harness.http.calls.filter { $0.url == Harness.rssURL }
        #expect(rssCalls.count == 2)
        #expect(rssCalls[0].validators == nil)
        #expect(rssCalls[1].validators?.etag == "\"v1\"")
        #expect(rssCalls[1].validators?.lastModified == "Tue, 10 Nov 2026 09:00:00 GMT")
    }

    @Test func oneFailingSourceDoesNotStopTheOthers() async throws {
        let harness = try await Harness()
        try await harness.scriptAllHealthy()
        await harness.http.script(Harness.atomURL, [.failure(.httpStatus(503))])

        let report = try await harness.service.refreshAll()

        #expect(report.failures == 1)
        #expect(report.newArticles == 4 + 3)

        let lab = try #require(try await harness.sources.allSources().first { $0.url == Harness.atomURL })
        #expect(lab.failCount == 1)
        #expect(lab.lastError == "Server returned HTTP 503")
        #expect(lab.lastOKAt == nil)

        let tech = try #require(try await harness.sources.allSources().first { $0.url == Harness.rssURL })
        #expect(tech.failCount == 0)
        #expect(tech.lastOKAt == testNow)
    }

    @Test func recoveryClearsTheFailure() async throws {
        let harness = try await Harness()
        try await harness.scriptAllHealthy()
        await harness.http.script(Harness.atomURL, [
            .failure(.network("offline")),
            .result(.ok(data: try fixture("atom.xml"), validators: HTTPValidators()))
        ])

        _ = try await harness.service.refreshAll()
        let second = try await harness.service.refreshAll()

        #expect(second.failures == 0)
        let lab = try #require(try await harness.sources.allSources().first { $0.url == Harness.atomURL })
        #expect(lab.failCount == 0)
        #expect(lab.lastError == nil)
    }

    @Test func htmlErrorPageAndOversizedBodyAreFailures() async throws {
        let harness = try await Harness()
        try await harness.scriptAllHealthy()
        await harness.http.script(Harness.rssURL, [.result(.ok(data: try fixture("not-a-feed.html"), validators: HTTPValidators()))])
        let huge = Data(count: IngestionService.maxResponseBytes + 1)
        await harness.http.script(Harness.atomURL, [.result(.ok(data: huge, validators: HTTPValidators()))])

        let report = try await harness.service.refreshAll()

        #expect(report.failures == 2)
        #expect(try await harness.articles.articleCount() == 3) // Hacker News only
    }

    @Test func changedScoreUpdatesInPlace() async throws {
        let harness = try await Harness()
        try await harness.scriptAllHealthy()
        let updated = String(decoding: try fixture("hackernews.json"), as: UTF8.self)
            .replacingOccurrences(of: "\"points\": 640", with: "\"points\": 900")
        await harness.http.script(Harness.hnURL, [
            .result(.ok(data: try fixture("hackernews.json"), validators: HTTPValidators())),
            .result(.ok(data: Data(updated.utf8), validators: HTTPValidators()))
        ])

        _ = try await harness.service.refreshAll()
        let second = try await harness.service.refreshAll()

        #expect(second.newArticles == 0)
        let stories = try await harness.articles.latestStories(limit: 50, matching: nil)
        #expect(stories.first { $0.discussionURL?.hasSuffix("40000001") == true }?.score == 900)
    }

    @Test func concurrentRefreshCallsShareOneRun() async throws {
        let harness = try await Harness()
        try await harness.scriptAllHealthy()

        async let first = harness.service.refreshAll()
        async let second = harness.service.refreshAll()
        let reports = try await [first, second]

        #expect(reports[0] == reports[1])
        #expect(await harness.http.calls.count == 3)
    }
}
