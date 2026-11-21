import Domain
import Foundation
import Intelligence
import Persistence
import Testing
import WidgetExpr
import WidgetSpec
@testable import WidgetRender
@testable import WidgetRuntime

let now = Date(timeIntervalSince1970: 1_794_310_000)

/// Serves a fixed list and records what was asked.
actor FakeStories: WidgetStorySource {
    var stories: [ClusterSummary]
    private(set) var requests: [(filter: StoryFilter, ranked: Bool, limit: Int)] = []
    var failure = false

    init(_ stories: [ClusterSummary]) {
        self.stories = stories
    }

    func fail() { failure = true }

    func stories(_ filter: StoryFilter, ranked: Bool, limit: Int) async throws -> [ClusterSummary] {
        requests.append((filter, ranked, limit))
        if failure { throw CocoaError(.fileReadUnknown) }
        return Array(stories.prefix(limit))
    }
}

func story(_ id: Int64, _ headline: String, sources: [String] = ["Wire"], kind: StoryKind? = nil, read: Bool = false, url: String? = nil) -> ClusterSummary {
    ClusterSummary(
        id: id, headline: headline, excerpt: "Excerpt \(id)", url: url ?? "https://example.com/\(id)",
        firstSeenAt: now.addingTimeInterval(-7200), lastSeenAt: now.addingTimeInterval(-7200),
        sourceCount: sources.count, sourceNames: sources, bestTier: .reporting, kind: kind,
        readAt: read ? now : nil
    )
}

func widget(data: String = #"{"stories":{"type":"query","from":"stories"}}"#, settings: String = "[]", view: String) throws -> WidgetDefinition {
    try WidgetSpecLoader.decode(Data("""
        {"spec":"0.2","id":"com.test.widget","name":"Test","version":"1.0.0","settings":\(settings),"data":\(data),"view":{"default":\(view)}}
        """.utf8))
}

func texts(_ node: RenderNode?) -> [String] {
    guard let node else { return [] }
    return (node.text.map { [$0] } ?? []) + node.children.flatMap(texts)
}

let subjects = ["ai": Subjects.ai]

@Suite struct VocabularyTests {
    @Test func specVocabularyMatchesTheAppsOwnTypes() {
        #expect(WidgetQueryVocabulary.kinds == Set(StoryKind.allCases.map(\.rawValue)))
        #expect(WidgetQueryVocabulary.subjects == Set(subjects.keys).union(["all"]))
    }
}

@Suite struct BundledNewsListTests {
    func headlines(_ node: RenderNode?) -> [String] {
        texts(node).filter { $0.hasPrefix("Headline") || $0 == "One" }
    }

    @Test func theBundledWidgetIsValidAndAsksForNothingButTheStore() throws {
        let definition = try BundledWidgets.newsList()
        #expect(definition.spec == "0.2")
        #expect(definition.symbol == "newspaper.fill")
        #expect(definition.permissions == nil)
        #expect(definition.data?.values.allSatisfy { $0.type == .query } == true)
        #expect(definition.validate().isEmpty)
    }

    @Test func rendersEachSizeWithAFeaturedFirstStory() async throws {
        let definition = try BundledWidgets.newsList()
        var stories = (1...12).map { story(Int64($0), "Headline \($0)") }
        stories[0] = story(1, "Headline 1", sources: ["Blog", "Wire", "HN"], kind: .shipping)
        let source = FakeStories(stories)
        let snapshot = await WidgetRuntime.resolve(definition, source: source, subjects: subjects, now: now)
        #expect(snapshot.issues.isEmpty)
        #expect(!snapshot.hasNoResults)

        let request = try #require(await source.requests.first)
        #expect(request.ranked)                                              // the default view is Overview
        #expect(request.filter.since == now.addingTimeInterval(-72 * 3600))

        let context = ExprContext(now: now)
        let small = RenderTree.build(definition, size: .small, scope: snapshot.scope, context: context)
        #expect(small.issues.isEmpty)
        #expect(headlines(small.root) == ["Headline 1", "Headline 2", "Headline 3"])

        let medium = RenderTree.build(definition, size: .medium, scope: snapshot.scope, context: context)
        #expect(medium.issues.isEmpty)
        let mediumTexts = texts(medium.root)
        #expect(headlines(medium.root).count == 5)
        #expect(mediumTexts.contains("Shipping"))                            // kind tag on the featured story
        #expect(mediumTexts.contains { $0.contains("3 sources") })
        #expect(mediumTexts.contains("B"))                                   // the source's badge letter
        #expect(mediumTexts.contains { $0.hasPrefix("Wire · ") })            // compact rows say source and time

        let large = RenderTree.build(definition, size: .large, scope: snapshot.scope, context: context)
        #expect(large.issues.isEmpty)
        #expect(headlines(large.root).count == 9)
    }

