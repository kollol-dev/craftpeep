import Domain
import Foundation
@testable import Persistence
import Testing
@testable import Intelligence

let now = Date(timeIntervalSince1970: 1_794_310_000)

func digest(
    _ id: Int64,
    source: Int64,
    tier: SourceTier = .reporting,
    cluster: Int64? = nil,
    title: String,
    url: String? = nil,
    hoursAgo: Double = 1,
    score: Int? = nil
) -> ArticleDigest {
    let link = url ?? "https://site\(source).example/\(id)"
    return ArticleDigest(
        id: id, sourceID: source, sourceTier: tier, clusterID: cluster, url: link, canonicalURL: link,
        title: title, date: now.addingTimeInterval(-hoursAgo * 3600), score: score
    )
}

// MARK: - Tokens

@Suite struct TitleTokeniserTests {
    @Test func wordFormsShareAStem() {
        for forms in [["release", "releases", "released", "releasing"], ["ship", "ships", "shipped", "shipping"],
                      ["acquire", "acquires", "acquired", "acquiring"], ["company", "companies"]] {
            #expect(Set(forms.map(TitleTokeniser.stem)).count == 1, "\(forms)")
        }
    }

    @Test func dropsFillerAndKeepsNumbers() {
        let tokens = TitleTokeniser.tokens("Northwind's Orion 3 is the new model, and it's out now")
        #expect(tokens == ["northwind", "orion", "3", "model"])
    }

    @Test func announcementVerbsAreNotDistinguishing() {
        #expect(TitleTokeniser.tokens("Acme announces Widget") == TitleTokeniser.tokens("Acme launches Widget"))
    }
}

// MARK: - Clustering

@Suite struct ClustererTests {
    let clusterer = Clusterer()

    @Test func sameURLJoinsAcrossSources() {
        let assignments = clusterer.assign(
            new: [
                digest(1, source: 1, title: "Acme ships Widget 2.0", url: "https://acme.example/widget-2"),
                digest(2, source: 9, tier: .community, title: "Widget 2.0", url: "https://acme.example/widget-2")
            ],
            existing: []
        )
        #expect(assignments.map(\.target) == [.new(0), .new(0)])
    }

    @Test func joinsAnExistingClusterByURLOrTitle() {
        let existing = [digest(1, source: 1, cluster: 77, title: "Helix to acquire database startup Quartzline for $2.1bn", hoursAgo: 5)]
        let assignments = clusterer.assign(
            new: [
                digest(2, source: 2, title: "Helix acquires Quartzline for $2.1B to bolster database business", hoursAgo: 4),
                digest(3, source: 3, title: "Something else entirely happened today", hoursAgo: 4)
            ],
            existing: existing
        )
        #expect(assignments.first { $0.articleID == 2 }?.target == .existing(77))
        #expect(assignments.first { $0.articleID == 3 }?.target == .new(0))
    }

    @Test func similarTitlesFromOneSourceStayApart() {
        let assignments = clusterer.assign(
            new: [
                digest(1, source: 6, title: "This Week in Rustacean: issue 601 community digest"),
                digest(2, source: 6, title: "This Week in Rustacean: issue 602 community digest")
            ],
            existing: []
        )
        #expect(Set(assignments.map(\.target)).count == 2)
    }

    @Test func nearIdenticalSubmissionsToACommunitySourceJoin() {
        // Seen on 14 November 2026: three Hacker News submissions of the same news shown as three stories.
        let assignments = clusterer.assign(
            new: [
                digest(1, source: 9, tier: .community, title: "FAA issues national ground stop", hoursAgo: 6),
                digest(2, source: 9, tier: .community, title: "FAA Issues National Ground Stop", hoursAgo: 5),
                digest(3, source: 9, tier: .community, title: "FAA lifted National Ground Stop at 0119Z", hoursAgo: 2)
            ],
            existing: []
        )
        let target = Dictionary(uniqueKeysWithValues: assignments.map { ($0.articleID, $0.target) })
        #expect(target[1] == target[2])
        // The stop being lifted is a later development, not a duplicate, even though most words match.
        #expect(target[3] != target[1])
    }

