import Foundation

/// What kind of thing a story is: the Hype Filter. Nil (unclassified) is a valid answer.
public enum StoryKind: String, Sendable, Codable, CaseIterable {
    /// Code, weights or a product people can use now.
    case shipping
    /// A product or feature announced, not necessarily available.
    case announcement
    case research
    case benchmark
    /// Funding, acquisitions, mergers.
    case funding
    case partnership
    /// Reports, rumours and predictions about things not confirmed.
    case speculation
    /// A claim nobody has been able to check.
    case unverifiedClaim = "unverified_claim"
}

public enum Confidence: String, Sendable, Codable {
    case high, medium, low
}

/// How well supported a story is, from the tiers of the sources reporting it.
public enum Verification: String, Sendable, Codable {
    /// At least one source is the organisation itself or its documentation.
    case official
    /// Two or more independent reporting sources.
    case corroborated
    /// One reporting or analysis source.
    case singleSource = "single_source"
    /// Community discussion or unassessed sources only.
    case unverified
}

extension SourceTier {
    /// Higher is more authoritative. Used to pick a cluster's headline and best tier.
    public var authority: Int {
        switch self {
        case .official: 5
        case .documentation: 4
        case .reporting: 3
        case .analysis: 2
        case .community: 1
        case .unverified: 0
        }
    }
}

/// The parts of a stored article that clustering and classification need.
public struct ArticleDigest: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var sourceID: Int64
    public var sourceTier: SourceTier
    public var clusterID: Int64?
    public var url: String
    public var canonicalURL: String
    public var title: String
    public var excerpt: String?
    /// Publication time, or retrieval time when the source gave none.
    public var date: Date
    public var score: Int?
    public var commentCount: Int?

    public init(
        id: Int64,
        sourceID: Int64,
        sourceTier: SourceTier,
        clusterID: Int64? = nil,
        url: String,
        canonicalURL: String,
        title: String,
        excerpt: String? = nil,
        date: Date,
        score: Int? = nil,
        commentCount: Int? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceTier = sourceTier
        self.clusterID = clusterID
        self.url = url
        self.canonicalURL = canonicalURL
        self.title = title
        self.excerpt = excerpt
        self.date = date
        self.score = score
        self.commentCount = commentCount
    }
}

/// Where the clusterer decided an article belongs.
public struct ClusterAssignment: Sendable, Equatable {
    public enum Target: Sendable, Hashable {
        case existing(Int64)
        /// A cluster to be created. Articles sharing a key join the same new cluster.
        case new(Int)
    }

    public var articleID: Int64
    public var target: Target

    public init(articleID: Int64, target: Target) {
        self.articleID = articleID
        self.target = target
    }
}

public struct TaggedEntity: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable {
        case company, technology, topic
    }

    public var name: String
    public var kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }
}

/// Everything about a cluster that is derived from its members. Recomputed when membership changes.
public struct ClusterUpdate: Sendable, Equatable {
    public var id: Int64
    public var headline: String
    public var leadArticleID: Int64
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var memberCount: Int
    public var sourceCount: Int
    /// Sources doing their own reporting or announcing. Community aggregators linking to someone
    /// else's article are not independent coverage.
    public var independentSourceCount: Int
    public var bestTier: SourceTier
    public var kind: StoryKind?
    /// `rule:<id>` today; `model:<name>` if a model ever classifies. Nil when unclassified.
    public var kindBasis: String?
    public var kindConfidence: Confidence?
    public var verification: Verification
    public var score: Int?
    public var commentCount: Int?
    public var entities: [TaggedEntity]

    public init(
        id: Int64,
        headline: String,
        leadArticleID: Int64,
        firstSeenAt: Date,
        lastSeenAt: Date,
        memberCount: Int,
        sourceCount: Int,
        independentSourceCount: Int,
        bestTier: SourceTier,
        kind: StoryKind?,
        kindBasis: String?,
        kindConfidence: Confidence?,
        verification: Verification,
        score: Int?,
        commentCount: Int?,
        entities: [TaggedEntity]
    ) {
        self.independentSourceCount = independentSourceCount
        self.id = id
        self.headline = headline
        self.leadArticleID = leadArticleID
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.memberCount = memberCount
        self.sourceCount = sourceCount
        self.bestTier = bestTier
        self.kind = kind
        self.kindBasis = kindBasis
        self.kindConfidence = kindConfidence
        self.verification = verification
        self.score = score
        self.commentCount = commentCount
        self.entities = entities
    }
}