    @Test func sourceBadgesAreFixedSizeTilesInTheSourcesColour() async throws {
        let definition = try BundledWidgets.newsList()
        let snapshot = await WidgetRuntime.resolve(definition, source: FakeStories([story(1, "One"), story(2, "Two")]), subjects: subjects, now: now)
        func find(_ node: RenderNode?, _ text: String) -> RenderNode? {
            guard let node else { return nil }
            if node.text == text { return node }
            for child in node.children { if let found = find(child, text) { return found } }
            return nil
        }
        let tile = try #require(find(RenderTree.build(definition, size: .small, scope: snapshot.scope).root, "W"))
        #expect(tile.width == 18 && tile.height == 18)
        #expect(tile.background == RenderColor(WidgetRuntime.color(for: "Wire")))
        #expect(tile.design == "rounded")
    }

    @Test(arguments: [
        ("overview", true, false, false, nil as String?),
        ("ai", true, true, false, nil),
        ("latest", false, false, false, nil),
        ("saved", false, false, true, nil),
        ("folder:AI Labs", false, false, false, "AI Labs")
    ])
    func eachViewSetsTheFilterAndTheOrder(_ view: String, _ ranked: Bool, _ ai: Bool, _ kept: Bool, _ folder: String?) async throws {
        let source = FakeStories([story(1, "One")])
        _ = await WidgetRuntime.resolve(try BundledWidgets.newsList(), settings: ["view": .string(view)], source: source, subjects: subjects, now: now)
        let request = try #require(await source.requests.first)
        #expect(request.ranked == ranked)
        #expect((request.filter.subject == Subjects.ai) == ai)
        #expect(request.filter.keptOnly == kept)
        #expect(request.filter.folder == folder)
    }

    @Test func anUnknownViewIsAnIssueNotACrash() async throws {
        let source = FakeStories([story(1, "One")])
        let snapshot = await WidgetRuntime.resolve(try BundledWidgets.newsList(), settings: ["view": "sports"], source: source, subjects: subjects, now: now)
        #expect(snapshot.issues == ["data.stories: unknown view 'sports'"])
        #expect(await source.requests.isEmpty)
    }

    @Test func readStoriesAreDimmedAndSourcesCanBeHidden() async throws {
        let definition = try BundledWidgets.newsList()
        let snapshot = await WidgetRuntime.resolve(
            definition, settings: ["showSources": false], source: FakeStories([story(1, "Lead"), story(2, "One", read: true)]), subjects: subjects, now: now
        )
        let result = RenderTree.build(definition, size: .medium, scope: snapshot.scope, context: ExprContext(now: now))
        func find(_ node: RenderNode?, _ text: String) -> RenderNode? {
            guard let node else { return nil }
            if node.text == text { return node }
            for child in node.children { if let found = find(child, text) { return found } }
            return nil
        }
        let read = try #require(find(result.root, "One"))
        #expect(read.color == .secondary)
        #expect(read.action == .openURL("https://example.com/2"))
        #expect(!texts(result.root).contains { $0.hasPrefix("Wire · ") })   // compact rows lose their source line
    }

    @Test func anEmptyStoreIsReportedNotHidden() async throws {
        let snapshot = await WidgetRuntime.resolve(try BundledWidgets.newsList(), source: FakeStories([]), subjects: subjects, now: now)
        #expect(snapshot.hasNoResults)
        #expect(snapshot.issues.isEmpty)
    }

    @Test func aFailingStoreBecomesAnIssue() async throws {
        let source = FakeStories([story(1, "One")])
        await source.fail()
        let snapshot = await WidgetRuntime.resolve(try BundledWidgets.newsList(), source: source, subjects: subjects, now: now)
        #expect(snapshot.issues == ["data.stories: could not read stories"])
        #expect(snapshot.hasNoResults)
    }

