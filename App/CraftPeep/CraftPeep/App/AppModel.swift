import AI
import AppKit
import Domain
import Foundation
import Ingestion
import Intelligence
import Observation
import Persistence
import WidgetBuilder
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
    case overview, ai, news, radar, saved
    /// One source's stories; which source is `AppModel.selectedSourceID`.
    case source

    var id: String { rawValue }

    /// The fixed sections at the top of the sidebar, in order. Sources are listed separately below them.
    static let main: [SidebarSection] = [.overview, .ai, .news, .radar, .saved]

    var title: String {
        switch self {
        case .overview: "Overview"
        case .ai: "AI Intelligence"
        case .news: "Technology News"
        case .radar: "Developer Radar"
        case .saved: "Saved"
        case .source: "Source"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "sparkles.rectangle.stack"
        case .ai: "brain"
        case .news: "newspaper"
        case .radar: "chevron.left.forwardslash.chevron.right"
        case .saved: "bookmark"
        case .source: "dot.radiowaves.up.forward"
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

    // Developer Radar
    private(set) var repositories: [RisingRepository] = []
    private(set) var repositoryLanguages: [String] = []
    private(set) var radarUpdated: Date?
    private(set) var radarError: String?
    /// Nil means every language.
    var repositoryLanguage: String? { didSet { if repositoryLanguage != oldValue { scheduleReload() } } }
    var selectedRepositoryID: Int64?

    var selectedRepository: RisingRepository? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    // Desktop widgets
    private(set) var widgets: [DesktopWidgetItem] = []
    private(set) var gallery: [WidgetDefinition] = []
    private(set) var galleryPreviews: [String: DesktopWidgetState] = [:]
    private var widgetStoryIDs: [String: Int64] = [:]

    // Widget builder (AI). A suggestion waits here until the user accepts or discards it.
    private(set) var widgetSuggestion: WidgetSuggestion?
    private(set) var widgetBuilderMessage: String?
    private(set) var isBuildingWidget = false
    private let widgetController = DesktopWidgetController()

    var section = SidebarSection.overview {
        didSet {
            guard section != oldValue else { return }
            selection = nil
            showingBriefing = false
            scheduleReload()
        }
    }
    var order = StoryOrder.top { didSet { if order != oldValue { scheduleReload() } } }
    /// Empty means every kind, including unclassified.
    var kindFilter: Set<StoryKind> = [] { didSet { if kindFilter != oldValue { scheduleReload() } } }
    var searchText = ""
    /// The source whose stories are listed when `section` is `.source`.
    var selectedSourceID: Int64? {
        didSet { if selectedSourceID != oldValue, section == .source { selection = nil; scheduleReload() } }
    }

    /// What the story list is titled: the section, or the source's name.
    var listTitle: String {
        guard section == .source else { return section.title }
        return sources.first { $0.id == selectedSourceID }?.name ?? "Source"
    }

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
        let repositories: any RepositoryStore
        let widgetInstances: any WidgetInstanceRepository
        let github: GitHubService
        let summaries: SummaryService
        let briefings: BriefingService
        let widgetBuilder: WidgetBuilder
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
            let repositories = GRDBRepositoryStore(database: database)
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
                repositories: repositories,
                widgetInstances: GRDBWidgetInstanceRepository(database: database),
                github: GitHubService(http: URLSessionHTTPClient(), store: repositories),
                summaries: SummaryService(gateway: gateway, clusters: clusters, summaries: GRDBSummaryRepository(database: database)),
                briefings: BriefingService(gateway: gateway, briefings: GRDBBriefingRepository(database: database)),
                widgetBuilder: WidgetBuilder(gateway: gateway)
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
            await refreshRadar()
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
        case .radar:
            await reloadRadar()
            return
        case .source:
            // Everything stored from this source, newest first, as in a feed reader.
            filter.sourceID = selectedSourceID ?? -1
            ranked = false
            limit = 500
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
        await refreshWidgets()
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

    /// Marks every story in the current list read: the section, source, search and filters as shown.
    func markAllRead() async {
        guard let services else { return }
        let unread = stories.filter { !$0.summary.isRead }.map(\.id)
        guard !unread.isEmpty else { return }
        let now = Date()
        do {
            try await services.clusters.markRead(clusterIDs: unread, at: now)
        } catch {
            loadError = "Could not mark the stories read."
            return
        }
        for index in stories.indices where stories[index].summary.readAt == nil {
            stories[index].summary.readAt = now
        }
        await recountUnread()
        await refreshWidgets()
    }

    var hasUnreadInList: Bool {
        stories.contains { !$0.summary.isRead }
    }

    // MARK: - OPML

    /// Adds the feeds an OPML file lists and says what happened, in a sentence or two.
    func importOPML(_ data: Data) async -> String {
        guard let services else { return "CraftPeep is not running." }
        let feeds: [OPMLFeed]
        do {
            feeds = try OPML.parse(data)
        } catch {
            return "That file is not an OPML subscription list."
        }
        let plan = OPML.plan(feeds)
        var added = 0
        var present = 0
        for definition in plan.definitions {
            if (try? await services.sources.addUserSource(definition)) == true { added += 1 } else { present += 1 }
        }
        sources = (try? await services.sources.allSources()) ?? sources
        // New sources are due at once; fetch them without making the caller wait.
        if added > 0 { Task { await refresh(onlyDue: true) } }

        var parts = [added == 1 ? "Added 1 feed." : "Added \(added) feeds."]
        if present > 0 { parts.append("\(present) were already in your sources.") }
        if plan.upgradedToHTTPS > 0 { parts.append("\(plan.upgradedToHTTPS) listed with plain http will be tried over https.") }
        if !plan.skipped.isEmpty { parts.append("Skipped \(plan.skipped.count) that are not web addresses.") }
        if added > 0 { parts.append("Feeds you add are marked Unverified.") }
        return parts.joined(separator: " ")
    }

    func exportOPML() -> Data {
        OPML.document(for: sources)
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

    // MARK: - Developer Radar

    /// Asks GitHub for candidates if enough time has passed since the last request. A handful of
    /// requests a few times a day; nothing is sent for stories or AI here.
    func refreshRadar() async {
        guard let services else { return }
        if let report = try? await services.github.refreshIfDue(), report.ran {
            if section == .radar { await reloadRadar() }
            await refreshWidgets()
        }
    }

    private func reloadRadar() async {
        guard let services else { return }
        let now = Date()
        let histories = (try? await services.repositories.histories(
            seenSince: now.addingTimeInterval(-3 * 86_400), baselineSince: now.addingTimeInterval(-7 * 86_400)
        )) ?? []
        let ranked = RepositoryRanker.rank(histories, now: now)
        repositoryLanguages = Array(Set(ranked.compactMap(\.repository.language))).sorted()
        if let language = repositoryLanguage, !repositoryLanguages.contains(language) { repositoryLanguage = nil }

        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        repositories = ranked.filter { item in
            (repositoryLanguage == nil || item.repository.language == repositoryLanguage)
                && (query.isEmpty
                    || item.repository.fullName.lowercased().contains(query)
                    || item.repository.description?.lowercased().contains(query) == true
                    || item.repository.topics.contains { $0.lowercased().contains(query) })
        }
        radarUpdated = await services.github.lastSuccess()
        radarError = await services.github.lastError()
        if let selectedRepositoryID, !repositories.contains(where: { $0.id == selectedRepositoryID }) { self.selectedRepositoryID = nil }
        sources = (try? await services.sources.allSources()) ?? sources
    }

    func releaseFeedURL(for repository: Repository) -> String {
        "https://github.com/\(repository.fullName)/releases.atom"
    }

    func isFollowingReleases(of repository: Repository) -> Bool {
        let url = releaseFeedURL(for: repository)
        return sources.contains { $0.url == url }
    }

    /// Adds the repository's own release feed as a source, so new versions arrive as stories.
    func followReleases(of repository: Repository) async -> String? {
        guard let services else { return "CraftPeep is not running." }
        let definition = SourceDefinition(
            kind: .rss, name: "\(repository.fullName) releases", url: releaseFeedURL(for: repository),
            siteURL: repository.url,
            // A project's release feed on github.com is published by the project itself.
            tier: .official, topics: ["dev"], refreshSeconds: 3600
        )
        do {
            guard try await services.sources.addUserSource(definition) else { return "You already follow these releases." }
        } catch {
            return "Could not follow the releases."
        }
        await refresh(onlyDue: true)
        sources = (try? await services.sources.allSources()) ?? sources
        return nil
    }

    // MARK: - Desktop widgets

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

    private struct StoreRepositories: WidgetRepositorySource {
        let store: any RepositoryStore

        func repositories(language: String?, limit: Int) async throws -> [RisingRepository] {
            let now = Date()
            let histories = try await store.histories(
                seenSince: now.addingTimeInterval(-3 * 86_400), baselineSince: now.addingTimeInterval(-7 * 86_400)
            )
            return Array(RepositoryRanker.rank(histories, now: now).filter { language == nil || $0.repository.language == language }.prefix(limit))
        }
    }

    private func resolve(_ definition: WidgetDefinition, settings: [String: WidgetSettingValue], size: WidgetSize) async -> (DesktopWidgetState, [String: Int64]) {
        guard let services else { return (.failed("CraftPeep is not running."), [:]) }
        let snapshot = await WidgetRuntime.resolve(
            definition,
            settings: WidgetRuntime.values(settings),
            source: StoreStories(intelligence: services.intelligence),
            repositories: StoreRepositories(store: services.repositories),
            subjects: ["ai": Subjects.ai]
        )
        // Remember which story each link belongs to, so opening one can mark it read.
        var links: [String: Int64] = [:]
        if case .object(let data)? = snapshot.variables["data"] {
            for case .array(let rows) in data.values {
                for case .object(let row) in rows {
                    if case .string(let url)? = row["url"], case .number(let id)? = row["id"], row["headline"] != nil { links[url] = Int64(id) }
                }
            }
        }
        let result = RenderTree.build(definition, size: size, scope: snapshot.scope)
        let usesRepositories = definition.data?.values.contains { $0.from == "repositories" } == true
        if let issue = snapshot.issues.first ?? result.issues.first {
            return (.failed(issue), links)
        } else if snapshot.hasNoResults {
            return (.empty(usesRepositories ? "No repositories match yet." : "No stories in the last three days."), links)
        } else if let root = result.root {
            var asOf = lastUpdated
            if usesRepositories {
                let fetched = await services.github.lastSuccess()
                asOf = fetched
            }
            return (.ready(root, asOf: asOf), links)
        }
        return (.failed("The widget has nothing to draw."), links)
    }

    /// Recomputes every desktop widget and makes the windows on screen match what is stored.
    func refreshWidgets() async {
        guard let services else { return }
        if gallery.isEmpty { gallery = (try? BundledWidgets.all()) ?? [] }
        await migrateLegacyWidgetPreference()

        let instances = (try? await services.widgetInstances.allInstances()) ?? []
        var items: [DesktopWidgetItem] = []
        var links: [String: Int64] = [:]
        for instance in instances {
            // A widget whose definition this version does not ship is skipped, not deleted.
            guard let definition = gallery.first(where: { $0.id == instance.widgetID }) else { continue }
            let size = WidgetSize(rawValue: instance.size) ?? .medium
            let (state, found) = await resolve(definition, settings: instance.settings, size: size)
            links.merge(found) { first, _ in first }
            items.append(DesktopWidgetItem(instance: instance, definition: definition, state: state))
        }
        widgets = items
        widgetStoryIDs = links
        widgetController.sync(model: self, items: items)
    }

    /// Draws each gallery widget once with its default settings, for the previews in Settings.
    func loadGalleryPreviews() async {
        if gallery.isEmpty { gallery = (try? BundledWidgets.all()) ?? [] }
        var previews: [String: DesktopWidgetState] = [:]
        for definition in gallery {
            previews[definition.id] = await resolve(definition, settings: [:], size: .medium).0
        }
        galleryPreviews = previews
    }

    func addWidget(_ definition: WidgetDefinition) async {
        guard let services else { return }
        try? await services.widgetInstances.save(
            WidgetInstance(id: UUID().uuidString, widgetID: definition.id, size: WidgetSize.medium.rawValue, createdAt: Date())
        )
        await refreshWidgets()
    }

    func removeWidget(_ id: String) async {
        guard let services else { return }
        try? await services.widgetInstances.delete(instanceID: id)
        await refreshWidgets()
    }

    private func updateWidget(_ id: String, refresh: Bool = true, _ change: (inout WidgetInstance) -> Void) async {
        guard let services, var instance = widgets.first(where: { $0.id == id })?.instance else { return }
        change(&instance)
        try? await services.widgetInstances.save(instance)
        if refresh {
            await refreshWidgets()
        } else if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].instance = instance
        }
    }

    func setWidgetAppearance(_ id: String, style: WidgetStyle? = nil, tint: WidgetTint? = nil) async {
        // Appearance changes nothing about the data, so the store is updated without re-resolving.
        await updateWidget(id, refresh: false) { instance in
            if let style { instance.style = style.rawValue }
            if let tint { instance.tint = tint.rawValue }
        }
    }

    func setWidgetSize(_ id: String, _ size: WidgetSize) async {
        await updateWidget(id) { $0.size = size.rawValue }
    }

    func setWidgetSetting(_ id: String, key: String, value: WidgetSettingValue) async {
        await updateWidget(id) { $0.settings[key] = value }
    }

    /// Called when the user has dragged a widget. Stored quietly; nothing needs redrawing.
    func widgetMoved(_ id: String, to origin: CGPoint) async {
        guard let current = widgets.first(where: { $0.id == id })?.instance,
              current.x != Double(origin.x) || current.y != Double(origin.y) else { return }
        await updateWidget(id, refresh: false) {
            $0.x = Double(origin.x)
            $0.y = Double(origin.y)
        }
    }

    /// The first widget build kept one widget's choices in preferences. Carry them over once.
    private func migrateLegacyWidgetPreference() async {
        let defaults = UserDefaults.standard
        guard let services, defaults.bool(forKey: "widget.newsList.enabled") else { return }
        defaults.set(false, forKey: "widget.newsList.enabled")
        let origin = (defaults.string(forKey: "widget.newsList.origin") ?? "").split(separator: ",").compactMap { Double($0) }
        try? await services.widgetInstances.save(WidgetInstance(
            id: UUID().uuidString, widgetID: "com.craftpeep.news-list",
            settings: [
                "subject": .string(defaults.string(forKey: "widget.newsList.subject") == "ai" ? "ai" : "all"),
                "showSources": .bool(defaults.object(forKey: "widget.newsList.showSources") as? Bool ?? true)
            ],
            size: WidgetSize(rawValue: defaults.string(forKey: "widget.newsList.size") ?? "")?.rawValue ?? "medium",
            x: origin.count == 2 ? origin[0] : nil, y: origin.count == 2 ? origin[1] : nil, createdAt: Date()
        ))
    }

    // MARK: - Widget builder

    /// Asks the model to choose a widget and settings for a description. `editing` is the widget being
    /// changed, if any. Nothing is installed here: the result waits in `widgetSuggestion`.
    func suggestWidget(for request: String, editing instanceID: String? = nil) async {
        guard let services, !isBuildingWidget else { return }
        isBuildingWidget = true
        widgetBuilderMessage = nil
        widgetSuggestion = nil
        defer { isBuildingWidget = false }
        let current = instanceID.flatMap { id in widgets.first { $0.id == id }?.instance }
        do {
            switch try await services.widgetBuilder.propose(request: request, catalogue: gallery, current: current) {
            case .nothingFits(let reason):
                widgetBuilderMessage = "No widget does that yet. \(reason)"
            case .proposal(let proposal):
                guard let definition = gallery.first(where: { $0.id == proposal.widgetID }) else {
                    widgetBuilderMessage = "The suggestion named a widget this version does not have."
                    return
                }
                let (preview, _) = await resolve(definition, settings: proposal.settings, size: proposal.size)
                widgetSuggestion = WidgetSuggestion(proposal: proposal, definition: definition, preview: preview, replacing: current?.id)
            }
        } catch {
            widgetBuilderMessage = Self.message(for: error)
        }
        await refreshAIStatus()
    }

    func acceptWidgetSuggestion() async {
        guard let services, let suggestion = widgetSuggestion else { return }
        widgetSuggestion = nil
        if let id = suggestion.replacing, let existing = widgets.first(where: { $0.id == id })?.instance {
            if existing.widgetID == suggestion.proposal.widgetID {
                var updated = existing
                updated.settings = suggestion.proposal.settings
                updated.size = suggestion.proposal.size.rawValue
                try? await services.widgetInstances.save(updated)
            } else {
                // A different kind of widget takes the old one's place on the desktop.
                try? await services.widgetInstances.delete(instanceID: id)
                try? await services.widgetInstances.save(WidgetInstance(
                    id: UUID().uuidString, widgetID: suggestion.proposal.widgetID, settings: suggestion.proposal.settings,
                    size: suggestion.proposal.size.rawValue, x: existing.x, y: existing.y, createdAt: Date()
                ))
            }
        } else {
            try? await services.widgetInstances.save(WidgetInstance(
                id: UUID().uuidString, widgetID: suggestion.proposal.widgetID, settings: suggestion.proposal.settings,
                size: suggestion.proposal.size.rawValue, createdAt: Date()
            ))
        }
        await refreshWidgets()
    }

    func discardWidgetSuggestion() {
        widgetSuggestion = nil
        widgetBuilderMessage = nil
    }

    func perform(_ action: RenderAction) {
        switch action {
        case .openURL(let url):
            Self.openWebLink(url)
            if let id = widgetStoryIDs[url] { Task { await markRead(id); await refreshWidgets() } }
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