/// A story as shown in a list: one row per underlying event, however many sources reported it.
public struct ClusterSummary: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var headline: String
    public var excerpt: String?
    public var url: String
    public var discussionURL: String?
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var memberCount: Int
    public var sourceCount: Int
    public var independentSourceCount: Int
    public var sourceNames: [String]
    public var bestTier: SourceTier
    public var kind: StoryKind?
    public var kindBasis: String?
    public var kindConfidence: Confidence?
    public var verification: Verification
    public var score: Int?
    public var commentCount: Int?
    public var entities: [String]
    public var readAt: Date?
    /// Set when the user saves the story to read later.
    public var savedAt: Date?
    public var isFavourite: Bool

    public var isRead: Bool { readAt != nil }
    public var isSaved: Bool { savedAt != nil }

    public init(
        id: Int64,
        headline: String,
        excerpt: String? = nil,
        url: String,
        discussionURL: String? = nil,
        firstSeenAt: Date,
        lastSeenAt: Date,
        memberCount: Int = 1,
        sourceCount: Int = 1,
        independentSourceCount: Int = 1,
        sourceNames: [String] = [],
        bestTier: SourceTier,
        kind: StoryKind? = nil,
        kindBasis: String? = nil,
        kindConfidence: Confidence? = nil,
        verification: Verification = .unverified,
        score: Int? = nil,
        commentCount: Int? = nil,
        entities: [String] = [],
        readAt: Date? = nil,
        savedAt: Date? = nil,
        isFavourite: Bool = false
    ) {
        self.readAt = readAt
        self.savedAt = savedAt
        self.isFavourite = isFavourite
        self.id = id
        self.headline = headline
        self.excerpt = excerpt
        self.url = url
        self.discussionURL = discussionURL
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.memberCount = memberCount
        self.sourceCount = sourceCount
        self.independentSourceCount = independentSourceCount
        self.sourceNames = sourceNames
        self.bestTier = bestTier
        self.kind = kind
        self.kindBasis = kindBasis
        self.kindConfidence = kindConfidence
        self.verification = verification
        self.score = score
        self.commentCount = commentCount
        self.entities = entities
    }
}

/// Something the user wants more of, or none of. Matched against a story's entities and headline.
public struct Interest: Sendable, Equatable, Identifiable {
    public enum Level: Int, Sendable, Codable {
        case muted = -1
        case followed = 1
        case priority = 2
    }

    public var keyword: String
    public var level: Level

    public var id: String { keyword.lowercased() }

    public init(keyword: String, level: Level) {
        self.keyword = keyword
        self.level = level
    }
}

/// Which stories a list wants. Every condition that is set must hold.
public struct StoryFilter: Sendable, Equatable {
    /// Only stories active on or after this time.
    public var since: Date = .distantPast
    /// Full-text query over the titles and excerpts of member articles.
    public var query: String?
    /// A subject area: the story is tagged with one of `entityNames`, or comes from a source whose
    /// first topic is `sourceTopic`. Nil means every subject.
    public var subject: Subject?
    /// Only these kinds. Unclassified stories are excluded when this is set.
    public var kinds: Set<StoryKind>?
    /// Only stories the user saved for later or marked as a favourite.
    public var keptOnly = false
    /// Only stories this source reported (alongside any other sources).
    public var sourceID: Int64?

    public struct Subject: Sendable, Equatable {
        public var entityNames: [String]
        public var sourceTopic: String?

        public init(entityNames: [String], sourceTopic: String? = nil) {
            self.entityNames = entityNames
            self.sourceTopic = sourceTopic
        }
    }

    public init(
        since: Date = .distantPast,
        query: String? = nil,
        subject: Subject? = nil,
        kinds: Set<StoryKind>? = nil,
        keptOnly: Bool = false,
        sourceID: Int64? = nil
    ) {
        self.sourceID = sourceID
        self.since = since
        self.query = query
        self.subject = subject
        self.kinds = kinds
        self.keptOnly = keptOnly
    }
}

public protocol ClusterRepository: Sendable {
    /// Articles not yet in a cluster, oldest first.
    func unclusteredArticles() async throws -> [ArticleDigest]
    /// Articles already in a cluster and dated on or after `date`.
    func clusteredArticles(since date: Date) async throws -> [ArticleDigest]
    /// Creates new clusters as needed and records membership. Returns every cluster touched.
    func apply(_ assignments: [ClusterAssignment], at now: Date) async throws -> Set<Int64>
    func members(of clusterIDs: Set<Int64>) async throws -> [Int64: [ArticleDigest]]
    func save(_ updates: [ClusterUpdate]) async throws
    /// Clusters matching the filter, newest first, unranked.
    func summaries(_ filter: StoryFilter) async throws -> [ClusterSummary]
    func setRead(_ read: Bool, clusterID: Int64, at now: Date) async throws
    /// Marks many stories read at once, in one transaction.
    func markRead(clusterIDs: [Int64], at now: Date) async throws
    func setSaved(_ saved: Bool, clusterID: Int64, at now: Date) async throws
    func setFavourite(_ favourite: Bool, clusterID: Int64) async throws
    /// Clusters whose stored facts no longer match their members (for example after a source was removed).
    /// Clusters left with no members are deleted here.
    func clustersNeedingRepair() async throws -> Set<Int64>
    /// Every article in a cluster, most authoritative first.
    func stories(inCluster id: Int64) async throws -> [Story]
    /// Deletes articles dated before `articlesBefore`, clusters left empty, and fetch log rows before
    /// `logsBefore`. Stories the user saved or marked as favourite are kept. Returns the number of articles removed.
    @discardableResult
    func purge(articlesBefore: Date, logsBefore: Date) async throws -> Int
}

public protocol InterestRepository: Sendable {
    func allInterests() async throws -> [Interest]
    func set(_ interest: Interest) async throws
    func remove(keyword: String) async throws
}
