import Domain
import Foundation
@testable import Persistence
import Testing
@testable import Intelligence

@Suite struct UserStateAndFilterTests {
    typealias Store = IntelligenceServiceTests.Store

    private func seeded() async throws -> Store {
        let store = try await Store()
        try await store.add("Northwind Blog", "Introducing Orion 3", url: "https://northwind.example/orion-3", hoursAgo: 3)
        try await store.add("Daily Tech", "Helix acquires Quartzline for $2.1B", url: "https://daily.example/helix", hoursAgo: 5)
        try await store.add("Wire", "New LLM agents framework lands", url: "https://wire.example/agents", hoursAgo: 2)
        try await store.add("Wire", "The quiet death of the headphone jack", url: "https://wire.example/jack", hoursAgo: 1)
        _ = try await store.service.process()
        return store
    }

    private func id(_ store: Store, _ headline: String) async throws -> Int64 {
        try #require(try await store.clusters.summaries(StoryFilter()).first { $0.headline == headline }).id
    }

    @Test func readSavedAndFavouriteRoundTrip() async throws {
        let store = try await seeded()
        let orion = try await id(store, "Introducing Orion 3")

        var summary = try #require(try await store.clusters.summaries(StoryFilter()).first { $0.id == orion })
        #expect(!summary.isRead && !summary.isSaved && !summary.isFavourite)

        try await store.clusters.setRead(true, clusterID: orion, at: now)
        try await store.clusters.setSaved(true, clusterID: orion, at: now)
        try await store.clusters.setFavourite(true, clusterID: orion)
        summary = try #require(try await store.clusters.summaries(StoryFilter()).first { $0.id == orion })
        #expect(summary.readAt == now)
        #expect(summary.savedAt == now)
        #expect(summary.isFavourite)

        // Each flag changes independently of the others.
        try await store.clusters.setRead(false, clusterID: orion, at: now)
        try await store.clusters.setSaved(false, clusterID: orion, at: now)
        summary = try #require(try await store.clusters.summaries(StoryFilter()).first { $0.id == orion })
        #expect(!summary.isRead && !summary.isSaved && summary.isFavourite)
    }

    @Test func keptFilterShowsSavedOrFavourite() async throws {
        let store = try await seeded()
        #expect(try await store.clusters.summaries(StoryFilter(keptOnly: true)).isEmpty)

        try await store.clusters.setSaved(true, clusterID: try await id(store, "Introducing Orion 3"), at: now)
        try await store.clusters.setFavourite(true, clusterID: try await id(store, "The quiet death of the headphone jack"))
        try await store.clusters.setRead(true, clusterID: try await id(store, "Helix acquires Quartzline for $2.1B"), at: now)

        let kept = try await store.clusters.summaries(StoryFilter(keptOnly: true))
        #expect(Set(kept.map(\.headline)) == ["Introducing Orion 3", "The quiet death of the headphone jack"])
    }

    @Test func kindFilterExcludesUnclassified() async throws {
        let store = try await seeded()
        let funding = try await store.clusters.summaries(StoryFilter(kinds: [.funding]))
        #expect(funding.map(\.headline) == ["Helix acquires Quartzline for $2.1B"])
        let two = try await store.clusters.summaries(StoryFilter(kinds: [.funding, .announcement]))
        #expect(two.count == 2)
        #expect(try await store.clusters.summaries(StoryFilter(kinds: [])).isEmpty)
    }

    @Test func subjectFilterMatchesTagsOrASourcesMainTopic() async throws {
        let store = try await seeded()
        // By tag: the agents story is tagged AI by the bundled rules.
        let tagged = try await store.clusters.summaries(StoryFilter(subject: Subjects.ai))
        #expect(tagged.map(\.headline) == ["New LLM agents framework lands"])

        // By source: everything from a source whose first topic is the subject.
        try await store.database.writer.write { db in
            try db.execute(sql: "UPDATE source SET topics = '[\"ai\",\"dev\"]' WHERE name = 'Northwind Blog'")
            try db.execute(sql: "UPDATE source SET topics = '[\"tech\",\"ai\"]' WHERE name = 'Daily Tech'")
        }
        let bySource = try await store.clusters.summaries(StoryFilter(subject: Subjects.ai))
        #expect(Set(bySource.map(\.headline)) == ["New LLM agents framework lands", "Introducing Orion 3"])

        #expect(try await store.clusters.summaries(StoryFilter(subject: .init(entityNames: []))).isEmpty)
        // A hostile topic string cannot widen the match.
        #expect(try await store.clusters.summaries(StoryFilter(subject: .init(entityNames: [], sourceTopic: "%"))).isEmpty)
    }

    @Test func filtersCombineWithSearchAndDates() async throws {
        let store = try await seeded()
        let filter = StoryFilter(since: now.addingTimeInterval(-4 * 3600), query: "orion", kinds: [.announcement])
        #expect(try await store.clusters.summaries(filter).map(\.headline) == ["Introducing Orion 3"])
        var tooRecent = filter
        tooRecent.since = now.addingTimeInterval(-3600)
        #expect(try await store.clusters.summaries(tooRecent).isEmpty)
    }

