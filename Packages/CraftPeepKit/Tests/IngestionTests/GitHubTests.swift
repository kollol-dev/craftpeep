import Domain
import Foundation
import Persistence
import Testing
@testable import Ingestion

@Suite struct GitHubSearchTests {
    @Test func parsesRepositoriesAndDropsWhatItShouldNotKeep() throws {
        let repositories = try GitHubSearch.parse(fixture("github-search.json"))
        // Dropped: a fork, an archived repository, a link that is not on github.com, a malformed name.
        #expect(repositories.map(\.fullName) == ["northwind/orion-runtime", "helix-labs/kestrel"])

        let first = repositories[0]
        #expect(first.id == 1001)
        #expect(first.description == "A fast inference runtime :rocket:")      // markup removed
        #expect(first.language == "Rust")
        #expect(first.topics == ["llm", "inference"])
        #expect(first.stars == 12000)
        #expect(first.createdAt == Date(timeIntervalSince1970: 1_792_488_600))
        #expect(repositories[1].description == nil)
        #expect(repositories[1].language == nil)
    }

    @Test func rejectsErrorBodies() {
        #expect(throws: IngestionError.self) {
            try GitHubSearch.parse(Data(#"{"message":"API rate limit exceeded","documentation_url":"https://docs.github.com"}"#.utf8))
        }
        #expect(throws: IngestionError.self) { try GitHubSearch.parse(Data("<html>".utf8)) }
    }

    @Test func buildsDatedQueriesAgainstTheOfficialEndpoint() throws {
        let queries = GitHubSearch.queries(now: testNow)
        #expect(queries.count == 3)
        #expect(queries[0].terms == "created:>2026-10-11 stars:>100")
        #expect(queries[1].terms.contains("pushed:>2026-11-03"))
        let url = try #require(GitHubSearch.url(for: queries[0]))
        #expect(url.host() == "api.github.com")
        #expect(url.path() == "/search/repositories")
        #expect(url.absoluteString.contains("per_page=50"))
        #expect(url.absoluteString.contains("sort=stars"))
    }
}

@Suite struct GitHubServiceTests {
    struct Harness {
        let store: GRDBRepositoryStore
        let http = FakeHTTPClient()
        let clock = Clock()

        final class Clock: @unchecked Sendable {
            private let lock = NSLock()
            private var value = testNow
            var now: Date { lock.withLock { value } }
            func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
        }

        init() throws {
            store = GRDBRepositoryStore(database: try AppDatabase())
        }

        var service: GitHubService {
            let clock = clock
            return GitHubService(http: http, store: store, now: { clock.now })
        }

        func script(_ reply: FakeHTTPClient.Reply) async {
            for query in GitHubSearch.queries(now: clock.now) {
                await http.script(GitHubSearch.url(for: query)!.absoluteString, [reply])
            }
        }
    }

    @Test func storesRepositoriesAndSkipsUntilDue() async throws {
        let harness = try Harness()
        await harness.script(.result(.ok(data: try fixture("github-search.json"), validators: HTTPValidators())))

        let first = try await harness.service.refreshIfDue()
        #expect(first.ran)
        #expect(first.repositoriesSeen == 2)                      // the same two from each of three queries
        #expect(await harness.http.calls.count == 3)
        #expect(await harness.service.lastError() == nil)
        #expect(await harness.service.lastSuccess() == testNow)

        harness.clock.advance(3600)
        let second = try await harness.service.refreshIfDue()
        #expect(!second.ran)
        #expect(await harness.http.calls.count == 3)              // nothing was sent

        harness.clock.advance(6 * 3600)
        await harness.script(.result(.ok(data: try fixture("github-search.json"), validators: HTTPValidators())))
        #expect(try await harness.service.refreshIfDue().ran)
    }

    @Test func rateLimitingIsRecordedAndRetriedAfterAnHourNotSooner() async throws {
        let harness = try Harness()
        await harness.script(.failure(.httpStatus(403)))

        let report = try await harness.service.refreshIfDue()
        #expect(report.failedQueries == 3)
        #expect(report.repositoriesSeen == 0)
        #expect(await harness.service.lastError() == "GitHub is rate limiting requests")
        #expect(await harness.service.lastSuccess() == nil)

        harness.clock.advance(1800)
        #expect(try await harness.service.refreshIfDue().ran == false)
        harness.clock.advance(1800)
        await harness.script(.result(.ok(data: try fixture("github-search.json"), validators: HTTPValidators())))
        #expect(try await harness.service.refreshIfDue().ran)
        #expect(await harness.service.lastError() == nil)
    }

    @Test func recordsOneSnapshotPerDayAndKeepsTheFirst() async throws {
        let store = GRDBRepositoryStore(database: try AppDatabase())
        func repository(_ stars: Int) -> Repository {
            Repository(id: 1, fullName: "a/b", url: "https://github.com/a/b", stars: stars, createdAt: testNow.addingTimeInterval(-400 * 86_400))
        }
        let dayStart = Date(timeIntervalSince1970: (testNow.timeIntervalSince1970 / 86_400).rounded(.down) * 86_400)
        try await store.record([repository(100)], at: dayStart.addingTimeInterval(3600))
        try await store.record([repository(130)], at: dayStart.addingTimeInterval(7200))               // same day: baseline stays 100
        try await store.record([repository(400)], at: dayStart.addingTimeInterval(2 * 86_400 + 60))

        let history = try #require(try await store.histories(seenSince: .distantPast, baselineSince: .distantPast).first)
        #expect(history.repository.stars == 400)
        #expect(history.baselineStars == 100)
        #expect(history.baselineAt == dayStart.addingTimeInterval(3600))

        // A look-back window that starts after the first day uses the next reading as its baseline.
        let recent = try #require(try await store.histories(seenSince: .distantPast, baselineSince: dayStart.addingTimeInterval(86_400)).first)
        #expect(recent.baselineStars == 400)

        try await store.purgeRepositories(notSeenSince: dayStart.addingTimeInterval(3 * 86_400), snapshotsBefore: .distantPast)
        #expect(try await store.histories(seenSince: .distantPast, baselineSince: .distantPast).isEmpty)
    }

    @Test func metaRoundTrips() async throws {
        let store = GRDBRepositoryStore(database: try AppDatabase())
        #expect(try await store.meta("k") == nil)
        try await store.setMeta("v", for: "k")
        try await store.setMeta("w", for: "k")
        #expect(try await store.meta("k") == "w")
        try await store.setMeta(nil, for: "k")
        #expect(try await store.meta("k") == nil)
    }
}