    @Test func viewLabelsForTheSwitcher() {
        #expect(WidgetViews.fixed.map(\.id) == ["overview", "ai", "latest", "saved"])
        #expect(WidgetViews.label(for: "latest") == "Latest")
        #expect(WidgetViews.label(for: WidgetViews.folder("AI Labs")) == "AI Labs")
        #expect(WidgetViews.label(for: "nonsense") == "Overview")
        #expect(WidgetRuntime.monogram("404 Media") == "4")
        #expect(WidgetRuntime.monogram("") == "•")
        #expect(WidgetRuntime.color(for: "The Verge") == WidgetRuntime.color(for: "the verge"))
    }
}

struct FakeRepositories: WidgetRepositorySource {
    var items: [RisingRepository]

    func repositories(language: String?, limit: Int) async throws -> [RisingRepository] {
        Array(items.filter { language == nil || $0.repository.language == language }.prefix(limit))
    }
}

func rising(_ id: Int64, _ name: String, language: String?, stars: Int, measured: Bool) -> RisingRepository {
    RisingRepository(
        repository: Repository(id: id, fullName: name, description: "About \(name)", url: "https://github.com/\(name)", language: language, stars: stars),
        starsPerDay: measured ? 300 : Double(stars) / 10,
        basis: measured ? .measured(gained: 600, overHours: 48) : .sinceCreation(days: 10)
    )
}

@Suite struct BundledRepositoryListTests {
    let items = [
        rising(1, "northwind/orion-runtime", language: "Rust", stars: 28_400, measured: false),
        rising(2, "helix-labs/kestrel", language: "Swift", stars: 5000, measured: true),
        rising(3, "o/three", language: "Rust", stars: 900, measured: false)
    ]

    @Test func everyBundledWidgetIsValidAndNeedsNoPermissions() throws {
        let all = try BundledWidgets.all()
        #expect(all.map(\.id) == ["com.craftpeep.news-list", "com.craftpeep.repository-list"])
        for definition in all {
            #expect(definition.validate().isEmpty, "\(definition.id)")
            #expect(definition.permissions == nil)
            #expect(definition.data?.values.allSatisfy { $0.type == .query } == true)
            #expect(definition.description?.isEmpty == false)
        }
    }

    @Test func rendersRepositoriesWithGrowthMarkedAsMeasuredOrEstimated() async throws {
        let definition = try BundledWidgets.repositoryList()
        let snapshot = await WidgetRuntime.resolve(
            definition, source: FakeStories([]), repositories: FakeRepositories(items: items), subjects: subjects, now: now
        )
        #expect(snapshot.issues.isEmpty)
        #expect(!snapshot.hasNoResults)

        let result = RenderTree.build(definition, size: .medium, scope: snapshot.scope, context: ExprContext(now: now))
        #expect(result.issues.isEmpty)
        let lines = texts(result.root)
        #expect(lines.contains("orion-runtime") && lines.contains("northwind"))   // featured: name and owner
        #expect(lines.contains("Estimate"))
        #expect(lines.contains { $0.contains("Rust") && $0.contains("28k stars in 10d, est.") })
        #expect(lines.contains { $0.contains("Swift") && $0.contains("+600 stars in 2d") })

        let small = RenderTree.build(definition, size: .small, scope: snapshot.scope, context: ExprContext(now: now))
        #expect(texts(small.root).filter { $0.contains("/") }.count == 3)
    }

    @Test func theLanguageSettingFiltersAndBlankMeansAny() async throws {
        let definition = try BundledWidgets.repositoryList()
        let source = FakeRepositories(items: items)
        let rust = await WidgetRuntime.resolve(definition, settings: ["language": "Rust"], source: FakeStories([]), repositories: source, subjects: subjects, now: now)
        let rustLines = texts(RenderTree.build(definition, size: .large, scope: rust.scope).root)
        #expect(rustLines.contains("orion-runtime") && rustLines.contains("o/three"))
        #expect(!rustLines.contains("kestrel") && !rustLines.contains("helix-labs/kestrel"))

        let none = await WidgetRuntime.resolve(definition, settings: ["language": "COBOL"], source: FakeStories([]), repositories: source, subjects: subjects, now: now)
        #expect(none.hasNoResults)
    }