    @Test func personalPostsJoinOnlyByLink() {
        let assignments = clusterer.assign(
            new: [
                digest(1, source: 9, tier: .community, title: "Show HN: A terminal file manager written in Go", hoursAgo: 5),
                digest(2, source: 3, tier: .reporting, title: "A terminal file manager written in Zig", hoursAgo: 4),
                digest(3, source: 9, tier: .community, title: "Show HN: A terminal file manager written in Zig", hoursAgo: 3),
                digest(4, source: 3, tier: .reporting, title: "Coverage of the Go file manager", url: "https://site9.example/1", hoursAgo: 2)
            ],
            existing: []
        )
        let target = Dictionary(uniqueKeysWithValues: assignments.map { ($0.articleID, $0.target) })
        #expect(Set([target[1], target[2], target[3]]).count == 3)
        #expect(target[4] == target[1])                         // same link: still the same story
        #expect(Clusterer.isMatchableByTitle("Ask HN: How do you keep up?") == false)
        #expect(Clusterer.isMatchableByTitle("Showcase: new HN features"))
    }

    @Test func aPublishersOwnNearIdenticalPostsStayApart() {
        let assignments = clusterer.assign(
            new: [
                digest(1, source: 2, tier: .reporting, title: "Helix quarterly earnings beat expectations", hoursAgo: 30),
                digest(2, source: 2, tier: .reporting, title: "Helix quarterly earnings beat expectations", hoursAgo: 2)
            ],
            existing: []
        )
        #expect(Set(assignments.map(\.target)).count == 2)
    }

    @Test func aCommunityDuplicateJoinsAnExistingStory() {
        let existing = [digest(1, source: 9, tier: .community, cluster: 41, title: "Kestrel 2.0 released with a rewritten query planner", hoursAgo: 8)]
        let assignments = clusterer.assign(
            new: [digest(2, source: 9, tier: .community, title: "Kestrel 2.0 Released with a Rewritten Query Planner", hoursAgo: 1)],
            existing: existing
        )
        #expect(assignments.first?.target == .existing(41))
    }

    @Test func sameHeadlineOutsideTheWindowIsADifferentStory() {
        let title = "Major Stratus Cloud outage takes down thousands of websites"
        let assignments = clusterer.assign(
            new: [digest(1, source: 1, title: title, hoursAgo: 300), digest(2, source: 2, title: title, hoursAgo: 1)],
            existing: []
        )
        #expect(Set(assignments.map(\.target)).count == 2)
    }

    @Test func everyArticleGetsExactlyOneAssignment() {
        let articles = (1...40).map { digest(Int64($0), source: Int64($0 % 5), title: "Story number \($0) about topic \($0 % 7)") }
        let assignments = clusterer.assign(new: articles, existing: [])
        #expect(assignments.count == 40)
        #expect(Set(assignments.map(\.articleID)).count == 40)
    }

    /// Pairwise precision and recall against the hand-labelled fixture. The thresholds asserted here
    /// are floors; the printed figures are what the documentation quotes.
    @Test func measuredAgainstLabelledHeadlines() throws {
        struct File: Decodable {
            struct Headline: Decodable {
                let group: Int
                let source: Int64
                let hoursAgo: Double
                let title: String
                let tier: SourceTier?
            }
            let headlines: [Headline]
        }
        let url = try #require(Bundle.module.url(forResource: "headlines", withExtension: "json", subdirectory: "Fixtures"))
        let headlines = try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).headlines

        let articles = headlines.enumerated().map { index, headline in
            digest(Int64(index), source: headline.source, tier: headline.tier ?? .reporting, title: headline.title, hoursAgo: headline.hoursAgo)
        }
        let assignments = clusterer.assign(new: articles, existing: [])
        var predicted: [Int64: ClusterAssignment.Target] = [:]
        for assignment in assignments { predicted[assignment.articleID] = assignment.target }

