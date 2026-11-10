import Domain
import Foundation

public struct ProcessReport: Sendable, Equatable {
    public var articlesClustered = 0
    public var clustersCreated = 0
    /// Articles that joined a cluster that already existed.
    public var joinedExisting = 0
    public var articlesPurged = 0

    public init() {}
}

/// Turns stored articles into stories: clusters them, classifies and tags each cluster,
/// and ranks them for display. Rules only; makes no network or AI calls.
public struct IntelligenceService: Sendable {
    public static let retention: TimeInterval = 90 * 24 * 3600
    public static let logRetention: TimeInterval = 14 * 24 * 3600

    private let clusters: any ClusterRepository
    private let interests: any InterestRepository
    private let rules: RuleSet
    private let clusterer: Clusterer
    private let ranker: Ranker
    private let now: @Sendable () -> Date

    public init(
        clusters: any ClusterRepository,
        interests: any InterestRepository,
        rules: RuleSet,
        clusterer: Clusterer = Clusterer(),
        ranker: Ranker = Ranker(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clusters = clusters
        self.interests = interests
        self.rules = rules
        self.clusterer = clusterer
        self.ranker = ranker
        self.now = now
    }

    /// Clusters any articles that are not yet in one, then recomputes the clusters that changed.
    /// Safe to call after every refresh; does nothing when there is nothing new.
    @discardableResult
    public func process() async throws -> ProcessReport {
        var report = ProcessReport()
        let current = now()
        report.articlesPurged = try await clusters.purge(
            articlesBefore: current.addingTimeInterval(-Self.retention),
            logsBefore: current.addingTimeInterval(-Self.logRetention)
        )

        let pending = try await clusters.unclusteredArticles()
        guard let earliest = pending.map(\.date).min() else { return report }

        let existing = try await clusters.clusteredArticles(since: earliest.addingTimeInterval(-clusterer.window))
        let assignments = clusterer.assign(new: pending, existing: existing)
        let touched = try await clusters.apply(assignments, at: current)
        try await rederive(touched)

        report.articlesClustered = assignments.count
        for assignment in assignments {
            if case .existing = assignment.target { report.joinedExisting += 1 }
        }
        report.clustersCreated = Set(assignments.compactMap { assignment -> Int? in
            if case .new(let key) = assignment.target { return key }
            return nil
        }).count
        return report
    }

    /// Re-applies the current rules to recent clusters, for when the rules have changed.
    public func reclassify(since date: Date) async throws {
        let recent = try await clusters.clusteredArticles(since: date)
        try await rederive(Set(recent.compactMap(\.clusterID)))
    }

    private func rederive(_ clusterIDs: Set<Int64>) async throws {
        let members = try await clusters.members(of: clusterIDs)
        let updates = members.compactMap { id, articles in
            ClusterDeriver.derive(id: id, members: articles, rules: rules)
        }
        try await clusters.save(updates)
    }

    /// Stories from the given period, most important first, with the reasons for their position.
    public func rankedStories(since date: Date, matching query: String? = nil, limit: Int) async throws -> [RankedStory] {
        let summaries = try await clusters.summaries(since: date, matching: query)
        let ranked = ranker.rank(summaries, interests: try await interests.allInterests(), now: now())
        return Array(ranked.prefix(limit))
    }

    /// Stories from the given period, newest first. Muted stories are still left out.
    public func latestStories(since date: Date, matching query: String? = nil, limit: Int) async throws -> [RankedStory] {
        let summaries = try await clusters.summaries(since: date, matching: query)
        let userInterests = try await interests.allInterests()
        let current = now()
        return Array(summaries.lazy.compactMap { ranker.rank($0, interests: userInterests, now: current) }.prefix(limit))
    }
}
