import Domain
import Foundation

/// Groups articles that report the same underlying story.
///
/// Tier 1: the same canonical URL (typically a Hacker News item pointing at a publisher's article).
/// Tier 2: similar headlines from different sources within a time window.
///
/// Tuned to under-merge. A missed merge shows two rows; a wrong merge hides a story.
public struct Clusterer: Sendable {
    public var window: TimeInterval = 72 * 3600
    /// Minimum weighted Jaccard similarity between two headlines.
    public var threshold = 0.5
    /// Alternative test for a short headline largely contained in a longer one about the same thing:
    /// minimum share of the shorter headline's weight that the two have in common.
    public var containmentThreshold = 0.7
    /// Minimum number of distinctive tokens two headlines must share.
    public var minimumShared = 3
    /// Two items from the same community source join only when their headlines are nearly identical.
    public var sameSourceThreshold = 0.8

    public init() {}

    private enum Group: Hashable {
        case existing(Int64)
        case new(Int)

        var target: ClusterAssignment.Target {
            switch self {
            case .existing(let id): .existing(id)
            case .new(let key): .new(key)
            }
        }
    }

    private struct Placed {
        let sourceID: Int64
        let date: Date
        let tokens: Set<String>
        let group: Group
    }

    /// `existing` must all have a cluster. Returns one assignment per article in `new`.
    public func assign(new: [ArticleDigest], existing: [ArticleDigest]) -> [ClusterAssignment] {
        let newTokens = new.map { TitleTokeniser.tokens($0.title) }
        let existingTokens = existing.map { TitleTokeniser.tokens($0.title) }

        // How many headlines each token appears in, to tell distinctive words from common ones.
        var frequency: [String: Int] = [:]
        for tokens in newTokens + existingTokens {
            for token in tokens { frequency[token, default: 0] += 1 }
        }
        let corpusSize = new.count + existing.count
        let commonCutoff = max(5, corpusSize / 50)
        func weight(_ token: String) -> Double {
            corpusSize >= 100 && frequency[token, default: 0] > commonCutoff ? 0.25 : 1
        }

        var placed: [Placed] = []
        var byURL: [String: Group] = [:]
        var byToken: [String: [Int]] = [:]

        func place(_ article: ArticleDigest, tokens: Set<String>, group: Group) {
            let index = placed.count
            placed.append(Placed(sourceID: article.sourceID, date: article.date, tokens: tokens, group: group))
            if byURL[article.canonicalURL] == nil { byURL[article.canonicalURL] = group }
            guard Self.isMatchableByTitle(article.title) else { return }
            for token in tokens where weight(token) == 1 {
                byToken[token, default: []].append(index)
            }
        }

        for (article, tokens) in zip(existing, existingTokens) {
            guard let id = article.clusterID else { continue }
            place(article, tokens: tokens, group: .existing(id))
        }

        var assignments: [ClusterAssignment] = []
        var nextKey = 0
        let order = new.indices.sorted { (new[$0].date, new[$0].id) < (new[$1].date, new[$1].id) }

        for index in order {
            let article = new[index]
            let tokens = newTokens[index]
            let group: Group

            if let sameURL = byURL[article.canonicalURL] {
                group = sameURL
            } else if Self.isMatchableByTitle(article.title),
                      let similar = bestMatch(for: article, tokens: tokens, placed: placed, byToken: byToken, weight: weight) {
                group = similar
            } else {
                group = .new(nextKey)
                nextKey += 1
            }

            place(article, tokens: tokens, group: group)
            assignments.append(ClusterAssignment(articleID: article.id, target: group.target))
        }
        return assignments
    }

    private func bestMatch(
        for article: ArticleDigest,
        tokens: Set<String>,
        placed: [Placed],
        byToken: [String: [Int]],
        weight: (String) -> Double
    ) -> Group? {
        var shared: [Int: Int] = [:]
        for token in tokens {
            for candidate in byToken[token] ?? [] { shared[candidate, default: 0] += 1 }
        }

        var best: (similarity: Double, group: Group)?
        for (candidate, count) in shared where count >= minimumShared {
            let other = placed[candidate]
            guard abs(other.date.timeIntervalSince(article.date)) <= window else { continue }

            let similarity = Self.similarity(tokens, other.tokens, weight: weight)
            let strength: Double
            if other.sourceID == article.sourceID {
                // A publisher's own posts with similar titles are usually a series, so they stay apart.
                // A community source is different: several people submit the same news, so nearly
                // identical titles there are one story. Containment is not enough on its own here:
                // "X issues ground stop" and "X lifts ground stop" are follow-ups, not duplicates.
                guard article.sourceTier == .community, similarity >= sameSourceThreshold else { continue }
                strength = similarity
            } else {
                let containment = Self.containment(tokens, other.tokens, weight: weight)
                guard similarity >= threshold || containment >= containmentThreshold else { continue }
                strength = max(similarity, containment)
            }
            if strength > (best?.similarity ?? 0) {
                best = (strength, other.group)
            }
        }
        return best?.group
    }

    /// Show HN, Ask HN, Tell HN and Launch HN posts are each someone's own project or question. Two of them
    /// can share most of their words ("a file manager written in Go", "... in Zig") and still be unrelated,
    /// so they join a story only by sharing its link.
    static func isMatchableByTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return !["show hn", "ask hn", "tell hn", "launch hn"].contains { lowered.hasPrefix($0) }
    }

    static func containment(_ a: Set<String>, _ b: Set<String>, weight: (String) -> Double) -> Double {
        let smaller = min(a.reduce(0.0) { $0 + weight($1) }, b.reduce(0.0) { $0 + weight($1) })
        guard smaller > 0 else { return 0 }
        return a.intersection(b).reduce(0.0) { $0 + weight($1) } / smaller
    }

    static func similarity(_ a: Set<String>, _ b: Set<String>, weight: (String) -> Double) -> Double {
        let union = a.union(b).reduce(0.0) { $0 + weight($1) }
        guard union > 0 else { return 0 }
        let intersection = a.intersection(b).reduce(0.0) { $0 + weight($1) }
        return intersection / union
    }
}
