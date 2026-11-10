import Domain
import Foundation

public struct RefreshReport: Sendable, Equatable {
    public var startedAt: Date
    public var outcomes: [FetchOutcome]

    public var newArticles: Int { outcomes.reduce(0) { $0 + $1.itemsNew } }
    public var failures: Int { outcomes.filter(\.isFailure).count }
    public var notModified: Int { outcomes.filter { $0.status == .notModified }.count }
}

/// Runs the fetch, parse, normalise, store pipeline for every enabled source.
/// Makes no AI calls. One source failing never stops the others.
public actor IngestionService {
    public static let maxResponseBytes = 5 * 1024 * 1024
    /// Articles published longer ago than this are not stored. Matches the retention period.
    public static let maxArticleAge: TimeInterval = 90 * 24 * 3600

    private let sources: any SourceRepository
    private let articles: any ArticleRepository
    private let http: any HTTPClient
    private let adapters: [SourceKind: any SourceAdapter]
    private let now: @Sendable () -> Date
    private let maxConcurrent: Int
    private var running: Task<RefreshReport, Error>?

    public init(
        sources: any SourceRepository,
        articles: any ArticleRepository,
        http: any HTTPClient,
        adapters: [SourceKind: any SourceAdapter] = [.rss: RSSAdapter(), .hackerNews: HackerNewsAdapter()],
        maxConcurrent: Int = 6,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sources = sources
        self.articles = articles
        self.http = http
        self.adapters = adapters
        self.maxConcurrent = max(1, maxConcurrent)
        self.now = now
    }

    /// Refreshes every enabled source now, whatever its schedule. For an explicit user request.
    /// A call made while a refresh is in flight joins that refresh.
    public func refreshAll() async throws -> RefreshReport {
        try await run(onlyDue: false)
    }

    /// Refreshes the enabled sources whose interval has elapsed. Failing sources back off.
    /// Cheap to call often: when nothing is due it does no network work.
    public func refreshDue() async throws -> RefreshReport {
        try await run(onlyDue: true)
    }

    private func run(onlyDue: Bool) async throws -> RefreshReport {
        if let running { return try await running.value }

        let task = Task { try await self.performRefresh(onlyDue: onlyDue) }
        running = task
        defer { running = nil }
        return try await task.value
    }

    private func performRefresh(onlyDue: Bool) async throws -> RefreshReport {
        let startedAt = now()
        var pending = try await sources.enabledSources()
        if onlyDue { pending = pending.filter { $0.isDue(at: startedAt) } }

        let outcomes = await withTaskGroup(of: FetchOutcome.self) { group in
            var collected: [FetchOutcome] = []
            var iterator = pending.makeIterator()

            for _ in 0..<maxConcurrent {
                guard let source = iterator.next() else { break }
                group.addTask { await self.refresh(source) }
            }
            while let outcome = await group.next() {
                collected.append(outcome)
                if let source = iterator.next() {
                    group.addTask { await self.refresh(source) }
                }
            }
            return collected
        }

        for outcome in outcomes {
            try await sources.record(outcome)
        }
        return RefreshReport(startedAt: startedAt, outcomes: outcomes.sorted { $0.sourceID < $1.sourceID })
    }

    private nonisolated func refresh(_ source: Source) async -> FetchOutcome {
        let started = now()
        let clock = ContinuousClock()
        let begin = clock.now
        var outcome = FetchOutcome(sourceID: source.id, at: started, status: .notModified)

        do {
            guard let adapter = adapters[source.kind] else { throw IngestionError.noAdapter(source.kind) }
            guard let url = URL(string: source.url) else { throw IngestionError.invalidURL(source.url) }

            let result = try await http.get(
                url,
                validators: source.validators.isEmpty ? nil : source.validators,
                accept: adapter.accept,
                maxBytes: Self.maxResponseBytes
            )

            switch result {
            case .notModified:
                outcome.httpStatus = 304
            case .ok(let data, let validators):
                let raw = try adapter.parse(data, source: source)
                let cleaned = Normaliser.normalise(raw, source: source, now: started, maxAge: Self.maxArticleAge)
                outcome.itemsNew = try await articles.upsert(cleaned)
                outcome.status = .fetched
                outcome.httpStatus = 200
                outcome.itemsSeen = cleaned.count
                outcome.bytes = data.count
                outcome.validators = validators
            }
        } catch let error as IngestionError {
            outcome.status = .failed(message: error.description)
            if case .httpStatus(let code) = error { outcome.httpStatus = code }
        } catch is CancellationError {
            outcome.status = .failed(message: "Cancelled")
        } catch {
            outcome.status = .failed(message: "Could not store articles")
        }

        let elapsed = clock.now - begin
        outcome.durationMillis = Int(elapsed.components.seconds * 1000)
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        return outcome
    }
}
