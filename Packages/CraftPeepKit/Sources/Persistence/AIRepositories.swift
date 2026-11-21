import Domain
import Foundation
import GRDB

public struct GRDBSummaryRepository: SummaryRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func summary(forCluster id: Int64) async throws -> StorySummary? {
        try await database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM summary WHERE cluster_id = ?", arguments: [id]) else { return nil }
            let created: Int64 = row["created_at"]
            return StorySummary(
                clusterID: row["cluster_id"], text: row["text"], whyItMatters: row["why_it_matters"],
                provider: row["provider"], model: row["model"],
                createdAt: Date(unixSeconds: created), inputHash: row["input_hash"]
            )
        }
    }

    public func save(_ summary: StorySummary) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO summary (cluster_id, input_hash, text, why_it_matters, provider, model, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    summary.clusterID, summary.inputHash, summary.text, summary.whyItMatters,
                    summary.provider, summary.model, summary.createdAt.unixSeconds
                ]
            )
        }
    }
}

public struct GRDBBriefingRepository: BriefingRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func briefing(forDate date: String) async throws -> Briefing? {
        try await database.writer.read { db in
            guard let body = try String.fetchOne(db, sql: "SELECT body FROM briefing WHERE for_date = ?", arguments: [date]) else { return nil }
            // A body written by a newer version that this one cannot read is treated as absent.
            return try? Self.decoder.decode(Briefing.self, from: Data(body.utf8))
        }
    }

    public func save(_ briefing: Briefing) async throws {
        let body = String(decoding: try Self.encoder.encode(briefing), as: UTF8.self)
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO briefing (for_date, body, created_at) VALUES (?, ?, ?)",
                arguments: [briefing.forDate, body, briefing.createdAt.unixSeconds]
            )
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

public struct GRDBAIUsageRepository: AIUsageRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func record(_ usage: AIUsageRecord) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO ai_usage (at, feature, provider, model, input_tokens, output_tokens, est_cost_micros, outcome)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    usage.at.unixSeconds, usage.feature, usage.provider, usage.model,
                    usage.inputTokens, usage.outputTokens, usage.estimatedCostMicros, usage.outcome.rawValue
                ]
            )
        }
    }

    public func totals(since date: Date) async throws -> AIUsageTotals {
        try await database.writer.read { db in
            var totals = AIUsageTotals()
            // Blocked calls never reached a provider, so they are not usage.
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) AS requests,
                           COALESCE(SUM(COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)), 0) AS tokens,
                           COALESCE(SUM(est_cost_micros), 0) AS cost,
                           COALESCE(SUM(est_cost_micros IS NULL), 0) AS unpriced
                    FROM ai_usage WHERE at >= ? AND outcome <> 'budget_blocked'
                    """,
                arguments: [date.unixSeconds]
            ) else { return totals }
            totals.requests = row["requests"]
            totals.tokens = row["tokens"]
            totals.estimatedCostMicros = row["cost"]
            totals.unpricedRequests = row["unpriced"]
            return totals
        }
    }
}
