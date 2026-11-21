import Domain
import Foundation
@testable import Intelligence
@testable import Persistence
import Testing

@Suite struct TrendingAlertSelectorTests {
    private func story(
        _ id: Int64, _ headline: String = "A story", publications: Int = 1, points: Int? = nil, hoursAgo: Double = 2
    ) -> ClusterSummary {
        let date = now.addingTimeInterval(-hoursAgo * 3600)
        return ClusterSummary(
            id: id, headline: headline, url: "https://example.com/\(id)", firstSeenAt: date, lastSeenAt: date,
            sourceCount: publications, independentSourceCount: publications, sourceNames: ["Wire"],
            bestTier: .reporting, score: points
        )
    }

    @Test func strongNeedsThreePublicationsOrThreeHundredPoints() {
        let selector = TrendingAlertSelector(strictness: .strong)
        #expect(selector.qualifies(story(1, publications: 3), now: now))
        #expect(!selector.qualifies(story(2, publications: 2), now: now))
        #expect(selector.qualifies(story(3, points: 300), now: now))
        #expect(!selector.qualifies(story(4, points: 299), now: now))
    }

    @Test func veryStrongRaisesBothBars() {
        let selector = TrendingAlertSelector(strictness: .veryStrong)
        #expect(!selector.qualifies(story(1, publications: 4), now: now))
        #expect(selector.qualifies(story(2, publications: 5), now: now))
        #expect(!selector.qualifies(story(3, points: 450), now: now))
        #expect(selector.qualifies(story(4, points: 600), now: now))
    }

    @Test func onlyStoriesFirstSeenInTheLastDayCount() {
        let selector = TrendingAlertSelector(strictness: .strong)
        #expect(!selector.qualifies(story(1, publications: 9, hoursAgo: 25), now: now))
        #expect(!selector.qualifies(story(2, publications: 9, hoursAgo: -1), now: now))   // future-dated
        #expect(selector.qualifies(story(3, publications: 9, hoursAgo: 23), now: now))
    }

    @Test func picksTheThreeMostCoveredAndNeverRepeatsAStory() {
        let selector = TrendingAlertSelector(strictness: .strong)
        let candidates = [
            story(1, publications: 3), story(2, publications: 6), story(3, points: 900),
            story(4, publications: 4), story(5, publications: 8), story(6, publications: 1)
        ]
        #expect(selector.select(candidates, alreadySent: [], now: now).map(\.id) == [5, 2, 4])
        #expect(selector.select(candidates, alreadySent: [5], now: now).map(\.id) == [2, 4, 1])
        #expect(selector.select([story(6)], alreadySent: [], now: now).isEmpty)          // nothing qualifies, no alert
    }
}

@Suite struct DailyAlertScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func dueFromTheChosenTimeUntilItHasRunThatDay() {
        let schedule = DailyAlertSchedule(hour: 10, minute: 0)
        #expect(!schedule.isDue(now: at(22, 9, 59), lastRun: at(21, 10), calendar: calendar))
        #expect(schedule.isDue(now: at(22, 10), lastRun: at(21, 10), calendar: calendar))
        #expect(!schedule.isDue(now: at(22, 10, 5), lastRun: at(22, 10, 1), calendar: calendar))
        #expect(schedule.isDue(now: at(22, 10), lastRun: nil, calendar: calendar))
    }

    @Test func aMacAsleepAtTenGetsTheAlertWhenItWakesThatDay() {
        let schedule = DailyAlertSchedule(hour: 10, minute: 0)
        #expect(schedule.isDue(now: at(22, 14, 30), lastRun: at(21, 10), calendar: calendar))
        #expect(!schedule.isDue(now: at(23, 8), lastRun: at(22, 14, 30), calendar: calendar))
    }

    @Test func outOfRangeTimesAreClamped() {
        #expect(DailyAlertSchedule(hour: 30, minute: -5) == DailyAlertSchedule(hour: 23, minute: 0))
    }
}

@Suite struct AlertMessageTests {
    private func story(_ id: Int64, _ headline: String, publications: Int = 1, points: Int? = nil) -> ClusterSummary {
        ClusterSummary(
            id: id, headline: headline, url: "https://example.com/\(id)", firstSeenAt: now, lastSeenAt: now,
            sourceCount: publications, independentSourceCount: publications, sourceNames: ["Wire"],
            bestTier: .reporting, score: points
        )
    }

    @Test func listsEachHeadlineWithItsCoverageAndOpensTheFirst() throws {
        let message = try #require(AlertMessage(stories: [
            story(7, "Orion 3 ships", publications: 5), story(8, "A   tidy\nheadline", points: 420)
        ]))
        #expect(message.title == "2 trending stories")
        #expect(message.body == "• Orion 3 ships — 5 publications\n• A tidy headline — 420 points")
        #expect(message.clusterID == 7)
        #expect(message.clusterIDs == [7, 8])
    }

    @Test func oneStoryAndNoStories() throws {
        let one = try #require(AlertMessage(stories: [story(1, "Orion 3 ships", publications: 3)]))
        #expect(one.title == "Trending story")
        #expect(one.body == "Orion 3 ships — 3 publications")
        #expect(AlertMessage(stories: []) == nil)
    }

    @Test func longHeadlinesAreShortened() throws {
        let message = try #require(AlertMessage(stories: [story(1, String(repeating: "a", count: 300), publications: 3)]))
        #expect(message.body.hasPrefix(String(repeating: "a", count: 119) + "…"))
    }
}

@Suite struct AlertStoreTests {
    typealias Store = IntelligenceServiceTests.Store

    @Test func alertSourcesLimitTheCandidatesAndSentStoriesAreRemembered() async throws {
        let store = try await Store()
        try await store.add("Northwind Blog", "Introducing Orion 3", url: "https://northwind.example/orion-3", hoursAgo: 3)
        try await store.add("Wire", "The quiet death of the headphone jack", url: "https://wire.example/jack", hoursAgo: 1)
        _ = try await store.service.process()

        #expect(try await store.sources.allSources().allSatisfy { !$0.alertsEnabled })   // off until chosen
        try await store.sources.setAlertsEnabled(true, sourceID: store.ids["Wire"]!)
        let chosen = Set(try await store.sources.allSources().filter(\.alertsEnabled).map(\.id))
        #expect(chosen == [store.ids["Wire"]!])

        let candidates = try await store.clusters.summaries(StoryFilter(sourceIDs: chosen))
        #expect(candidates.map(\.headline) == ["The quiet death of the headphone jack"])
        #expect(try await store.clusters.summaries(StoryFilter(sourceIDs: [])).isEmpty)

        let alerts = GRDBAlertRepository(database: store.database)
        try await alerts.recordSent(candidates.map(\.id), at: now)
        #expect(try await alerts.sentClusterIDs(since: now.addingTimeInterval(-3600)) == Set(candidates.map(\.id)))
        #expect(try await alerts.sentClusterIDs(since: now.addingTimeInterval(60)).isEmpty)
        try await alerts.recordSent(candidates.map(\.id), at: now)                         // recording twice is harmless
    }

    @Test func aFolderCanBeChosenAtOnce() async throws {
        let store = try await Store()
        try await store.sources.setFolder("Labs", sourceID: store.ids["Northwind Blog"]!)
        try await store.sources.setAlertsEnabled(true, folder: "Labs")
        let enabled = try await store.sources.allSources().filter(\.alertsEnabled).map(\.name)
        #expect(enabled == ["Northwind Blog"])
        try await store.sources.setAlertsEnabled(false, folder: "Labs")
        #expect(try await store.sources.allSources().allSatisfy { !$0.alertsEnabled })
    }
}