        var truePositives = 0, falsePositives = 0, falseNegatives = 0
        var wrongMerges: [String] = []
        for i in headlines.indices {
            for j in headlines.indices where j > i {
                let same = headlines[i].group == headlines[j].group
                let merged = predicted[Int64(i)] == predicted[Int64(j)]
                switch (same, merged) {
                case (true, true): truePositives += 1
                case (false, true):
                    falsePositives += 1
                    wrongMerges.append("\(headlines[i].title) <-> \(headlines[j].title)")
                case (true, false): falseNegatives += 1
                case (false, false): break
                }
            }
        }
        let precision = Double(truePositives) / Double(max(1, truePositives + falsePositives))
        let recall = Double(truePositives) / Double(max(1, truePositives + falseNegatives))
        print("CLUSTERING precision=\(String(format: "%.2f", precision)) recall=\(String(format: "%.2f", recall)) tp=\(truePositives) fp=\(falsePositives) fn=\(falseNegatives)")

        #expect(wrongMerges.isEmpty, "wrong merges: \(wrongMerges)")
        #expect(precision >= 0.95)
        #expect(recall >= 0.5)
    }
}

// MARK: - Rules

@Suite struct RuleTests {
    let rules: RuleSet

    init() throws {
        rules = try RuleSet.bundled()
    }

    private func kind(_ headline: String, url: String = "https://example.com/a", tier: SourceTier = .reporting) -> StoryKind? {
        Classifier.kind(headline: headline, memberURLs: [url], bestTier: tier, rules: rules.kindRules)?.kind
    }

    @Test func bundledRulesAreWellFormed() {
        #expect(Set(rules.kindRules.map(\.id)).count == rules.kindRules.count)
        #expect(Set(rules.entities.map(\.name)).count == rules.entities.count)
        for rule in rules.kindRules {
            #expect(rule.hosts != nil || rule.urlContains != nil || rule.titleAny != nil, "\(rule.id) has no condition")
        }
        for entity in rules.entities {
            #expect(!(entity.aliases ?? []).isEmpty || !(entity.exact ?? []).isEmpty, "\(entity.name) can never match")
        }
    }

    @Test func classifiesByHostURLAndTitle() {
        #expect(kind("Attention Is All You Need, Again", url: "https://arxiv.org/abs/2611.01234") == .research)
        #expect(kind("v2.0.0", url: "https://github.com/acme/widget/releases/tag/v2.0.0") == .shipping)
        #expect(kind("Kestrel 2.0 released with a rewritten query planner") == .shipping)
        #expect(kind("Ferrolabs raises $400M in Series C") == .funding)
        #expect(kind("Helix partners with Tessera on data centres") == .partnership)
        #expect(kind("Orion 3 tops the coding leaderboard") == .benchmark)
        #expect(kind("Northwind is reportedly working on a phone") == .speculation)
        #expect(kind("Introducing Orion 3", tier: .official) == .announcement)
        #expect(kind("Northwind unveils Orion 3") == .announcement)
    }

    @Test func researchIsNeverDowngraded() {
        // A paper with marketing-sounding words in its title is still research: host rules run first.
        let decision = Classifier.kind(
            headline: "Introducing a new benchmark that outperforms everything",
            memberURLs: ["https://arxiv.org/abs/2611.99999"], bestTier: .community, rules: rules.kindRules
        )
        #expect(decision?.kind == .research)
        #expect(decision?.basis == "rule:research-host")
        #expect(decision?.confidence == .high)
    }

    @Test func officialSourcesAreNotLabelledSpeculation() {
        #expect(kind("Orion 4 is expected to arrive next quarter", tier: .official) != .speculation)
        #expect(kind("Orion 4 is expected to arrive next quarter", tier: .reporting) == .speculation)
    }

    @Test(arguments: [
        "The quiet death of the headphone jack",
        "Who Gives A Crap? Hackers, apparently, after toilet paper maker's customer data exposed",
        "The backlash about data centers might really just be about electricity",
        "How we cut our build times in half",
        "Grok Build coding agent leaks confidential info"
    ])
    func leavesOrdinaryHeadlinesUnclassified(_ headline: String) {
        #expect(kind(headline) == nil)
    }

