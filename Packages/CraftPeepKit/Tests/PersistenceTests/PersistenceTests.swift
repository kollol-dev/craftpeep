import Domain
import Foundation
import Testing
@testable import Persistence

private let now = Date(timeIntervalSince1970: 1_794_310_000)

private func article(
    source: Int64 = 1,
    path: String,
    title: String,
    excerpt: String? = nil,
    published: Date? = now,
    score: Int? = nil
) -> NewArticle {
    NewArticle(
        sourceID: source,
        externalID: nil,
        url: "https://example.com/\(path)",
        canonicalURL: "https://example.com/\(path)",
        title: title,
        excerpt: excerpt,
        author: nil,
        publishedAt: published,
        retrievedAt: now,
        contentHash: "\(title)|\(excerpt ?? "")",
        score: score
    )
}

private struct Store {
    let database: AppDatabase
    let sources: GRDBSourceRepository
    let articles: GRDBArticleRepository

    init(database: AppDatabase? = nil) async throws {
        self.database = try database ?? AppDatabase()
        sources = GRDBSourceRepository(database: self.database)
        articles = GRDBArticleRepository(database: self.database)
        try await sources.seed([
            SourceDefinition(kind: .rss, name: "Example", url: "https://example.com/feed", tier: .reporting, topics: ["tech"]),
            SourceDefinition(kind: .hackerNews, name: "HN", url: "https://hn.example/api", tier: .community)
        ])
    }
}

@Suite struct SourceRepositoryTests {
    @Test func seedingIsIdempotentAndKeepsExistingRows() async throws {
        let store = try await Store()
        let added = try await store.sources.seed([
            SourceDefinition(kind: .rss, name: "Renamed", url: "https://example.com/feed", tier: .official),
            SourceDefinition(kind: .rss, name: "New", url: "https://new.example/feed", tier: .unverified)
        ])
        #expect(added == 1)

        let all = try await store.sources.allSources()
        #expect(all.count == 3)
        let original = try #require(all.first { $0.url == "https://example.com/feed" })
        #expect(original.name == "Example")
        #expect(original.tier == .reporting)
        #expect(original.topics == ["tech"])
        #expect(original.enabled)
    }

    @Test func recordingOutcomesTracksHealthAndValidators() async throws {
        let store = try await Store()
        let id = try #require(try await store.sources.allSources().first { $0.name == "Example" }).id

        try await store.sources.record(FetchOutcome(sourceID: id, at: now, status: .failed(message: "boom")))
        try await store.sources.record(FetchOutcome(sourceID: id, at: now, status: .failed(message: "boom again")))
        var source = try #require(try await store.sources.allSources().first { $0.id == id })
        #expect(source.failCount == 2)
        #expect(source.lastError == "boom again")
        #expect(source.lastOKAt == nil)

        try await store.sources.record(FetchOutcome(
            sourceID: id, at: now, status: .fetched, httpStatus: 200, itemsSeen: 3, itemsNew: 3,
            validators: HTTPValidators(etag: "abc", lastModified: nil)
        ))
        source = try #require(try await store.sources.allSources().first { $0.id == id })
        #expect(source.failCount == 0)
        #expect(source.lastError == nil)
        #expect(source.lastOKAt == now)
        #expect(source.validators.etag == "abc")

        // A 304 carries no validators and must not wipe the stored ones.
        try await store.sources.record(FetchOutcome(sourceID: id, at: now, status: .notModified, httpStatus: 304))
        source = try #require(try await store.sources.allSources().first { $0.id == id })
        #expect(source.validators.etag == "abc")
    }
}

@Suite struct ArticleRepositoryTests {
    @Test func upsertInsertsOncePerSourceAndURL() async throws {
        let store = try await Store()
        let first = try await store.articles.upsert([
            article(path: "a", title: "Alpha"),
            article(path: "b", title: "Beta")
        ])
        let second = try await store.articles.upsert([
            article(path: "a", title: "Alpha"),
            article(path: "c", title: "Gamma")
        ])
        // The same page reported by a different source is a separate article; clustering joins them later.
        let third = try await store.articles.upsert([article(source: 2, path: "a", title: "Alpha on HN")])

        #expect(first == 2)
        #expect(second == 1)
        #expect(third == 1)
        #expect(try await store.articles.articleCount() == 4)
    }

    @Test func changedContentUpdatesTheRowAndTheSearchIndex() async throws {
        let store = try await Store()
        _ = try await store.articles.upsert([article(path: "a", title: "Original headline", score: 10)])
        _ = try await store.articles.upsert([article(path: "a", title: "Corrected headline", score: 25)])

        let stories = try await store.articles.latestStories(limit: 10, matching: nil)
        #expect(stories.count == 1)
        #expect(stories[0].title == "Corrected headline")
        #expect(stories[0].score == 25)

        #expect(try await store.articles.latestStories(limit: 10, matching: "corrected").count == 1)
        #expect(try await store.articles.latestStories(limit: 10, matching: "original").isEmpty)
    }

    @Test func missingScoreDoesNotEraseAStoredOne() async throws {
        let store = try await Store()
        _ = try await store.articles.upsert([article(path: "a", title: "Alpha", score: 10)])
        _ = try await store.articles.upsert([article(path: "a", title: "Alpha", score: nil)])
        #expect(try await store.articles.latestStories(limit: 1, matching: nil).first?.score == 10)
    }

