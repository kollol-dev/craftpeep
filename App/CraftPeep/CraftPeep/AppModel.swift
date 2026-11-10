import Domain
import Foundation
import Ingestion
import Observation
import Persistence

/// Composition root and state for the story list. Views read the store through this;
/// they never touch adapters or the network.
@Observable
final class AppModel {
    private(set) var stories: [Story] = []
    private(set) var sources: [Source] = []
    private(set) var storyCount = 0
    private(set) var isRefreshing = false
    private var lastReport: RefreshReport?
    private(set) var startupError: String?
    private(set) var loadError: String?
    var searchText = ""

    private struct Services {
        let sources: any SourceRepository
        let articles: any ArticleRepository
        let ingestion: IngestionService
    }

    private let services: Services?
    private var didStart = false

    init() {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let database = try AppDatabase(url: directory.appendingPathComponent("CraftPeep/craftpeep.sqlite"))
            let sources = GRDBSourceRepository(database: database)
            let articles = GRDBArticleRepository(database: database)
            services = Services(
                sources: sources,
                articles: articles,
                ingestion: IngestionService(sources: sources, articles: articles, http: URLSessionHTTPClient())
            )
        } catch {
            services = nil
            startupError = "CraftPeep could not open its database. \(error.localizedDescription)"
        }
    }

    var failingSources: [Source] {
        sources.filter { $0.failCount > 0 }
    }

    var newInLastRefresh: Int? {
        lastReport?.newArticles
    }

    var lastUpdated: Date? {
        sources.compactMap(\.lastOKAt).max()
    }

    /// Seeds the default sources on first launch and shows what is already stored.
    func start() async {
        guard let services, !didStart else { return }
        didStart = true
        do {
            try await services.sources.seed(SourceCatalogue.bundled())
        } catch {
            loadError = "Could not load the default sources."
        }
        await reload()

        // Fetch on launch unless the stored stories are fresh. Scheduled refresh arrives in M3.
        let stale = lastUpdated.map { $0.timeIntervalSinceNow < -Self.launchRefreshAge } ?? true
        if stale { await refresh() }
    }

    private static let launchRefreshAge: TimeInterval = 15 * 60

    func refresh() async {
        guard let services, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            lastReport = try await services.ingestion.refreshAll()
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
            let found = try await services.articles.latestStories(limit: 500, matching: query)
            // A slower, older search must not overwrite a newer one.
            guard query == searchText else { return }
            stories = found
            sources = try await services.sources.allSources()
            storyCount = try await services.articles.articleCount()
        } catch {
            loadError = "Could not read stored stories."
        }
    }
}
