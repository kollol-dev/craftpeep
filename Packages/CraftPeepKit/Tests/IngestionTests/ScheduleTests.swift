import Domain
import Foundation
import Persistence
import Testing
@testable import Ingestion

@Suite struct ScheduleTests {
    private func source(interval: Int = 1800, lastFetch: TimeInterval?, failures: Int = 0) -> Source {
        Source(
            id: 1, kind: .rss, name: "S", url: "https://example.com/feed", tier: .reporting,
            refreshSeconds: interval, lastFetchAt: lastFetch.map { testNow.addingTimeInterval(-$0) }, failCount: failures
        )
    }

    @Test func neverFetchedIsDue() {
        #expect(source(lastFetch: nil).isDue(at: testNow))
    }

    @Test func dueOnlyAfterItsInterval() {
        #expect(!source(lastFetch: 1799).isDue(at: testNow))
        #expect(source(lastFetch: 1800).isDue(at: testNow))
    }

    @Test func failuresBackOffExponentiallyUpToADay() {
        #expect(source(lastFetch: nil, failures: 1).effectiveInterval == 3600)
        #expect(source(lastFetch: nil, failures: 3).effectiveInterval == 14_400)
        #expect(source(lastFetch: nil, failures: 50).effectiveInterval == 86_400)
        #expect(!source(lastFetch: 3599, failures: 1).isDue(at: testNow))
        #expect(source(lastFetch: 3600, failures: 1).isDue(at: testNow))
    }

    @Test func absurdIntervalsAreFloored() {
        #expect(source(interval: 0, lastFetch: nil).effectiveInterval == 60)
    }

    @Test func refreshDueSkipsFreshSourcesButRefreshAllDoesNot() async throws {
        let harness = try await Harness()
        try await harness.scriptAllHealthy()

        let first = try await harness.service.refreshDue()
        #expect(first.outcomes.count == 3) // nothing fetched before, so everything is due

        let second = try await harness.service.refreshDue()
        #expect(second.outcomes.isEmpty)   // same clock time: nothing is due
        #expect(await harness.http.calls.count == 3)

        let forced = try await harness.service.refreshAll()
        #expect(forced.outcomes.count == 3)
    }

    @Test func futureDatesAreTreatedAsMissing() throws {
        let source = makeSource()
        func published(_ offset: TimeInterval) -> Date? {
            let raw = RawItem(url: "https://example.com/a", title: "A", publishedAt: testNow.addingTimeInterval(offset))
            return Normaliser.normalise(raw, source: source, now: testNow)?.publishedAt
        }
        #expect(published(-60) != nil)
        #expect(published(120) != nil)        // clock skew
        #expect(published(18 * 3600) == nil)  // a scheduled post dated tomorrow
    }

    @Test func itemsOlderThanTheRetentionPeriodAreNotStored() {
        let source = makeSource()
        let raw = [
            RawItem(url: "https://example.com/new", title: "New", publishedAt: testNow.addingTimeInterval(-86_400)),
            RawItem(url: "https://example.com/old", title: "Old", publishedAt: testNow.addingTimeInterval(-200 * 86_400)),
            RawItem(url: "https://example.com/undated", title: "Undated")
        ]
        let kept = Normaliser.normalise(raw, source: source, now: testNow, maxAge: 90 * 86_400)
        #expect(kept.map(\.title) == ["New", "Undated"])
        #expect(Normaliser.normalise(raw, source: source, now: testNow).count == 3)
    }
}
