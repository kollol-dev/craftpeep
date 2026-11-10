import Domain
import Foundation
import GRDB

public struct GRDBClusterRepository: ClusterRepository {
    private let database: AppDatabase
    /// Separates values inside group_concat results. Cannot appear in cleaned text.
    private static let separator = "\u{1F}"

    public init(database: AppDatabase) {
        self.database = database
    }

    private static let digestSelect = """
        SELECT a.id, a.source_id, a.cluster_id, a.url, a.canonical_url, a.title, a.excerpt,
               COALESCE(a.published_at, a.retrieved_at) AS date, a.score, a.comment_count, s.tier
        FROM article a JOIN source s ON s.id = a.source_id
        """

    public func unclusteredArticles() async throws -> [ArticleDigest] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: Self.digestSelect + " WHERE a.cluster_id IS NULL ORDER BY date, a.id")
                .map(Self.digest)
        }
    }

    public func clusteredArticles(since date: Date) async throws -> [ArticleDigest] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: Self.digestSelect
                    + " WHERE a.cluster_id IS NOT NULL AND COALESCE(a.published_at, a.retrieved_at) >= ? ORDER BY date, a.id",
                arguments: [date.unixSeconds]
            ).map(Self.digest)
        }
    }

    public func apply(_ assignments: [ClusterAssignment], at now: Date) async throws -> Set<Int64> {
        guard !assignments.isEmpty else { return [] }
        return try await database.writer.write { db in
            var created: [Int: Int64] = [:]
            var touched = Set<Int64>()
            for assignment in assignments {
                let clusterID: Int64
                switch assignment.target {
                case .existing(let id):
                    clusterID = id
                case .new(let key):
                    if let id = created[key] {
                        clusterID = id
                    } else {
                        try db.execute(
                            sql: "INSERT INTO cluster (first_seen_at, last_seen_at) VALUES (?, ?)",
                            arguments: [now.unixSeconds, now.unixSeconds]
                        )
                        clusterID = db.lastInsertedRowID
                        created[key] = clusterID
                    }
                }
                try db.execute(
                    sql: "UPDATE article SET cluster_id = ? WHERE id = ?",
                    arguments: [clusterID, assignment.articleID]
                )
                touched.insert(clusterID)
            }
            return touched
        }
    }

    public func members(of clusterIDs: Set<Int64>) async throws -> [Int64: [ArticleDigest]] {
        guard !clusterIDs.isEmpty else { return [:] }
        return try await database.writer.read { db in
            var result: [Int64: [ArticleDigest]] = [:]
            // Chunked to stay well inside SQLite's bound-parameter limit.
            for chunk in Array(clusterIDs).chunked(into: 500) {
                let marks = databaseQuestionMarks(count: chunk.count)
                let rows = try Row.fetchAll(
                    db,
                    sql: Self.digestSelect + " WHERE a.cluster_id IN (\(marks)) ORDER BY date, a.id",
                    arguments: StatementArguments(chunk)
                )
                for digest in rows.map(Self.digest) {
                    if let id = digest.clusterID { result[id, default: []].append(digest) }
                }
            }
            return result
        }
    }

    public func save(_ updates: [ClusterUpdate]) async throws {
        guard !updates.isEmpty else { return }
        try await database.writer.write { db in
            for update in updates {
                try db.execute(
                    sql: """
                        UPDATE cluster SET
                          headline = ?, lead_article_id = ?, first_seen_at = ?, last_seen_at = ?,
                          member_count = ?, source_count = ?, independent_count = ?, best_tier = ?,
                          kind = ?, kind_basis = ?, kind_confidence = ?, verification = ?,
                          score = ?, comment_count = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        update.headline, update.leadArticleID,
                        update.firstSeenAt.unixSeconds, update.lastSeenAt.unixSeconds,
                        update.memberCount, update.sourceCount, update.independentSourceCount, update.bestTier.rawValue,
                        update.kind?.rawValue, update.kindBasis, update.kindConfidence?.rawValue,
                        update.verification.rawValue, update.score, update.commentCount, update.id
                    ]
                )
                try db.execute(sql: "DELETE FROM cluster_entity WHERE cluster_id = ?", arguments: [update.id])
                for entity in update.entities {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO cluster_entity (cluster_id, name, kind) VALUES (?, ?, ?)",
                        arguments: [update.id, entity.name, entity.kind.rawValue]
                    )
                }
            }
        }
    }

    public func summaries(since date: Date, matching query: String?) async throws -> [ClusterSummary] {
        let pattern = query.flatMap(FTS5Pattern.init(matchingAllPrefixesIn:))
        let wantsSearch = !(query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if wantsSearch && pattern == nil { return [] }

        return try await database.writer.read { db in
            var sql = """
                SELECT c.*, la.url AS lead_url, la.excerpt AS lead_excerpt,
                  (SELECT group_concat(name, char(31)) FROM
                     (SELECT DISTINCT s.name AS name FROM article a JOIN source s ON s.id = a.source_id
                      WHERE a.cluster_id = c.id ORDER BY s.name)) AS source_names,
                  (SELECT group_concat(name, char(31)) FROM
                     (SELECT name FROM cluster_entity WHERE cluster_id = c.id ORDER BY name)) AS entity_names,
                  (SELECT a.discussion_url FROM article a
                   WHERE a.cluster_id = c.id AND a.discussion_url IS NOT NULL
                   ORDER BY a.score DESC LIMIT 1) AS discussion_url
                FROM cluster c JOIN article la ON la.id = c.lead_article_id
                WHERE c.last_seen_at >= ?
                """
            var arguments: StatementArguments = [date.unixSeconds]
            if let pattern {
                sql += """
                     AND c.id IN (SELECT a.cluster_id FROM article a
                                  JOIN article_fts f ON f.rowid = a.id WHERE article_fts MATCH ?)
                    """
                arguments += [pattern]
            }
            sql += " ORDER BY c.last_seen_at DESC, c.id DESC"
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map(Self.summary)
        }
    }

    public func stories(inCluster id: Int64) async throws -> [Story] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT a.*, s.name AS source_name, s.tier AS source_tier
                    FROM article a JOIN source s ON s.id = a.source_id
                    WHERE a.cluster_id = ?
                    ORDER BY COALESCE(a.published_at, a.retrieved_at), a.id
                    """,
                arguments: [id]
            )
            return rows.map(GRDBArticleRepository.story)
                .sorted { ($0.sourceTier.authority, $1.effectiveDate) > ($1.sourceTier.authority, $0.effectiveDate) }
        }
    }

    @discardableResult
    public func purge(articlesBefore: Date, logsBefore: Date) async throws -> Int {
        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM article WHERE COALESCE(published_at, retrieved_at) < ?",
                arguments: [articlesBefore.unixSeconds]
            )
            let removed = db.changesCount
            try db.execute(sql: "DELETE FROM cluster WHERE id NOT IN (SELECT DISTINCT cluster_id FROM article WHERE cluster_id IS NOT NULL)")
            try db.execute(sql: "DELETE FROM fetch_log WHERE at < ?", arguments: [logsBefore.unixSeconds])
            return removed
        }
    }

    private static func digest(_ row: Row) -> ArticleDigest {
        let date: Int64 = row["date"]
        return ArticleDigest(
            id: row["id"],
            sourceID: row["source_id"],
            sourceTier: SourceTier(rawValue: row["tier"]) ?? .unverified,
            clusterID: row["cluster_id"],
            url: row["url"],
            canonicalURL: row["canonical_url"],
            title: row["title"],
            excerpt: row["excerpt"],
            date: Date(unixSeconds: date),
            score: row["score"],
            commentCount: row["comment_count"]
        )
    }

    private static func summary(_ row: Row) -> ClusterSummary {
        func list(_ column: String) -> [String] {
            let joined: String? = row[column]
            return joined?.components(separatedBy: separator).filter { !$0.isEmpty } ?? []
        }
        let first: Int64 = row["first_seen_at"]
        let last: Int64 = row["last_seen_at"]
        let kind: String? = row["kind"]
        let confidence: String? = row["kind_confidence"]
        return ClusterSummary(
            id: row["id"],
            headline: row["headline"],
            excerpt: row["lead_excerpt"],
            url: row["lead_url"],
            discussionURL: row["discussion_url"],
            firstSeenAt: Date(unixSeconds: first),
            lastSeenAt: Date(unixSeconds: last),
            memberCount: row["member_count"],
            sourceCount: row["source_count"],
            independentSourceCount: row["independent_count"],
            sourceNames: list("source_names"),
            bestTier: SourceTier(rawValue: row["best_tier"]) ?? .unverified,
            kind: kind.flatMap(StoryKind.init(rawValue:)),
            kindBasis: row["kind_basis"],
            kindConfidence: confidence.flatMap(Confidence.init(rawValue:)),
            verification: Verification(rawValue: row["verification"]) ?? .unverified,
            score: row["score"],
            commentCount: row["comment_count"],
            entities: list("entity_names")
        )
    }
}

public struct GRDBInterestRepository: InterestRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func allInterests() async throws -> [Interest] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT keyword, level FROM interest ORDER BY keyword COLLATE NOCASE").compactMap { row in
                guard let level = Interest.Level(rawValue: row["level"]) else { return nil }
                return Interest(keyword: row["keyword"], level: level)
            }
        }
    }

    public func set(_ interest: Interest) async throws {
        let keyword = interest.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO interest (keyword, level) VALUES (?, ?) ON CONFLICT(keyword) DO UPDATE SET level = excluded.level",
                arguments: [keyword, interest.level.rawValue]
            )
        }
    }

    public func remove(keyword: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM interest WHERE keyword = ?", arguments: [keyword])
        }
    }
}

private func databaseQuestionMarks(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ",")
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
