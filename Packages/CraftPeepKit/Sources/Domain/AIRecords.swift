import Foundation

/// An AI-written summary of one story. Always shown labelled, with its model and time.
public struct StorySummary: Sendable, Equatable {
    public var clusterID: Int64
    public var text: String
    public var whyItMatters: String
    public var provider: String
    public var model: String
    public var createdAt: Date
    /// Hash of the prompt version and the member articles' content. A summary is reused while this matches.
    public var inputHash: String

    public init(clusterID: Int64, text: String, whyItMatters: String, provider: String, model: String, createdAt: Date, inputHash: String) {
        self.clusterID = clusterID
        self.text = text
        self.whyItMatters = whyItMatters
        self.provider = provider
        self.model = model
        self.createdAt = createdAt
        self.inputHash = inputHash
    }
}

public struct BriefingItem: Sendable, Equatable, Codable {
    /// The stored stories this item is about. Every item has at least one; that is what makes it checkable.
    public var clusterIDs: [Int64]
    public var title: String
    public var whatHappened: String
    public var whyItMatters: String
    public var whoIsAffected: String
    public var technicalImplications: String?
    public var businessImplications: String?
    public var whatToWatch: String?

    public init(
        clusterIDs: [Int64], title: String, whatHappened: String, whyItMatters: String, whoIsAffected: String,
        technicalImplications: String? = nil, businessImplications: String? = nil, whatToWatch: String? = nil
    ) {
        self.clusterIDs = clusterIDs
        self.title = title
        self.whatHappened = whatHappened
        self.whyItMatters = whyItMatters
        self.whoIsAffected = whoIsAffected
        self.technicalImplications = technicalImplications
        self.businessImplications = businessImplications
        self.whatToWatch = whatToWatch
    }
}

public struct Briefing: Sendable, Equatable, Codable {
    /// Local calendar date the briefing is for, as yyyy-MM-dd.
    public var forDate: String
    public var headline: String
    public var items: [BriefingItem]
    public var exploreNext: [String]
    public var provider: String
    public var model: String
    public var createdAt: Date

    public init(forDate: String, headline: String, items: [BriefingItem], exploreNext: [String], provider: String, model: String, createdAt: Date) {
        self.forDate = forDate
        self.headline = headline
        self.items = items
        self.exploreNext = exploreNext
        self.provider = provider
        self.model = model
        self.createdAt = createdAt
    }
}

/// One AI call, for the usage ledger. Holds counts only, never prompt or response text.
public struct AIUsageRecord: Sendable, Equatable {
    public enum Outcome: String, Sendable {
        case ok, error
        case budgetBlocked = "budget_blocked"
    }

    public var at: Date
    public var feature: String
    public var provider: String
    public var model: String
    public var inputTokens: Int?
    public var outputTokens: Int?
    /// Millionths of a US dollar. Nil when the price of the model is not known; never a guess.
    public var estimatedCostMicros: Int?
    public var outcome: Outcome

    public init(at: Date, feature: String, provider: String, model: String, inputTokens: Int?, outputTokens: Int?, estimatedCostMicros: Int?, outcome: Outcome) {
        self.at = at
        self.feature = feature
        self.provider = provider
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.estimatedCostMicros = estimatedCostMicros
        self.outcome = outcome
    }
}

public struct AIUsageTotals: Sendable, Equatable {
    public var requests = 0
    public var tokens = 0
    /// Sum over calls whose price was known.
    public var estimatedCostMicros = 0
    /// Calls whose price was not known, so the cost above may be an undercount.
    public var unpricedRequests = 0

    public init() {}
}

public protocol SummaryRepository: Sendable {
    func summary(forCluster id: Int64) async throws -> StorySummary?
    func save(_ summary: StorySummary) async throws
}

public protocol BriefingRepository: Sendable {
    func briefing(forDate date: String) async throws -> Briefing?
    func save(_ briefing: Briefing) async throws
}

public protocol AIUsageRepository: Sendable {
    func record(_ usage: AIUsageRecord) async throws
    func totals(since date: Date) async throws -> AIUsageTotals
}