    @Test func journalNewsPagesAreNotResearchByHostAlone() {
        // Journals also publish news. Only preprint and proceedings hosts imply a paper.
        #expect(kind("To deter bioterrorism, U.S. imposes new rules on ordering DNA", url: "https://www.science.org/content/article/x", tier: .community) == nil)
        #expect(kind("A new result", url: "https://www.nature.com/articles/d41586-026-00000-0", tier: .community) == nil)
    }

    @Test func phrasesMatchWholeWordsOnly() {
        #expect(kind("Unreleased prototype spotted") == nil)       // not "released"
        #expect(kind("Membership prices rise") == nil)             // not "ships"
    }

    @Test func verificationFollowsSourceTiers() {
        #expect(Classifier.verification(tiersBySource: [1: .community, 2: .official]) == .official)
        #expect(Classifier.verification(tiersBySource: [1: .reporting, 2: .reporting]) == .corroborated)
        #expect(Classifier.verification(tiersBySource: [1: .reporting, 2: .community]) == .singleSource)
        #expect(Classifier.verification(tiersBySource: [1: .analysis]) == .singleSource)
        #expect(Classifier.verification(tiersBySource: [1: .community, 2: .unverified]) == .unverified)
    }

    @Test func tagsEntitiesWithoutFalseFriends() {
        func names(_ text: String) -> Set<String> {
            Set(Tagger.entities(in: [text], rules: rules.entities).map(\.name))
        }
        #expect(names("OpenAI and Anthropic publish joint safety evals") == ["OpenAI", "Anthropic"])
        #expect(names("Apple ships Swift 6.3 with Xcode 27") == ["Apple", "Swift"])
        #expect(names("An apple a day: swift justice for rust on old pipes") == [])
        #expect(names("Metadata standards for meta-analysis") == [])
        #expect(names("New LLM agents framework is open source").isSuperset(of: ["AI", "Open source"]))
        #expect(names("Claude Monet exhibition opens") == ["Anthropic"]) // a known false positive of name matching
    }

    @Test func derivesAClusterFromItsMembers() throws {
        let members = [
            digest(1, source: 9, tier: .community, title: "Orion 3", url: "https://northwind.example/orion-3", hoursAgo: 2, score: 640),
            digest(2, source: 1, tier: .official, title: "Introducing Orion 3", url: "https://northwind.example/orion-3", hoursAgo: 3),
            digest(3, source: 2, tier: .reporting, title: "Northwind unveils Orion 3, its most capable model", hoursAgo: 1)
        ]
        let update = try #require(ClusterDeriver.derive(id: 5, members: members, rules: rules))

        #expect(update.headline == "Introducing Orion 3") // the official source speaks first
        #expect(update.leadArticleID == 2)
        #expect(update.memberCount == 3)
        #expect(update.sourceCount == 3)
        #expect(update.independentSourceCount == 2) // the aggregator is not independent coverage
        #expect(update.bestTier == .official)
        #expect(update.verification == .official)
        #expect(update.kind == .announcement)
        #expect(update.kindBasis == "rule:announcement-official")
        #expect(update.score == 640)
        #expect(update.firstSeenAt == now.addingTimeInterval(-3 * 3600))
        #expect(update.lastSeenAt == now.addingTimeInterval(-3600))
        #expect(ClusterDeriver.derive(id: 5, members: [], rules: rules) == nil)
    }
}

// MARK: - Ranking

@Suite struct RankerTests {
    let ranker = Ranker()

    private func story(
        _ id: Int64,
        _ headline: String = "A story",
        tier: SourceTier = .reporting,
        independent: Int = 1,
        kind: StoryKind? = nil,
        points: Int? = nil,
        hoursAgo: Double = 1,
        entities: [String] = []
    ) -> ClusterSummary {
        let date = now.addingTimeInterval(-hoursAgo * 3600)
        return ClusterSummary(
            id: id, headline: headline, url: "https://example.com/\(id)", firstSeenAt: date, lastSeenAt: date,
            sourceCount: independent, independentSourceCount: independent, bestTier: tier, kind: kind,
            score: points, entities: entities
        )
    }

