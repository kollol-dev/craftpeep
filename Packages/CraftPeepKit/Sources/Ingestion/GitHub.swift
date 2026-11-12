import Domain
import Foundation

/// Reads GitHub's repository search API. GitHub has no official "trending" endpoint, so CraftPeep asks
/// for candidates by search and measures star growth itself from one day to the next.
public enum GitHubSearch {
    public struct Query: Sendable, Equatable {
        public var name: String
        public var terms: String
    }

    /// The candidate sets fetched on each refresh. Three requests, well inside the unauthenticated
    /// limit of ten searches a minute.
    public static func queries(now: Date) -> [Query] {
        func day(_ daysAgo: Int) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let parts = calendar.dateComponents([.year, .month, .day], from: now.addingTimeInterval(-Double(daysAgo) * 86_400))
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        return [
            Query(name: "new", terms: "created:>\(day(30)) stars:>100"),
            Query(name: "ai", terms: "topic:llm pushed:>\(day(7)) stars:>500"),
            Query(name: "agents", terms: "topic:ai-agents pushed:>\(day(7)) stars:>300")
        ]
    }

    public static func url(for query: Query) -> URL? {
        var components = URLComponents(string: "https://api.github.com/search/repositories")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query.terms),
            URLQueryItem(name: "sort", value: "stars"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "50")
        ]
        return components?.url
    }

    /// Input is untrusted. Forks and archived repositories are left out; text is cleaned and capped.
    public static func parse(_ data: Data) throws -> [Repository] {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw IngestionError.malformed("unexpected GitHub response")
        }
        let dates = ISO8601DateFormatter()
        return response.items.compactMap { item in
            guard item.fork != true, item.archived != true, item.stargazersCount >= 0,
                  let url = URLCanonicaliser.webURL(item.htmlURL), url.host()?.lowercased() == "github.com",
                  // owner/name, both made of the characters GitHub allows.
                  item.fullName.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
            else { return nil }
            let description = item.description.map { HTMLText.truncate(HTMLText.plain($0), to: 300) }
            return Repository(
                id: item.id,
                fullName: item.fullName,
                description: description?.isEmpty == false ? description : nil,
                url: url.absoluteString,
                language: item.language.map { String($0.prefix(40)) },
                topics: (item.topics ?? []).prefix(12).map { String($0.prefix(40)) },
                stars: item.stargazersCount,
                forks: max(0, item.forksCount ?? 0),
                createdAt: item.createdAt.flatMap(dates.date(from:)),
                pushedAt: item.pushedAt.flatMap(dates.date(from:))
            )
        }
    }

    private struct Response: Decodable {
        let items: [Item]
    }

    private struct Item: Decodable {
        let id: Int64
        let fullName: String
        let htmlURL: String
        let description: String?
        let language: String?
        let topics: [String]?
        let stargazersCount: Int
        let forksCount: Int?
        let createdAt: String?
        let pushedAt: String?
        let fork: Bool?
        let archived: Bool?

        enum CodingKeys: String, CodingKey {
            case id, description, language, topics, fork, archived
            case fullName = "full_name"
            case htmlURL = "html_url"
            case stargazersCount = "stargazers_count"
            case forksCount = "forks_count"
            case createdAt = "created_at"
            case pushedAt = "pushed_at"
        }
    }
}

public struct GitHubRefreshReport: Sendable, Equatable {
    public var repositoriesSeen = 0
    public var failedQueries = 0
    /// False when the refresh was skipped because the last one was recent.
    public var ran = false
}

/// Keeps the store's picture of GitHub current. Polite by construction: a few requests, a few times a day.
public struct GitHubService: Sendable {
    public static let interval: TimeInterval = 6 * 3600
    public static let retryInterval: TimeInterval = 3600
    static let lastAttemptKey = "github.lastAttemptAt"
    static let lastSuccessKey = "github.lastSuccessAt"
    public static let lastErrorKey = "github.lastError"

    private let http: any HTTPClient
    private let store: any RepositoryStore
    private let now: @Sendable () -> Date

    public init(http: any HTTPClient, store: any RepositoryStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http
        self.store = store
        self.now = now
    }

    public func lastSuccess() async -> Date? {
        (try? await store.meta(Self.lastSuccessKey)).flatMap { $0 }.flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    public func lastError() async -> String? {
        (try? await store.meta(Self.lastErrorKey)).flatMap { $0 }
    }

    /// Fetches unless the last attempt was recent: six hours after a success, one hour after a failure.
    @discardableResult
    public func refreshIfDue() async throws -> GitHubRefreshReport {
        let current = now()
        let lastAttempt = try await store.meta(Self.lastAttemptKey).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        let failedLastTime = try await store.meta(Self.lastErrorKey) != nil
        if let lastAttempt, current.timeIntervalSince(lastAttempt) < (failedLastTime ? Self.retryInterval : Self.interval) {
            return GitHubRefreshReport()
        }
        try await store.setMeta(String(current.timeIntervalSince1970), for: Self.lastAttemptKey)

        var report = GitHubRefreshReport(ran: true)
        var found: [Int64: Repository] = [:]
        var firstError: String?

        for query in GitHubSearch.queries(now: current) {
            do {
                guard let url = GitHubSearch.url(for: query) else { throw IngestionError.invalidURL(query.terms) }
                let result = try await http.get(url, validators: nil, accept: "application/vnd.github+json", maxBytes: IngestionService.maxResponseBytes)
                guard case .ok(let data, _) = result else { continue }
                for repository in try GitHubSearch.parse(data) { found[repository.id] = repository }
            } catch {
                report.failedQueries += 1
                let description = (error as? IngestionError)?.description ?? "request failed"
                // 403 and 429 are how GitHub says "slow down".
                firstError = firstError ?? (description.contains("403") || description.contains("429") ? "GitHub is rate limiting requests" : description)
            }
        }

        try await store.record(Array(found.values), at: current)
        report.repositoriesSeen = found.count
        // One failed query out of three still gives a useful list; only a wholly failed refresh is an error state.
        let failedEntirely = found.isEmpty && report.failedQueries > 0
        try await store.setMeta(failedEntirely ? firstError : nil, for: Self.lastErrorKey)
        if !failedEntirely {
            try await store.setMeta(String(current.timeIntervalSince1970), for: Self.lastSuccessKey)
        }
        try await store.purgeRepositories(
            notSeenSince: current.addingTimeInterval(-30 * 86_400),
            snapshotsBefore: current.addingTimeInterval(-14 * 86_400)
        )
        return report
    }
}
