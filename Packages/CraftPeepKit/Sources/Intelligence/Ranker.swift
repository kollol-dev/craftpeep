import Domain
import Foundation

public struct RankedStory: Sendable, Equatable, Identifiable {
    public var summary: ClusterSummary
    /// For ordering only. Never shown: it is a weighted sum of heuristics, not a measurement.
    public var score: Double
    /// Why this story ranks where it does, strongest first, in words a reader can check.
    public var reasons: [String]

    public var id: Int64 { summary.id }
}

/// Orders stories by a sum of small, named factors. Every factor that contributes can explain itself.
public struct Ranker: Sendable {
    public struct Weights: Sendable {
        public var tier: [SourceTier: Double] = [
            .official: 3, .documentation: 2.5, .reporting: 2, .analysis: 1.5, .community: 1, .unverified: 0.5
        ]
        /// Multiplies log2(1 + number of sources).
        public var coverage = 1.5
        /// Multiplies log10(1 + community points).
        public var community = 1.0
        public var followed = 3.0
        public var priority = 5.0
        public var kind: [StoryKind: Double] = [.shipping: 1, .research: 0.5, .benchmark: 0.5, .speculation: -0.5, .unverifiedClaim: -1]
        /// Hours for a story's score to halve.
        public var halfLifeHours = 18.0

        public init() {}
    }

    public var weights = Weights()

    public init() {}

    public func rank(_ stories: [ClusterSummary], interests: [Interest], now: Date) -> [RankedStory] {
        stories.compactMap { rank($0, interests: interests, now: now) }
            .sorted { ($0.score, $0.summary.lastSeenAt, $0.id) > ($1.score, $1.summary.lastSeenAt, $1.id) }
    }

    /// Returns nil for a story the user has muted.
    public func rank(_ story: ClusterSummary, interests: [Interest], now: Date) -> RankedStory? {
        var factors: [(value: Double, reason: String?)] = []

        let headline = PhraseText(story.headline)
        let entityNames = Set(story.entities.map { $0.lowercased() })
        func matches(_ interest: Interest) -> Bool {
            entityNames.contains(interest.keyword.lowercased()) || headline.contains(interest.keyword)
        }

        for interest in interests where matches(interest) {
            switch interest.level {
            case .muted: return nil
            case .followed: factors.append((weights.followed, "Matches your interest: \(interest.keyword)"))
            case .priority: factors.append((weights.priority, "Matches your priority interest: \(interest.keyword)"))
            }
        }

        let tierReason: String? = switch story.bestTier {
        case .official: "Official source"
        case .documentation: "Official documentation"
        default: nil
        }
        factors.append((weights.tier[story.bestTier] ?? 0, tierReason))

        // An aggregator linking to an article is discussion, not a second report of it.
        if story.independentSourceCount > 1 {
            factors.append((
                weights.coverage * log2(1 + Double(story.independentSourceCount)),
                "Covered by \(story.independentSourceCount) sources"
            ))
        }

        if let points = story.score, points > 0 {
            let value = weights.community * log10(1 + Double(points))
            factors.append((value, points >= 100 ? "\(points) points on Hacker News" : nil))
        }

        if let kind = story.kind, let value = weights.kind[kind] {
            let reason: String? = switch kind {
            case .shipping: "Available now"
            case .research: "Research"
            case .benchmark: "Benchmark results"
            default: nil
            }
            factors.append((value, value > 0 ? reason : nil))
        }

        // Age runs from when the story broke, but later coverage can keep it fresh for up to a day.
        let reference = min(story.lastSeenAt, story.firstSeenAt.addingTimeInterval(24 * 3600))
        let ageHours = max(0, now.timeIntervalSince(reference) / 3600)
        let decay = pow(0.5, ageHours / weights.halfLifeHours)

        let total = max(0, factors.reduce(0) { $0 + $1.value }) * decay
        let reasons = factors
            .filter { $0.reason != nil && $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .compactMap(\.reason)

        return RankedStory(summary: story, score: total, reasons: Array(reasons))
    }
}