    @Test func storiesAreNewestFirstWithUndatedOnesByRetrievalTime() async throws {
        let store = try await Store()
        _ = try await store.articles.upsert([
            article(path: "old", title: "Old", published: now.addingTimeInterval(-7200)),
            article(path: "undated", title: "Undated", published: nil),
            article(path: "recent", title: "Recent", published: now.addingTimeInterval(-600))
        ])

        let stories = try await store.articles.latestStories(limit: 10, matching: nil)
        #expect(stories.map(\.title) == ["Undated", "Recent", "Old"])
        #expect(stories[0].publishedAt == nil)
        #expect(stories[0].sourceName == "Example")
        #expect(stories[0].sourceTier == .reporting)
        #expect(try await store.articles.latestStories(limit: 2, matching: nil).count == 2)
    }

    @Test func fullTextSearchCoversTitleAndExcerptWithStemmingAndPrefixes() async throws {
        let store = try await Store()
        _ = try await store.articles.upsert([
            article(path: "a", title: "Acme ships Widget 2.0", excerpt: "The runtime is open source."),
            article(path: "b", title: "Benchmarks for new models", excerpt: "Shipping next week."),
            article(path: "c", title: "Unrelated funding round")
        ])

        #expect(try await store.articles.latestStories(limit: 10, matching: "runtime").map(\.title) == ["Acme ships Widget 2.0"])
        #expect(try await store.articles.latestStories(limit: 10, matching: "shipping").count == 2) // stemmed: ships, shipping
        #expect(try await store.articles.latestStories(limit: 10, matching: "bench").count == 1)   // prefix while typing
        #expect(try await store.articles.latestStories(limit: 10, matching: "widget acme").count == 1)
        #expect(try await store.articles.latestStories(limit: 10, matching: "nothinghere").isEmpty)
    }

    @Test func hostileSearchInputIsHarmless() async throws {
        let store = try await Store()
        _ = try await store.articles.upsert([article(path: "a", title: "Alpha")])

        for query in ["\"", "alpha\" OR \"", "NEAR(", "*", "a AND", "title:alpha", "'; DROP TABLE article; --"] {
            _ = try await store.articles.latestStories(limit: 10, matching: query)
        }
        #expect(try await store.articles.latestStories(limit: 10, matching: "\"*").isEmpty)
        #expect(try await store.articles.latestStories(limit: 10, matching: "   ").count == 1)
        #expect(try await store.articles.articleCount() == 1)
    }
}

@Suite struct DatabaseFileTests {
    @Test func dataSurvivesReopeningAndMigrationIsRepeatable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("craftpeep-tests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("nested/craftpeep.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let store = try await Store(database: AppDatabase(url: file))
            _ = try await store.articles.upsert([article(path: "a", title: "Persisted")])
        }

        let reopened = try await Store(database: AppDatabase(url: file))
        #expect(try await reopened.sources.allSources().count == 2)
        #expect(try await reopened.articles.latestStories(limit: 10, matching: "persisted").count == 1)
    }

    @Test func deletingASourceRemovesItsArticlesAndIndexEntries() async throws {
        let store = try await Store()
        _ = try await store.articles.upsert([article(path: "a", title: "Orphan candidate")])

        try await store.database.writer.write { db in
            try db.execute(sql: "DELETE FROM source WHERE id = 1")
        }

        #expect(try await store.articles.articleCount() == 0)
        #expect(try await store.articles.latestStories(limit: 10, matching: "orphan").isEmpty)
    }
}

@Suite struct WidgetInstanceRepositoryTests {
    @Test func instancesRoundTripUpdateAndDelete() async throws {
        let repository = GRDBWidgetInstanceRepository(database: try AppDatabase())
        #expect(try await repository.allInstances().isEmpty)

        var first = WidgetInstance(id: "a", widgetID: "com.craftpeep.news-list", settings: ["subject": .string("ai"), "showSources": .bool(false), "n": .number(3)], size: "large", createdAt: now)
        let second = WidgetInstance(id: "b", widgetID: "com.craftpeep.repository-list", createdAt: now.addingTimeInterval(60))
        try await repository.save(second)
        try await repository.save(first)
        #expect(try await repository.allInstances() == [first, second])       // oldest first

        first.x = 120
        first.y = 340.5
        first.size = "small"
        first.style = "tinted"
        first.tint = "orange"
        first.settings["subject"] = .string("all")
        try await repository.save(first)
        #expect(try await repository.allInstances().first == first)

        try await repository.delete(instanceID: "a")
        #expect(try await repository.allInstances().map(\.id) == ["b"])
    }

    @Test func unreadableSettingsFallBackToDefaultsInsteadOfFailing() async throws {
        let database = try AppDatabase()
        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO widget_instance (id, widget_id, settings, size, created_at) VALUES ('x', 'w', 'not json', 'medium', 1)")
        }
        let instance = try #require(try await GRDBWidgetInstanceRepository(database: database).allInstances().first)
        #expect(instance.settings.isEmpty)
        #expect(instance.x == nil)
        #expect(instance.style == "automatic")      // rows written before appearance existed get the defaults
        #expect(instance.tint == "blue")
    }
}