    @Test func withoutARepositorySourceItReportsAnIssue() async throws {
        let snapshot = await WidgetRuntime.resolve(try BundledWidgets.repositoryList(), source: FakeStories([]), subjects: subjects, now: now)
        #expect(snapshot.issues == ["data.repos: repositories are not available here"])
    }

    @Test func storedSettingValuesConvert() {
        #expect(WidgetRuntime.values(["a": .bool(true), "b": .number(3), "c": .string("x")]) == ["a": true, "b": 3, "c": "x"])
    }
}

@Suite struct RuntimeTests {
    @Test func storedSettingsCannotBreakAWidget() throws {
        let definition = try widget(
            settings: #"[{"key":"subject","type":"select","label":"S","default":"all","options":[{"value":"all","label":"A"},{"value":"ai","label":"B"}]},{"key":"count","type":"number","label":"N","default":5,"min":1,"max":10},{"key":"on","type":"boolean","label":"B","default":true},{"key":"token","type":"secret","label":"T"}]"#,
            view: #"{"type":"text","text":"x"}"#
        )
        let resolved = WidgetRuntime.settings(for: definition, overrides: [
            "subject": "sports", "count": 9000, "on": "yes", "token": "s3cret", "unknown": 1
        ])
        #expect(resolved == ["subject": "all", "count": 10, "on": true])       // wrong values fall back, secrets never appear
        #expect(WidgetRuntime.settings(for: definition, overrides: ["subject": "ai", "count": 3, "on": false]) == ["subject": "ai", "count": 3, "on": false])
    }

    @Test func queryConditionsBecomeAStoreFilter() async throws {
        let definition = try widget(
            data: #"{"s":{"type":"query","from":"stories","where":{"kinds":["shipping","research"],"entities":["Swift","{{ settings.extra }}"],"sinceHours":24,"saved":true},"sort":"latest","limit":4}}"#,
            settings: #"[{"key":"extra","type":"string","label":"E","default":"Rust"}]"#,
            view: #"{"type":"text","text":"x"}"#
        )
        let source = FakeStories([])
        _ = await WidgetRuntime.resolve(definition, source: source, subjects: subjects, now: now)
        let request = try #require(await source.requests.first)
        #expect(!request.ranked)
        #expect(request.limit == 4)
        #expect(request.filter.kinds == [.shipping, .research])
        #expect(request.filter.subject == StoryFilter.Subject(entityNames: ["Swift", "Rust"]))
        #expect(request.filter.keptOnly)
        #expect(request.filter.since == now.addingTimeInterval(-24 * 3600))
    }

    @Test func anUnknownSubjectFromASettingIsAnIssueNotACrash() async throws {
        let definition = try widget(
            data: #"{"s":{"type":"query","from":"stories","where":{"subject":"{{ settings.subject }}"}}}"#,
            settings: #"[{"key":"subject","type":"string","label":"S","default":"sports"}]"#,
            view: #"{"type":"text","text":"x"}"#
        )
        let source = FakeStories([story(1, "One")])
        let snapshot = await WidgetRuntime.resolve(definition, source: source, subjects: subjects, now: now)
        #expect(snapshot.issues == ["data.s: unknown subject 'sports'"])
        #expect(await source.requests.isEmpty)
    }

    @Test func networkAndAISourcesAreNeverRun() async throws {
        let definition = try WidgetSpecLoader.decode(Data("""
            {"spec":"0.2","id":"com.test.widget","name":"T","version":"1.0.0",
             "permissions":{"network":["example.com"],"ai":true},
             "data":{"feed":{"type":"rss","url":"https://example.com/feed"},"api":{"type":"http","url":"https://example.com/x"},
                     "sum":{"type":"ai","prompt":"p"},"lookup":{"type":"static","value":{"a":1}},"clock":{"type":"time"}},
             "view":{"default":{"type":"text","text":"{{ data.lookup.a }}"}}}
            """.utf8))
        let source = FakeStories([])
        let snapshot = await WidgetRuntime.resolve(definition, source: source, subjects: subjects, now: now)
        #expect(snapshot.issues.count == 3)
        #expect(snapshot.issues.allSatisfy { $0.contains("not available") })
        #expect(await source.requests.isEmpty)
        #expect(!snapshot.hasNoResults)                                         // it never asked for stories
        #expect(texts(RenderTree.build(definition, size: .medium, scope: snapshot.scope).root) == ["1"])
    }

