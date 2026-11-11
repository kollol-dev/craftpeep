import AI
import AppKit
import Domain
import Foundation
import Ingestion
import Intelligence
import Observation
import Persistence
import WidgetExpr
import WidgetRender
import WidgetRuntime
import WidgetSpec

/// One row in a story list: a story and why it is where it is.
struct StoryItem: Identifiable, Equatable {
    var summary: ClusterSummary
    var reasons: [String]

    var id: Int64 { summary.id }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview, ai, news, saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .ai: "AI Intelligence"
        case .news: "Technology News"
        case .saved: "Saved"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "sparkles.rectangle.stack"
        case .ai: "brain"
        case .news: "newspaper"
        case .saved: "bookmark"
        }
    }
}

enum StoryOrder: String, CaseIterable, Identifiable {
    case top = "Top"
    case latest = "Latest"

    var id: String { rawValue }
}

/// A plain count of the last day, shown above the Overview list. Not AI-generated.
struct DailyDigest: Equatable {
    var stories: Int
    var multiSource: Int
    var official: Int
    var mostMentioned: [String]
}

/// Composition root and state for the whole app. Views read the store through this;
/// they never touch adapters, the network or the database.
@Observable
final class AppModel {
    private(set) var stories: [StoryItem] = []
    private(set) var coverage: [Story] = []
    private(set) var pulse: [StoryItem] = []
    private(set) var unreadTopCount = 0
    private(set) var digest: DailyDigest?
    private(set) var sources: [Source] = []
    private(set) var interests: [Interest] = []
    private(set) var isRefreshing = false
    private(set) var newInLastRefresh: Int?
    private(set) var startupError: String?
    private(set) var loadError: String?

    // AI. Everything here stays empty until the user switches AI on in Settings.
    private(set) var summary: StorySummary?
    private(set) var summaryError: String?
    private(set) var isSummarising = false
    private(set) var briefing: Briefing?
    private(set) var briefingError: String?
    private(set) var isWritingBriefing = false
    private(set) var aiUsageToday = AIUsageTotals()
    private(set) var savedKeyKinds: Set<ProviderKind> = []
    /// True while the detail pane shows the briefing instead of a story.
    var showingBriefing = false

    // Desktop widget
    private(set) var widget = DesktopWidgetState.loading
    private var widgetStoryIDs: [String: Int64] = [:]
    private let widgetController = DesktopWidgetController()

    var section = SidebarSection.overview { didSet { if section != oldValue { selection = nil; scheduleReload() } } }
    var order = StoryOrder.top { didSet { if order != oldValue { scheduleReload() } } }
    /// Empty means every kind, including unclassified.
    var kindFilter: Set<StoryKind> = [] { didSet { if kindFilter != oldValue { scheduleReload() } } }
    var searchText = ""
    var selection: Int64? {
        didSet {
            guard selection != oldValue else { return }
            if selection != nil { showingBriefing = false }
            Task { await selectionChanged() }
        }
    }

    private struct Services {
        let sources: any SourceRepository
        let clusters: any ClusterRepository
        let interests: any InterestRepository
        let ingestion: IngestionService
        let intelligence: IntelligenceService
        let secrets: any SecretStore
        let gateway: AIGateway
        let usage: any AIUsageRepository
        let summaries: SummaryService
        let briefings: BriefingService
    }

    private let services: Services?

    private static let topWindow: TimeInterval = 3 * 24 * 3600
    private static let latestWindow: TimeInterval = 14 * 24 * 3600
    private static let schedulerTick: Duration = .seconds(300)
    /// How many of the top-ranked stories count as "important" for the unread badge.
    private static let importantCount = 20