    @Test func eachFactorMovesAStoryUpAndExplainsItself() throws {
        let plain = try #require(ranker.rank(story(1), interests: [], now: now))
        #expect(plain.reasons.isEmpty)

        let official = try #require(ranker.rank(story(2, tier: .official), interests: [], now: now))
        #expect(official.score > plain.score)
        #expect(official.reasons == ["Official source"])

        let covered = try #require(ranker.rank(story(3, independent: 4), interests: [], now: now))
        #expect(covered.score > plain.score)
        #expect(covered.reasons == ["Covered by 4 sources"])

        let popular = try #require(ranker.rank(story(4, points: 640), interests: [], now: now))
        #expect(popular.score > plain.score)
        #expect(popular.reasons == ["640 points on Hacker News"])

        let shipped = try #require(ranker.rank(story(5, kind: .shipping), interests: [], now: now))
        #expect(shipped.score > plain.score)
        #expect(shipped.reasons == ["Available now"])

        let rumour = try #require(ranker.rank(story(6, kind: .speculation), interests: [], now: now))
        #expect(rumour.score < plain.score)
        #expect(rumour.reasons.isEmpty)
    }

    @Test func popularityAloneDoesNotBeatAnOfficialMultiSourceStory() {
        let ranked = ranker.rank(
            [story(1, tier: .community, points: 2000), story(2, tier: .official, independent: 3, kind: .shipping)],
            interests: [], now: now
        )
        #expect(ranked.map(\.id) == [2, 1])
    }

    @Test func interestsBoostAndMutesRemove() {
        let stories = [
            story(1, "Kestrel 2.0 released", entities: []),
            story(2, "Swift 6.3 lands", entities: ["Swift"]),
            story(3, "Celebrity gadget roundup", entities: [])
        ]
        let interests = [
            Interest(keyword: "swift", level: .priority),
            Interest(keyword: "Kestrel", level: .followed),
            Interest(keyword: "celebrity", level: .muted)
        ]
        let ranked = ranker.rank(stories, interests: interests, now: now)

        #expect(ranked.map(\.id) == [2, 1])
        #expect(ranked[0].reasons.first == "Matches your priority interest: swift")
        #expect(ranked[1].reasons.first == "Matches your interest: Kestrel")
    }

    @Test func interestKeywordsMatchWholeWords() {
        let ranked = ranker.rank([story(1, "Rustacean meetup notes")], interests: [Interest(keyword: "rust", level: .muted)], now: now)
        #expect(ranked.count == 1)
    }

    @Test func olderStoriesDecay() throws {
        let fresh = try #require(ranker.rank(story(1, hoursAgo: 1), interests: [], now: now))
        let dayOld = try #require(ranker.rank(story(2, hoursAgo: 25), interests: [], now: now))
        let halfLife = try #require(ranker.rank(story(3, hoursAgo: 18), interests: [], now: now))
        let atZero = try #require(ranker.rank(story(4, hoursAgo: 0), interests: [], now: now))
        #expect(fresh.score > dayOld.score)
        #expect(abs(halfLife.score - atZero.score / 2) < 0.001)
    }

    @Test func reasonsAreCappedAtThreeStrongestFirst() throws {
        let busy = story(1, "Swift thing", tier: .official, independent: 5, kind: .shipping, points: 900, entities: ["Swift"])
        let ranked = try #require(ranker.rank(busy, interests: [Interest(keyword: "Swift", level: .priority)], now: now))
        #expect(ranked.reasons.count == 3)
        #expect(ranked.reasons[0] == "Matches your priority interest: Swift")
    }
}

// MARK: - End to end against a real database

@Suite struct IntelligenceServiceTests {
    struct Store {
        let database: AppDatabase
        let sources: GRDBSourceRepository
        let articles: GRDBArticleRepository
        let clusters: GRDBClusterRepository
        let interests: GRDBInterestRepository
        let service: IntelligenceService
        let ids: [String: Int64]

