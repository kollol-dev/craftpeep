import Domain
import Foundation
import Ingestion
import Persistence
import Testing
@testable import Intelligence

/// Fetches the real catalogue and prints what clustering, classification and ranking make of it.
/// For tuning by eye, not for CI:
///   CRAFTPEEP_LIVE=1 swift test --filter LiveEvaluationTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CRAFTPEEP_LIVE"] == "1"))
struct LiveEvaluationTests {
    @Test func evaluateOnLiveCatalogue() async throws {
        let database = try AppDatabase()
        let sources = GRDBSourceRepository(database: database)
        let articles = GRDBArticleRepository(database: database)
        let clusters = GRDBClusterRepository(database: database)
        try await sources.seed(SourceCatalogue.bundled())

        let refresh = try await IngestionService(sources: sources, articles: articles, http: URLSessionHTTPClient()).refreshAll()
        let names = Dictionary(uniqueKeysWithValues: try await sources.allSources().map { ($0.id, $0.name) })
        for outcome in refresh.outcomes where outcome.isFailure {
            print("EVAL FAILED \(names[outcome.sourceID] ?? "?"): \(outcome.status)")
        }

        let service = IntelligenceService(
            clusters: clusters, interests: GRDBInterestRepository(database: database), rules: try RuleSet.bundled()
        )
        let clock = ContinuousClock()
        var report = ProcessReport()
        let duration = try await clock.measure { report = try await service.process() }
        print("EVAL \(refresh.newArticles) articles, \(refresh.failures) failed sources; \(report.clustersCreated) clusters in \(duration)")

        let all = try await clusters.summaries(StoryFilter())
        print("EVAL --- multi-source clusters")
        for cluster in all where cluster.sourceCount > 1 {
            print("EVAL [\(cluster.sourceCount)] \(cluster.headline)")
            for story in try await clusters.stories(inCluster: cluster.id) {
                print("EVAL      \(story.sourceName): \(story.title)")
            }
        }

        var kinds: [String: Int] = [:]
        for cluster in all { kinds[cluster.kind?.rawValue ?? "unclassified", default: 0] += 1 }
        print("EVAL --- kinds: \(kinds.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        for kind in StoryKind.allCases {
            for cluster in all.filter({ $0.kind == kind }).prefix(6) {
                print("EVAL   \(kind.rawValue) (\(cluster.kindBasis ?? "")): \(cluster.headline)")
            }
        }

        print("EVAL --- top 25")
        let since = Date().addingTimeInterval(-3 * 86_400)
        for story in try await service.rankedStories(since: since, limit: 25) {
            let summary = story.summary
            print("EVAL \(String(format: "%.2f", story.score)) \(summary.headline) | \(summary.sourceNames.joined(separator: ", ")) | \(summary.kind?.rawValue ?? "-") | \(summary.verification.rawValue) | \(summary.entities.joined(separator: ",")) | \(story.reasons.joined(separator: "; "))")
        }
        #expect(report.clustersCreated > 0)
    }
}