    @Test func worksEndToEndAgainstTheRealStore() async throws {
        struct StoreSource: WidgetStorySource {
            let service: IntelligenceService
            func stories(_ filter: StoryFilter, ranked: Bool, limit: Int) async throws -> [ClusterSummary] {
                let found = ranked ? try await service.rankedStories(filter, limit: limit) : try await service.latestStories(filter, limit: limit)
                return found.map(\.summary)
            }
        }
        let database = try AppDatabase()
        let sources = GRDBSourceRepository(database: database)
        try await sources.seed([
            SourceDefinition(kind: .rss, name: "Northwind Blog", url: "https://northwind.example/feed", tier: .official, folder: "Elsewhere"),
            SourceDefinition(kind: .rss, name: "Wire", url: "https://wire.example/feed", tier: .reporting)
        ])
        let ids = Dictionary(uniqueKeysWithValues: try await sources.allSources().map { ($0.name, $0.id) })
        func add(_ source: String, _ title: String, _ path: String) async throws {
            _ = try await GRDBArticleRepository(database: database).upsert([NewArticle(
                sourceID: ids[source]!, externalID: nil, url: "https://x.example/\(path)", canonicalURL: "https://x.example/\(path)",
                title: title, excerpt: nil, author: nil, publishedAt: now.addingTimeInterval(-3600), retrievedAt: now, contentHash: title
            )])
        }
        try await add("Wire", "The quiet death of the headphone jack", "jack")
        try await add("Northwind Blog", "Introducing Orion 3, a new LLM", "orion")
        let service = IntelligenceService(
            clusters: GRDBClusterRepository(database: database), interests: GRDBInterestRepository(database: database),
            rules: try RuleSet.bundled(), now: { now }
        )
        _ = try await service.process()

        let definition = try BundledWidgets.newsList()
        let all = await WidgetRuntime.resolve(definition, source: StoreSource(service: service), subjects: subjects, now: now)
        let allTexts = texts(RenderTree.build(definition, size: .small, scope: all.scope, context: ExprContext(now: now)).root)
        #expect(allTexts.filter { $0.count > 3 } == ["Introducing Orion 3, a new LLM", "The quiet death of the headphone jack"])  // official source ranks first

        let ai = await WidgetRuntime.resolve(definition, settings: ["view": "ai"], source: StoreSource(service: service), subjects: subjects, now: now)
        let aiTexts = texts(RenderTree.build(definition, size: .small, scope: ai.scope, context: ExprContext(now: now)).root)
        #expect(aiTexts.filter { $0.count > 3 } == ["Introducing Orion 3, a new LLM"])

        // Folders: only stories from sources filed in that folder.
        let folderView = await WidgetRuntime.resolve(definition, settings: ["view": "folder:Labs"], source: StoreSource(service: service), subjects: subjects, now: now)
        #expect(folderView.hasNoResults)
    }
}

@Suite struct RenderTreeTests {
    private func build(_ view: String, _ variables: [String: ExprValue] = [:]) throws -> RenderResult {
        RenderTree.build(try widget(view: view), size: .medium, scope: ExprScope(variables), context: ExprContext(now: now))
    }

    @Test func conditionalsListsAndLimits() throws {
        let result = try build(
            #"{"type":"vstack","children":[{"type":"text","when":"{{ show }}","text":"shown"},{"type":"text","when":"{{ hide }}","text":"hidden"},{"type":"list","each":"{{ items }}","limit":2,"item":{"type":"text","text":"{{ item }}"}}]}"#,
            ["show": true, "hide": false, "items": ["a", "b", "c"]]
        )
        #expect(texts(result.root) == ["shown", "a", "b"])
        #expect(result.issues.isEmpty)
    }