        init() async throws {
            database = try AppDatabase()
            sources = GRDBSourceRepository(database: database)
            articles = GRDBArticleRepository(database: database)
            clusters = GRDBClusterRepository(database: database)
            interests = GRDBInterestRepository(database: database)
            service = IntelligenceService(clusters: clusters, interests: interests, rules: try RuleSet.bundled(), now: { now })
            try await sources.seed([
                SourceDefinition(kind: .rss, name: "Northwind Blog", url: "https://northwind.example/feed", tier: .official),
                SourceDefinition(kind: .rss, name: "Daily Tech", url: "https://daily.example/feed", tier: .reporting),
                SourceDefinition(kind: .rss, name: "Wire", url: "https://wire.example/feed", tier: .reporting),
                SourceDefinition(kind: .hackerNews, name: "Hacker News", url: "https://hn.example/api", tier: .community)
            ])
            ids = Dictionary(uniqueKeysWithValues: try await sources.allSources().map { ($0.name, $0.id) })
        }

        func add(_ source: String, _ title: String, url: String, hoursAgo: Double = 2, score: Int? = nil) async throws {
            let date = now.addingTimeInterval(-hoursAgo * 3600)
            _ = try await articles.upsert([NewArticle(
                sourceID: ids[source]!, externalID: nil, url: url, canonicalURL: url, title: title, excerpt: "Excerpt for \(title)",
                author: nil, publishedAt: date, retrievedAt: now, contentHash: title, score: score,
                discussionURL: source == "Hacker News" ? "https://hn.example/item?id=\(abs(title.hashValue))" : nil
            )])
        }
    }

