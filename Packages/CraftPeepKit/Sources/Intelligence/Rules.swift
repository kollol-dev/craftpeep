import Domain
import Foundation

/// The classification rules shipped with the app. Deterministic and readable, so every label
/// can be traced to the rule that produced it. No model is involved.
public struct RuleSet: Sendable, Codable, Equatable {
    public struct EntityRule: Sendable, Codable, Equatable {
        public var name: String
        public var kind: TaggedEntity.Kind
        /// Matched as whole words, ignoring case.
        public var aliases: [String]?
        /// Matched as whole words with exact capitalisation, for names that are also ordinary words.
        public var exact: [String]?
    }

    public struct KindRule: Sendable, Codable, Equatable {
        public var id: String
        public var kind: StoryKind
        public var confidence: Confidence
        /// Any member article is hosted on one of these domains (or a subdomain).
        public var hosts: [String]?
        /// Any member article's URL contains one of these.
        public var urlContains: [String]?
        /// The cluster's best source tier is one of these.
        public var tiers: [SourceTier]?
        /// The headline contains one of these phrases.
        public var titleAny: [String]?
        /// The headline contains none of these phrases.
        public var titleNone: [String]?
    }

    public var entities: [EntityRule]
    /// Evaluated in order; the first rule whose every condition holds wins.
    public var kindRules: [KindRule]

    public static func bundled() throws -> RuleSet {
        guard let url = Bundle.module.url(forResource: "classification.rules", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: url))
    }
}

public struct KindDecision: Sendable, Equatable {
    public var kind: StoryKind
    public var basis: String
    public var confidence: Confidence
}

public enum Classifier {
    /// Returns nil when no rule applies. Unclassified is an honest answer.
    public static func kind(
        headline: String,
        memberURLs: [String],
        bestTier: SourceTier,
        rules: [RuleSet.KindRule]
    ) -> KindDecision? {
        let title = PhraseText(headline)
        let hosts = memberURLs.compactMap { URL(string: $0)?.host()?.lowercased() }

        for rule in rules {
            // A rule with no conditions would match everything; treat it as a mistake and skip it.
            guard rule.hosts != nil || rule.urlContains != nil || rule.titleAny != nil else { continue }

            if let wanted = rule.hosts {
                guard hosts.contains(where: { host in wanted.contains { host == $0 || host.hasSuffix("." + $0) } }) else { continue }
            }
            if let fragments = rule.urlContains {
                guard memberURLs.contains(where: { url in fragments.contains { url.contains($0) } }) else { continue }
            }
            if let tiers = rule.tiers {
                guard tiers.contains(bestTier) else { continue }
            }
            if let phrases = rule.titleAny {
                guard phrases.contains(where: title.contains) else { continue }
            }
            if let phrases = rule.titleNone {
                guard !phrases.contains(where: title.contains) else { continue }
            }
            return KindDecision(kind: rule.kind, basis: "rule:\(rule.id)", confidence: rule.confidence)
        }
        return nil
    }

    public static func verification(tiersBySource: [Int64: SourceTier]) -> Verification {
        let tiers = Array(tiersBySource.values)
        if tiers.contains(where: { $0 == .official || $0 == .documentation }) { return .official }
        let reporting = tiers.filter { $0 == .reporting }.count
        if reporting >= 2 { return .corroborated }
        if reporting == 1 || tiers.contains(.analysis) { return .singleSource }
        return .unverified
    }
}

public enum Tagger {
    public static func entities(in texts: [String], rules: [RuleSet.EntityRule]) -> [TaggedEntity] {
        let text = PhraseText(texts.joined(separator: " . "))
        return rules.compactMap { rule in
            let matched = (rule.aliases ?? []).contains(where: text.contains)
                || (rule.exact ?? []).contains(where: text.containsExact)
            return matched ? TaggedEntity(name: rule.name, kind: rule.kind) : nil
        }
    }
}

/// Computes everything about a cluster that follows from its members.
public enum ClusterDeriver {
    public static func derive(id: Int64, members: [ArticleDigest], rules: RuleSet) -> ClusterUpdate? {
        // The headline comes from the most authoritative source; ties go to whoever published first.
        guard let lead = members.min(by: {
            ($1.sourceTier.authority, $0.date, $0.id) < ($0.sourceTier.authority, $1.date, $1.id)
        }) else { return nil }

        var tiersBySource: [Int64: SourceTier] = [:]
        for member in members { tiersBySource[member.sourceID] = member.sourceTier }

        let decision = Classifier.kind(
            headline: lead.title,
            memberURLs: members.map(\.url),
            bestTier: lead.sourceTier,
            rules: rules.kindRules
        )
        let dates = members.map(\.date)

        return ClusterUpdate(
            id: id,
            headline: lead.title,
            leadArticleID: lead.id,
            firstSeenAt: dates.min() ?? lead.date,
            lastSeenAt: dates.max() ?? lead.date,
            memberCount: members.count,
            sourceCount: tiersBySource.count,
            independentSourceCount: tiersBySource.values.filter { $0 != .community }.count,
            bestTier: lead.sourceTier,
            kind: decision?.kind,
            kindBasis: decision?.basis,
            kindConfidence: decision?.confidence,
            verification: Classifier.verification(tiersBySource: tiersBySource),
            score: members.compactMap(\.score).max(),
            commentCount: members.compactMap(\.commentCount).max(),
            // Titles only: an excerpt mentions plenty of things the story is not about.
            entities: Tagger.entities(in: members.map(\.title), rules: rules.entities)
        )
    }
}