    @Test func onlyWebLinksBecomeActions() throws {
        func action(_ url: String) throws -> RenderAction? {
            try build(#"{"type":"text","text":"t","action":{"type":"openURL","value":"{{ link }}"}}"#, ["link": .string(url)]).root?.action
        }
        #expect(try action("https://example.com/a") == .openURL("https://example.com/a"))
        for hostile in ["javascript:alert(1)", "file:///etc/passwd", "craftpeep://do-something", "x-apple.systempreferences:", "", "https://"] {
            #expect(try action(hostile) == nil, "\(hostile) must not become an action")
        }
        #expect(try build(#"{"type":"button","text":"Copy","action":{"type":"copy","value":"{{ link }}"}}"#, ["link": "abc"]).root?.action == .copy("abc"))
    }

    @Test func badExpressionsDropTheNodeAndAreReported() throws {
        let result = try build(#"{"type":"vstack","children":[{"type":"text","text":"{{ missing( }}"},{"type":"text","text":"fine"}]}"#)
        #expect(texts(result.root) == ["fine"])
        #expect(result.issues.count == 1)
    }

    @Test func undrawnComponentsAreLeftOutAndSaidSo() throws {
        let result = try build(#"{"type":"vstack","children":[{"type":"chart","series":"{{ x }}"},{"type":"image","url":"https://example.com/a.png"},{"type":"text","text":"ok"}]}"#)
        #expect(texts(result.root) == ["ok"])
        #expect(result.issues.count == 2)
    }

    @Test func hostileSizesAreBounded() throws {
        let many = ExprValue.array((0..<5000).map { .number(Double($0)) })
        let result = try build(#"{"type":"list","each":"{{ items }}","limit":100000,"item":{"type":"text","text":"{{ item }}","padding":99999,"lines":99999}}"#, ["items": many])
        #expect(result.root?.children.count == RenderTree.maximumListItems)
        #expect(result.root?.children.first?.padding == 64)
        #expect(result.root?.children.first?.lines == 20)

        let long = try build(#"{"type":"text","text":"{{ t }}"}"#, ["t": .string(String(repeating: "x", count: 10_000))])
        #expect(long.root?.text?.count == RenderTree.maximumTextLength)
    }

    @Test func nestedListsCannotExceedTheNodeBudget() throws {
        let outer = ExprValue.array(Array(repeating: .array(Array(repeating: 1, count: 50)), count: 50))
        let result = try build(#"{"type":"list","each":"{{ rows }}","as":"row","item":{"type":"list","each":"{{ row }}","item":{"type":"text","text":"x"}}}"#, ["rows": outer])
        func count(_ node: RenderNode?) -> Int { node.map { 1 + $0.children.map(count).reduce(0, +) } ?? 0 }
        #expect(count(result.root) <= RenderTree.maximumNodes + 1)
    }

    @Test func listRowsKnowTheirIndex() throws {
        let result = try build(#"{"type":"list","each":"{{ items }}","item":{"type":"text","text":"{{ index == 0 ? 'first: ' : '' }}{{ item }}"}}"#, ["items": ["a", "b"]])
        #expect(texts(result.root) == ["first: a", "b"])
    }

    @Test func sizesAndDesignsAreValidatedAndClamped() throws {
        #expect(throws: WidgetSpecError.self) { try widget(view: #"{"type":"text","text":"x","width":5000}"#) }
        #expect(throws: WidgetSpecError.self) { try widget(view: #"{"type":"text","text":"x","design":"comic"}"#) }
        let node = try build(#"{"type":"text","text":"x","width":40,"height":12,"design":"serif"}"#).root
        #expect(node?.width == 40 && node?.height == 12 && node?.design == "serif")
        #expect(throws: WidgetSpecError.self) {
            try WidgetSpecLoader.decode(Data(#"{"spec":"0.2","id":"com.a.b","name":"N","version":"1.0.0","symbol":"<bad>","view":{"default":{"type":"text","text":"x"}}}"#.utf8))
        }
        #expect(throws: WidgetSpecError.self) {
            try widget(data: #"{"s":{"type":"query","from":"stories","where":{"view":"sports"}}}"#, view: #"{"type":"text","text":"x"}"#)
        }
        _ = try widget(data: #"{"s":{"type":"query","from":"stories","where":{"view":"folder:AI Labs"}}}"#, view: #"{"type":"text","text":"x"}"#)
    }

    @Test func coloursAndNumbers() throws {
        #expect(RenderColor("accent") == .accent)
        #expect(RenderColor("#FF8000") == .rgb(red: 1, green: 128.0 / 255, blue: 0))
        #expect(RenderColor("url(javascript:x)") == nil)
        #expect(RenderColor("#12") == nil)
        let number = try build(#"{"type":"number","value":"{{ n }}"}"#, ["n": 42])
        #expect(number.root?.text == "42")
    }
}