    @Test func clustersClassifiesAndRanksStoredArticles() async throws {
        let store = try await Store()
        try await store.add("Northwind Blog", "Introducing Orion 3", url: "https://northwind.example/orion-3", hoursAgo: 3)
        try await store.add("Hacker News", "Orion 3", url: "https://northwind.example/orion-3", hoursAgo: 2, score: 640)
        try await store.add("Daily Tech", "Helix to acquire database startup Quartzline for $2.1bn", url: "https://daily.example/helix", hoursAgo: 5)
        try await store.add("Wire", "Helix acquires Quartzline for $2.1B to bolster database business", url: "https://wire.example/helix", hoursAgo: 4)
        try await store.add("Wire", "The quiet death of the headphone jack", url: "https://wire.example/jack", hoursAgo: 1)

        let report = try await store.service.process()
        #expect(report.articlesClustered == 5)
        #expect(report.clustersCreated == 3)

        let ranked = try await store.service.rankedStories(since: .distantPast, limit: 10)
        #expect(ranked.map(\.summary.headline) == [
            "Introducing Orion 3",
            "Helix to acquire database startup Quartzline for $2.1bn",
            "The quiet death of the headphone jack"
        ])

        let orion = ranked[0].summary
        #expect(orion.sourceNames == ["Hacker News", "Northwind Blog"])
        #expect(orion.sourceCount == 2)
        #expect(orion.independentSourceCount == 1)
        #expect(orion.verification == .official)
        #expect(orion.kind == .announcement)
        #expect(orion.score == 640)
        #expect(orion.discussionURL?.hasPrefix("https://hn.example/item") == true)
        #expect(orion.url == "https://northwind.example/orion-3")
        #expect(ranked[0].reasons.contains("Official source"))
        #expect(!ranked[0].reasons.contains { $0.hasPrefix("Covered by") })

        let helix = ranked[1].summary
        #expect(helix.verification == .corroborated)
        #expect(helix.kind == .funding)
        #expect(ranked[1].reasons == ["Covered by 2 sources"])

        #expect(ranked[2].summary.kind == nil)
        #expect(ranked[2].summary.verification == .singleSource)

        let members = try await store.clusters.stories(inCluster: orion.id)
        #expect(members.map(\.sourceName) == ["Northwind Blog", "Hacker News"]) // most authoritative first
    }

    @Test func laterArticlesJoinExistingClustersAndReprocessingIsIdempotent() async throws {
        let store = try await Store()
        try await store.add("Daily Tech", "Helix to acquire database startup Quartzline for $2.1bn", url: "https://daily.example/helix", hoursAgo: 5)
        _ = try await store.service.process()

        let again = try await store.service.process()
        #expect(again.articlesClustered == 0)

        try await store.add("Wire", "Helix acquires Quartzline for $2.1B to bolster database business", url: "https://wire.example/helix", hoursAgo: 1)
        let report = try await store.service.process()
        #expect(report.joinedExisting == 1)
        #expect(report.clustersCreated == 0)

        let stories = try await store.service.latestStories(since: .distantPast, limit: 10)
        #expect(stories.count == 1)
        #expect(stories[0].summary.memberCount == 2)
        #expect(stories[0].summary.verification == .corroborated)
        #expect(stories[0].summary.lastSeenAt == now.addingTimeInterval(-3600))
    }

    @Test func searchFindsAClusterThroughAnyMember() async throws {
        let store = try await Store()
        try await store.add("Northwind Blog", "Introducing Orion 3", url: "https://northwind.example/orion-3")
        try await store.add("Hacker News", "Northwind flagship discussion", url: "https://northwind.example/orion-3")
        try await store.add("Wire", "Unrelated", url: "https://wire.example/u")
        _ = try await store.service.process()

        let found = try await store.service.rankedStories(since: .distantPast, matching: "flagship", limit: 10)
        #expect(found.map(\.summary.headline) == ["Introducing Orion 3"])
        #expect(try await store.service.rankedStories(since: .distantPast, matching: "\"*", limit: 10).isEmpty)
    }

    @Test func interestsPersistAndAffectResults() async throws {
        let store = try await Store()
        try await store.add("Wire", "Kestrel 2.0 released", url: "https://wire.example/kestrel")
        try await store.add("Wire", "Celebrity gadget roundup", url: "https://wire.example/celebrity")
        _ = try await store.service.process()

        try await store.interests.set(Interest(keyword: "Celebrity", level: .followed))
        try await store.interests.set(Interest(keyword: "celebrity", level: .muted)) // same keyword, case-insensitively
        try await store.interests.set(Interest(keyword: "  ", level: .followed))
        #expect(try await store.interests.allInterests() == [Interest(keyword: "Celebrity", level: .muted)])
        #expect(try await store.service.rankedStories(since: .distantPast, limit: 10).count == 1)
        #expect(try await store.service.latestStories(since: .distantPast, limit: 10).count == 1)

        try await store.interests.remove(keyword: "CELEBRITY")
        #expect(try await store.service.rankedStories(since: .distantPast, limit: 10).count == 2)
    }

    @Test func retentionRemovesOldArticlesAndEmptyClusters() async throws {
        let store = try await Store()
        try await store.add("Wire", "Ancient story", url: "https://wire.example/old", hoursAgo: 24 * 120)
        try await store.add("Wire", "Recent story", url: "https://wire.example/new", hoursAgo: 2)
        _ = try await store.service.process()   // retention runs first, so the old article never gets a cluster
        #expect(try await store.articles.articleCount() == 1)

        try await store.add("Wire", "Another ancient story", url: "https://wire.example/old2", hoursAgo: 24 * 100)
        let report = try await store.service.process()
        #expect(report.articlesPurged == 1)
        #expect(try await store.service.latestStories(since: .distantPast, limit: 10).map(\.summary.headline) == ["Recent story"])

        let clusterCount = try await store.database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cluster") ?? -1
        }
        #expect(clusterCount == 1)
    }

    @Test func reclassifyAppliesCurrentRulesToStoredClusters() async throws {
        let store = try await Store()
        try await store.add("Wire", "Kestrel 2.0 released", url: "https://wire.example/kestrel")
        _ = try await store.service.process()

        // Simulate rules that used to say nothing about this story.
        let silent = IntelligenceService(
            clusters: store.clusters, interests: store.interests,
            rules: RuleSet(entities: [], kindRules: []), now: { now }
        )
        try await silent.reclassify(since: .distantPast)
        #expect(try await store.service.latestStories(since: .distantPast, limit: 1).first?.summary.kind == nil)

        try await store.service.reclassify(since: .distantPast)
        #expect(try await store.service.latestStories(since: .distantPast, limit: 1).first?.summary.kind == .shipping)
    }
}