    @Test func savedStoriesSurviveRetention() async throws {
        let store = try await Store()
        try await store.add("Wire", "Keep me", url: "https://wire.example/keep", hoursAgo: 24 * 80)
        try await store.add("Wire", "Drop me", url: "https://wire.example/drop", hoursAgo: 24 * 80)
        _ = try await store.service.process()
        try await store.clusters.setSaved(true, clusterID: try await id(store, "Keep me"), at: now)

        let removed = try await store.clusters.purge(articlesBefore: now.addingTimeInterval(-24 * 3600), logsBefore: now)
        #expect(removed == 1)
        #expect(try await store.clusters.summaries(StoryFilter()).map(\.headline) == ["Keep me"])
    }

    @Test func userSourcesCanBeAddedOnceAndRemovedWithTheirStories() async throws {
        let store = try await seeded()
        let definition = SourceDefinition(kind: .rss, name: "My Blog", url: "https://me.example/feed", tier: .unverified)
        #expect(try await store.sources.addUserSource(definition))
        #expect(try await store.sources.addUserSource(definition) == false)

        let all = try await store.sources.allSources()
        #expect(all.first { $0.name == "My Blog" }?.isUserAdded == true)
        #expect(all.first { $0.name == "Wire" }?.isUserAdded == false)

        // Removing Wire takes its articles; the next processing pass removes the emptied clusters.
        let wire = try #require(all.first { $0.name == "Wire" })
        try await store.sources.delete(sourceID: wire.id)
        _ = try await store.service.process()
        let left = try await store.clusters.summaries(StoryFilter())
        #expect(Set(left.map(\.headline)) == ["Introducing Orion 3", "Helix acquires Quartzline for $2.1B"])
    }

    @Test func removingASourceRepairsClustersItSharedWithOthers() async throws {
        let store = try await Store()
        try await store.add("Northwind Blog", "Introducing Orion 3", url: "https://northwind.example/orion-3", hoursAgo: 3)
        try await store.add("Hacker News", "Orion 3", url: "https://northwind.example/orion-3", hoursAgo: 2, score: 640)
        _ = try await store.service.process()

        let blog = try #require(try await store.sources.allSources().first { $0.name == "Northwind Blog" })
        try await store.sources.delete(sourceID: blog.id)
        _ = try await store.service.process()

        let story = try #require(try await store.clusters.summaries(StoryFilter()).first)
        #expect(story.headline == "Orion 3")          // the remaining member now leads
        #expect(story.memberCount == 1)
        #expect(story.bestTier == .community)
        #expect(story.verification == .unverified)
    }

    @Test func disabledSourcesAreNotFetchedButKeepTheirStories() async throws {
        let store = try await seeded()
        let wire = try #require(try await store.sources.allSources().first { $0.name == "Wire" })
        try await store.sources.setEnabled(false, sourceID: wire.id)
        #expect(try await store.sources.enabledSources().contains { $0.id == wire.id } == false)
        #expect(try await store.clusters.summaries(StoryFilter()).count == 4)
    }
}

@Suite struct ReaderBasicsStoreTests {
    typealias Store = IntelligenceServiceTests.Store

    @Test func storiesCanBeListedForOneSource() async throws {
        let store = try await Store()
        try await store.add("Northwind Blog", "Introducing Orion 3", url: "https://northwind.example/orion-3", hoursAgo: 3)
        try await store.add("Hacker News", "Orion 3", url: "https://northwind.example/orion-3", hoursAgo: 2)
        try await store.add("Wire", "The quiet death of the headphone jack", url: "https://wire.example/jack", hoursAgo: 1)
        _ = try await store.service.process()

        let hn = store.ids["Hacker News"]!
        let fromHN = try await store.clusters.summaries(StoryFilter(sourceID: hn))
        // A story counts for a source when that source reported it, even if another source leads it.
        #expect(fromHN.map(\.headline) == ["Introducing Orion 3"])
        let fromWire = try await store.clusters.summaries(StoryFilter(sourceID: store.ids["Wire"]!))
        #expect(fromWire.map(\.headline) == ["The quiet death of the headphone jack"])
        let fromNobody = try await store.clusters.summaries(StoryFilter(sourceID: 999_999))
        #expect(fromNobody.isEmpty)
    }

    @Test func markingManyReadKeepsTheFirstReadTime() async throws {
        let store = try await Store()
        try await store.add("Wire", "One", url: "https://wire.example/1")
        try await store.add("Wire", "Two different subject", url: "https://wire.example/2")
        _ = try await store.service.process()
        let stories = try await store.clusters.summaries(StoryFilter())
        let first = try #require(stories.first { $0.headline == "One" })

        try await store.clusters.setRead(true, clusterID: first.id, at: now.addingTimeInterval(-600))
        try await store.clusters.markRead(clusterIDs: stories.map(\.id), at: now)
        try await store.clusters.markRead(clusterIDs: [], at: now)

        let after = try await store.clusters.summaries(StoryFilter())
        let allRead = after.allSatisfy { $0.isRead }
        #expect(allRead)
        let earlier = after.first(where: { $0.id == first.id })
        #expect(earlier?.readAt == now.addingTimeInterval(-600))
    }
}
