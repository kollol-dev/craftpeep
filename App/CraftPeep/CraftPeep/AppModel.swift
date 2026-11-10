import Domain
import Foundation
import Ingestion
import Intelligence
import Observation
import Persistence

/// One row in the story list: a story, why it is where it is, and nothing from the engine's internals.
struct StoryItem: Identifiable, Equatable {
    let summary: ClusterSummary
    let reasons: [String]

    var id: Int64 { summary.id }
}

enum StoryOrder: String, CaseIterable, Identifiable {
    case top = "Top"
    case latest = "Latest"

    var id: String { rawValue }
}

/// Composition root and state for the story list. Views read the store through this;
/// they never touch adapters or the network.
@Observable
final class AppModel {
    private(set) var stories: [StoryItem] = []
    private(set) var sources: [Source] = []
    private(set) var isRefreshing = false
    private(set) var newInLastRefresh: Int?
    private(set) var startupError: String?
    private(set) var loadError: String?
    var searchText = ""
    var order = StoryOrder.top

    private struct Services {
        let sources: any SourceRepository
        let clusters: any ClusterRepository
        let ingestion: IngestionService
        let intelligence: IntelligenceService
    }

    private let services: Services?
    private var didStart = false

    /// How far back each view looks.
    private static let topWindow: TimeInterval = 3 * 24 * 3600
    private static let latestWindow: TimeInterval = 14 * 24 * 3600
    /// How often the background loop checks whether any source is due.
    private static let schedulerTick: Duration = .seconds(300)

    init() {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let database = try AppDatabase(url: directory.appendingPathComponent("CraftPeep/craftpeep.sqlite"))
            let sources = GRDBSourceRepository(database: database)
            let clusters = GRDBClusterRepository(database: database)
            services = Services(
                sources: sources,
                clusters: clusters,
                ingestion: IngestionService(
                    sources: sources,
                    articles: GRDBArticleRepository(database: database),
                    http: URLSessionHTTPClient()
                ),
                intelligence: IntelligenceService(
                    clusters: clusters,
                    interests: GRDBInterestRepository(database: database),
                    rules: try RuleSet.bundled()
                )
            )
        } catch {
            services = nil
            startupError = "CraftPeep could not start. \(error.localizedDescription)"
        }
    }

    var failingSources: [Source] {
        sources.filter { $0.failCount > 0 }
    }

    var lastUpdated: Date? {
        sources.compactMap(\.lastOKAt).max()
    }

    /// Seeds the default sources, shows what is stored, then keeps sources fresh for as long as
    /// the app runs. Called once; the loop ends when the calling task is cancelled.
    func start() async {
        guard let services, !didStart else { return }
        didStart = true
        do {
            try await services.sources.seed(SourceCatalogue.bundled())
            // The bundled rules may have changed since these stories were classified.
            try await services.intelligence.reclassify(since: Date().addingTimeInterval(-Self.latestWindow))
            try await services.intelligence.process()
        } catch {
            loadError = "Could not prepare stored stories."
        }
        await reload()

        while !Task.isCancelled {
            await refresh(onlyDue: true)
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
            // A scheduler tick with nothing due changes nothing; leave the list alone.
            guard !report.outcomes.isEmpty else { return }
            newInLastRefresh = report.newArticles
            try await services.intelligence.process()
            loadError = nil
        } catch {
            loadError = "Refresh failed. \(error.localizedDescription)"
        }
        await reload()
    }

    func reload() async {
        guard let services else { return }
        do {
            let query = searchText
            let order = order
            let now = Date()
            let ranked: [RankedStory]
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                ranked = try await services.intelligence.latestStories(since: .distantPast, matching: query, limit: 300)
            } else if order == .top {
                ranked = try await services.intelligence.rankedStories(since: now.addingTimeInterval(-Self.topWindow), limit: 150)
            } else {
                ranked = try await services.intelligence.latestStories(since: now.addingTimeInterval(-Self.latestWindow), limit: 500)
            }
            // A slower, older request must not overwrite a newer one.
            guard query == searchText, order == self.order else { return }
            stories = ranked.map { StoryItem(summary: $0.summary, reasons: order == .top && query.isEmpty ? $0.reasons : []) }
            sources = try await services.sources.allSources()
        } catch {
            loadError = "Could not read stored stories."
        }
    }

    /// Every source's version of one story, most authoritative first.
    func coverage(of item: StoryItem) async -> [Story] {
        guard let services else { return [] }
        return (try? await services.clusters.stories(inCluster: item.id)) ?? []
    }
}