    init() {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let database = try AppDatabase(url: directory.appendingPathComponent("CraftPeep/craftpeep.sqlite"))
            let sources = GRDBSourceRepository(database: database)
            let clusters = GRDBClusterRepository(database: database)
            let interests = GRDBInterestRepository(database: database)
            let secrets = KeychainSecretStore()
            let usage = GRDBAIUsageRepository(database: database)
            let gateway = AIGateway(settings: { AIPreferences.current() }, secrets: secrets, usage: usage)
            services = Services(
                sources: sources,
                clusters: clusters,
                interests: interests,
                ingestion: IngestionService(
                    sources: sources,
                    articles: GRDBArticleRepository(database: database),
                    http: URLSessionHTTPClient()
                ),
                intelligence: IntelligenceService(clusters: clusters, interests: interests, rules: try RuleSet.bundled()),
                secrets: secrets,
                gateway: gateway,
                usage: usage,
                summaries: SummaryService(gateway: gateway, clusters: clusters, summaries: GRDBSummaryRepository(database: database)),
                briefings: BriefingService(gateway: gateway, briefings: GRDBBriefingRepository(database: database))
            )
        } catch {
            services = nil
            startupError = "CraftPeep could not start. \(error.localizedDescription)"
        }
        // Runs for the life of the app, whether or not a window is open.
        Task { await self.run() }
    }

    var selectedItem: StoryItem? {
        stories.first { $0.id == selection }
    }

    var failingSources: [Source] {
        sources.filter { $0.enabled && $0.failCount > 0 }
    }

    var lastUpdated: Date? {
        sources.compactMap(\.lastOKAt).max()
    }

    // MARK: - Lifecycle

    private func run() async {
        guard let services else { return }
        do {
            try await services.sources.seed(SourceCatalogue.bundled())
            // The bundled rules may have changed since these stories were classified.
            try await services.intelligence.reclassify(since: Date().addingTimeInterval(-Self.latestWindow))
            try await services.intelligence.process()
        } catch {
            loadError = "Could not prepare stored stories."
        }
        await reload()
        await refreshAIStatus()
        #if DEBUG
        DebugSnapshot.scheduleIfRequested(model: self)
        #endif

        while !Task.isCancelled {
            await refresh(onlyDue: true)
            await writeBriefingIfDue()
            try? await Task.sleep(for: Self.schedulerTick, tolerance: .seconds(60))
        }
    }

    /// `onlyDue` respects each source's interval and backoff; a user-requested refresh does not.
    func refresh(onlyDue: Bool = false) async {
        guard let services, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let report = onlyDue ? try await services.ingestion.refreshDue() : try await services.ingestion.refreshAll()
            // A scheduler tick with nothing due changes nothing; leave the lists alone.
            guard !report.outcomes.isEmpty else { return }
            newInLastRefresh = report.newArticles
            try await services.intelligence.process()
            loadError = nil
        } catch {
            loadError = "Refresh failed. \(error.localizedDescription)"
        }
        await reload()
    }

    // MARK: - Loading

    private func scheduleReload() {
        Task { await reload() }
    }

    private struct Request: Equatable {
        var section: SidebarSection
        var order: StoryOrder
        var kinds: Set<StoryKind>
        var query: String
    }

    func reload() async {
        guard let services else { return }
        let request = Request(
            section: section, order: order, kinds: kindFilter,
            query: searchText.trimmingCharacters(in: .whitespaces)
        )
        let now = Date()
        var filter = StoryFilter(kinds: request.kinds.isEmpty ? nil : request.kinds)
        var ranked = true
        var showReasons = true
        var limit = 150

        switch request.section {
        case .overview:
            filter.since = now.addingTimeInterval(-Self.topWindow)
            limit = 60
        case .ai:
            filter.since = now.addingTimeInterval(-Self.topWindow)
            filter.subject = Subjects.ai
        case .news:
            ranked = request.order == .top
            filter.since = now.addingTimeInterval(ranked ? -Self.topWindow : -Self.latestWindow)
            limit = ranked ? 150 : 500
        case .saved:
            filter.keptOnly = true
            ranked = false
            limit = 1000
        }
        if !request.query.isEmpty {
            // Search covers everything stored for the section, newest first.
            filter.query = request.query
            filter.since = .distantPast
            ranked = false
            limit = 300
        }
        showReasons = ranked

        do {
            let found = ranked
                ? try await services.intelligence.rankedStories(filter, limit: limit)
                : try await services.intelligence.latestStories(filter, limit: limit)
            let top = try await services.intelligence.rankedStories(
                StoryFilter(since: now.addingTimeInterval(-Self.topWindow)), limit: Self.importantCount
            )
            let lastDay = try await services.clusters.summaries(StoryFilter(since: now.addingTimeInterval(-24 * 3600)))
            let allSources = try await services.sources.allSources()
            let allInterests = try await services.interests.allInterests()

            // A slower, older request must not overwrite a newer one.
            let current = Request(
                section: section, order: order, kinds: kindFilter,
                query: searchText.trimmingCharacters(in: .whitespaces)
            )
            guard request == current else { return }

            stories = found.map { StoryItem(summary: $0.summary, reasons: showReasons ? $0.reasons : []) }
            let unread = top.filter { !$0.summary.isRead }
            unreadTopCount = unread.count
            pulse = unread.prefix(5).map { StoryItem(summary: $0.summary, reasons: $0.reasons) }
            digest = Self.makeDigest(lastDay)
            sources = allSources
            interests = allInterests
            if let selection, !stories.contains(where: { $0.id == selection }) { self.selection = nil }
        } catch {
            loadError = "Could not read stored stories."
        }
        await refreshWidget()
    }

    private static func makeDigest(_ stories: [ClusterSummary]) -> DailyDigest? {
        guard !stories.isEmpty else { return nil }
        var mentions: [String: Int] = [:]
        for story in stories {
            for entity in story.entities { mentions[entity, default: 0] += 1 }
        }
        let most = mentions.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(4).map(\.key)
        return DailyDigest(
            stories: stories.count,
            multiSource: stories.filter { $0.independentSourceCount > 1 }.count,
            official: stories.filter { $0.verification == .official }.count,
            mostMentioned: Array(most)
        )
    }

    // MARK: - Selection and story actions

    private func selectionChanged() async {
        coverage = []
        summary = nil
        summaryError = nil
        guard let services, let id = selection else { return }
        coverage = (try? await services.clusters.stories(inCluster: id)) ?? []
        guard selection == id else { return }
        // Only a summary already written is shown here. Writing one costs money and waits to be asked.
        if let item = selectedItem {
            let cached = try? await services.summaries.cachedSummary(for: item.summary)
            if selection == id { summary = cached }
        }
        if selectedItem?.summary.isRead == false {
            await update(id) { summary, now in
                try await services.clusters.setRead(true, clusterID: id, at: now)
                summary.readAt = now
            }
        }
    }

    /// Applies a change to the store and to the visible rows without reordering the list.
    private func update(_ id: Int64, _ change: (inout ClusterSummary, Date) async throws -> Void) async {
        guard var summary = (stories.first { $0.id == id } ?? pulse.first { $0.id == id })?.summary else { return }
        let wasRead = summary.isRead
        do {
            try await change(&summary, Date())
        } catch {
            loadError = "Could not save that change."
            return
        }
        if let index = stories.firstIndex(where: { $0.id == id }) { stories[index].summary = summary }
        if let index = pulse.firstIndex(where: { $0.id == id }) {
            if summary.isRead { pulse.remove(at: index) } else { pulse[index].summary = summary }
        }
        if wasRead != summary.isRead {
            // The badge counts the important stories only; recount rather than guess.
            await recountUnread()
        }
    }

    private func recountUnread() async {
        guard let services else { return }
        let top = (try? await services.intelligence.rankedStories(
            StoryFilter(since: Date().addingTimeInterval(-Self.topWindow)), limit: Self.importantCount
        )) ?? []
        let unread = top.filter { !$0.summary.isRead }
        unreadTopCount = unread.count
        pulse = unread.prefix(5).map { StoryItem(summary: $0.summary, reasons: $0.reasons) }
    }

    func toggleSaved(_ id: Int64? = nil) async {
        guard let services, let id = id ?? selection else { return }
        await update(id) { summary, now in
            let saved = !summary.isSaved
            try await services.clusters.setSaved(saved, clusterID: id, at: now)
            summary.savedAt = saved ? now : nil
        }
    }

    func toggleFavourite(_ id: Int64? = nil) async {
        guard let services, let id = id ?? selection else { return }
        await update(id) { summary, _ in
            let favourite = !summary.isFavourite
            try await services.clusters.setFavourite(favourite, clusterID: id)
            summary.isFavourite = favourite
        }
    }

    func markSelectedUnread() async {
        guard let services, let id = selection else { return }
        await update(id) { summary, now in
            try await services.clusters.setRead(false, clusterID: id, at: now)
            summary.readAt = nil
        }
    }

    func markRead(_ id: Int64) async {
        guard let services else { return }
        await update(id) { summary, now in
            try await services.clusters.setRead(true, clusterID: id, at: now)
            summary.readAt = now
        }
    }

    func openSelected() {
        if let url = selectedItem?.summary.url { Self.openWebLink(url) }
    }

    func openSelectedDiscussion() {
        if let url = selectedItem?.summary.discussionURL { Self.openWebLink(url) }
    }

    /// Stored links are already limited to the web; check again at the point of use.
    static func openWebLink(_ string: String) {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Desktop widget

    /// Gives a widget the same stories, ranking and mutes the main window uses.
    private struct StoreStories: WidgetStorySource {
        let intelligence: IntelligenceService

        func stories(_ filter: StoryFilter, ranked: Bool, limit: Int) async throws -> [ClusterSummary] {
            let found = ranked
                ? try await intelligence.rankedStories(filter, limit: limit)
                : try await intelligence.latestStories(filter, limit: limit)
            return found.map(\.summary)
        }
    }

    /// Recomputes what the desktop widget shows and makes its window match the user's choice.
    func refreshWidget() async {
        let preferences = WidgetPreferences.current()
        widgetController.sync(model: self, preferences: preferences)
        guard preferences.isEnabled || WidgetPreferences.alwaysResolve, let services else { return }
        do {
            let definition = try BundledWidgets.newsList()
            let snapshot = await WidgetRuntime.resolve(
                definition,
                settings: ["subject": .string(preferences.subject), "showSources": .bool(preferences.showSources)],
                source: StoreStories(intelligence: services.intelligence),
                subjects: ["ai": Subjects.ai]
            )
            // Remember which story each link belongs to, so opening one can mark it read.
            var ids: [String: Int64] = [:]
            if case .array(let stories)? = snapshot.scope.variables["data"].flatMap({ value -> ExprValue? in
                if case .object(let data) = value { return data["stories"] }
                return nil
            }) {
                for case .object(let story) in stories {
                    if case .string(let url)? = story["url"], case .number(let id)? = story["id"] { ids[url] = Int64(id) }
                }
            }
            widgetStoryIDs = ids

            let result = RenderTree.build(definition, size: preferences.size, scope: snapshot.scope)
            if let issue = snapshot.issues.first ?? result.issues.first {
                widget = .failed(issue)
            } else if snapshot.hasNoStories {
                widget = .empty
            } else if let root = result.root {
                widget = .ready(root, asOf: lastUpdated)
            } else {
                widget = .failed("The widget has nothing to draw.")
            }
        } catch {
            widget = .failed("The widget could not be loaded.")
        }
    }

    func perform(_ action: RenderAction) {
        switch action {
        case .openURL(let url):
            Self.openWebLink(url)
            if let id = widgetStoryIDs[url] { Task { await markRead(id); await refreshWidget() } }
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .refresh:
            Task { await refresh() }
        }
    }

    // MARK: - AI

    var isAIEnabled: Bool { AIPreferences.current().isEnabled }

    func refreshAIStatus() async {
        guard let services else { return }
        savedKeyKinds = Set(ProviderKind.allCases.filter {
            (try? services.secrets.secret(for: AIGateway.keyAccount(for: $0)))?.isEmpty == false
        })
        aiUsageToday = (try? await services.usage.totals(since: Calendar.current.startOfDay(for: Date()))) ?? AIUsageTotals()
        briefing = try? await services.briefings.todaysBriefing()
    }

    func summariseSelected() async {
        guard let services, let item = selectedItem, !isSummarising else { return }
        isSummarising = true
        summaryError = nil
        defer { isSummarising = false }
        do {
            let written = try await services.summaries.summarise(item.summary)
            if selection == item.id { summary = written }
        } catch {
            if selection == item.id { summaryError = Self.message(for: error) }
        }
        await refreshAIStatus()
    }

    func writeBriefing() async {
        guard let services, !isWritingBriefing else { return }
        isWritingBriefing = true
        briefingError = nil
        defer { isWritingBriefing = false }
        do {
            // The app chooses the stories; the model only explains them.
            let ranked = try await services.intelligence.rankedStories(
                StoryFilter(since: Date().addingTimeInterval(-36 * 3600)), limit: 14
            )
            briefing = try await services.briefings.generate(from: ranked.map(\.summary))
        } catch {
            briefingError = Self.message(for: error)
        }
        await refreshAIStatus()
    }

    /// Writes today's briefing once, after seven in the morning, if the user asked for that.
    private func writeBriefingIfDue() async {
        guard AIPreferences.current().isEnabled, AIPreferences.automaticBriefing, briefing == nil, briefingError == nil,
              Calendar.current.component(.hour, from: Date()) >= 7 else { return }
        await writeBriefing()
    }

    func story(for clusterID: Int64) -> StoryItem? {
        stories.first { $0.id == clusterID }
    }

    /// Returns a message when the key could not be stored.
    func saveKey(_ key: String, for kind: ProviderKind) async -> String? {
        guard let services else { return "CraftPeep is not running." }
        do {
            try services.secrets.setSecret(key.trimmingCharacters(in: .whitespacesAndNewlines), for: AIGateway.keyAccount(for: kind))
        } catch {
            return "The Keychain did not accept the key."
        }
        await refreshAIStatus()
        return nil
    }

    func removeKey(for kind: ProviderKind) async {
        guard let services else { return }
        try? services.secrets.setSecret(nil, for: AIGateway.keyAccount(for: kind))
        await refreshAIStatus()
    }

    func testAIConnection() async -> String {
        guard let services else { return "CraftPeep is not running." }
        defer { Task { await refreshAIStatus() } }
        do {
            let response = try await services.gateway.complete(AIRequest(
                feature: .connectionTest, system: "This is a connection test.", user: "Reply with the single word OK.",
                maxOutputTokens: 2_000, effort: .low
            ))
            return "Connected. \(response.model) replied."
        } catch {
            return Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> String {
        (error as? ProviderError)?.description ?? "Something went wrong. \(error.localizedDescription)"
    }

    // MARK: - Settings actions

    func setEnabled(_ enabled: Bool, source: Source) async {
        guard let services else { return }
        try? await services.sources.setEnabled(enabled, sourceID: source.id)
        sources = (try? await services.sources.allSources()) ?? sources
    }

    /// Returns a message for the user when the feed cannot be added.
    func addFeed(name: String, url: String) async -> String? {
        guard let services else { return "CraftPeep is not running." }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmedURL), parsed.scheme?.lowercased() == "https",
              let host = parsed.host(), !host.isEmpty else {
            return "Enter a full feed address starting with https://"
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let definition = SourceDefinition(
            kind: .rss,
            name: trimmedName.isEmpty ? host : String(trimmedName.prefix(80)),
            url: parsed.absoluteString,
            siteURL: "https://\(host)",
            // Nothing the user adds is trusted until they say so.
            tier: .unverified
        )
        do {
            guard try await services.sources.addUserSource(definition) else { return "That feed is already in your sources." }
        } catch {
            return "Could not add the feed."
        }
        await refresh(onlyDue: true)
        await reload()
        if let added = sources.first(where: { $0.url == definition.url }), let error = added.lastError {
            return "Added, but the first fetch failed: \(error)"
        }
        return nil
    }

    func removeSource(_ source: Source) async {
        guard let services, source.isUserAdded else { return }
        try? await services.sources.delete(sourceID: source.id)
        _ = try? await services.intelligence.process()
        await reload()
    }

    func setInterest(_ keyword: String, level: Interest.Level) async {
        guard let services else { return }
        try? await services.interests.set(Interest(keyword: keyword, level: level))
        await reload()
    }

    func removeInterest(_ interest: Interest) async {
        guard let services else { return }
        try? await services.interests.remove(keyword: interest.keyword)
        await reload()
    }
}
