import Domain
import Foundation
import GRDB

// MARK: - Sources

public struct GRDBSourceRepository: SourceRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    @discardableResult
    public func seed(_ definitions: [SourceDefinition]) async throws -> Int {
        try await database.writer.write { db in
            var added = 0
            for definition in definitions {
                let topics = String(decoding: try JSONEncoder().encode(definition.topics), as: UTF8.self)
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO source (kind, name, url, site_url, tier, topics, refresh_secs, folder)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        definition.kind.rawValue, definition.name, definition.url, definition.siteURL,
                        definition.tier.rawValue, topics, definition.refreshSeconds, definition.folder
                    ]
                )
                added += db.changesCount
            }

            // Sources stored before folders existed get the catalogue's folder once. After that the user's
            // filing is left alone, even when they take a source out of every folder.
            let marker = "catalogue.folders.v1"
            if try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: [marker]) == nil {
                for definition in definitions where definition.folder != nil {
                    try db.execute(
                        sql: "UPDATE source SET folder = ? WHERE url = ? AND folder IS NULL AND tier_origin = 'catalog'",
                        arguments: [definition.folder, definition.url]
                    )
                }
                try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, '1')", arguments: [marker])
            }
            return added
        }
    }

    public func allSources() async throws -> [Source] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM source ORDER BY name COLLATE NOCASE").map(Self.source)
        }
    }

    public func enabledSources() async throws -> [Source] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM source WHERE enabled = 1 ORDER BY id").map(Self.source)
        }
    }

    public func newestStoryDates() async throws -> [Int64: Date] {
        try await database.writer.read { db in
            var dates: [Int64: Date] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT source_id, MAX(COALESCE(published_at, retrieved_at)) AS newest FROM article GROUP BY source_id") {
                let newest: Int64 = row["newest"]
                dates[row["source_id"]] = Date(unixSeconds: newest)
            }
            return dates
        }
    }

    public func setFolder(_ folder: String?, sourceID: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE source SET folder = ? WHERE id = ?", arguments: [Self.folderName(folder), sourceID])
        }
    }

    public func renameFolder(_ name: String, to newName: String) async throws {
        guard let cleaned = Self.folderName(newName) else { return }
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE source SET folder = ? WHERE folder = ?", arguments: [cleaned, name])
        }
    }

    public func removeFolder(_ name: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE source SET folder = NULL WHERE folder = ?", arguments: [name])
        }
    }

    public func setAlertsEnabled(_ enabled: Bool, sourceID: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE source SET alert = ? WHERE id = ?", arguments: [enabled, sourceID])
        }
    }

    public func setAlertsEnabled(_ enabled: Bool, folder: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE source SET alert = ? WHERE folder = ?", arguments: [enabled, folder])
        }
    }

    /// Trimmed and capped; blank means no folder.
    static func folderName(_ name: String?) -> String? {
        guard let trimmed = name?.split(whereSeparator: \.isWhitespace).joined(separator: " "), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(60))
    }

    public func setTier(_ tier: SourceTier, sourceID: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE source SET tier = ? WHERE id = ?", arguments: [tier.rawValue, sourceID])
        }
    }

    public func setAllowsInsecureHTTP(_ allowed: Bool, sourceID: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE source SET allow_http = ?,
                      fail_count = CASE WHEN ? THEN 0 ELSE fail_count END,
                      last_fetch_at = CASE WHEN ? THEN NULL ELSE last_fetch_at END
                    WHERE id = ?
                    """,
                arguments: [allowed, allowed, allowed, sourceID]
            )
        }
    }

    public func setEnabled(_ enabled: Bool, sourceID: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE source SET enabled = ? WHERE id = ?", arguments: [enabled, sourceID])
        }
    }

    public func addUserSource(_ definition: SourceDefinition) async throws -> Bool {
        try await database.writer.write { db in
            let topics = String(decoding: try JSONEncoder().encode(definition.topics), as: UTF8.self)
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO source (kind, name, url, site_url, tier, tier_origin, topics, refresh_secs, folder)
                    VALUES (?, ?, ?, ?, ?, 'user', ?, ?, ?)
                    """,
                arguments: [
                    definition.kind.rawValue, definition.name, definition.url, definition.siteURL,
                    definition.tier.rawValue, topics, definition.refreshSeconds, Self.folderName(definition.folder)
                ]
            )
            return db.changesCount == 1
        }
    }

    public func delete(sourceID: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM source WHERE id = ?", arguments: [sourceID])
        }
    }

    public func record(_ outcome: FetchOutcome) async throws {
        try await database.writer.write { db in
            let at = outcome.at.unixSeconds
            var errorMessage: String?
            switch outcome.status {
            case .fetched, .notModified:
                try db.execute(
                    sql: """
                        UPDATE source
                        SET last_fetch_at = ?, last_ok_at = ?, fail_count = 0, last_error = NULL
                        WHERE id = ?
                        """,
                    arguments: [at, at, outcome.sourceID]
                )
            case .failed(let message):
                errorMessage = message
                try db.execute(
                    sql: """
                        UPDATE source
                        SET last_fetch_at = ?, fail_count = fail_count + 1, last_error = ?
                        WHERE id = ?
                        """,
                    arguments: [at, message, outcome.sourceID]
                )
            }

            if let validators = outcome.validators {
                try db.execute(
                    sql: "UPDATE source SET etag = ?, last_modified = ? WHERE id = ?",
                    arguments: [validators.etag, validators.lastModified, outcome.sourceID]
                )
            }

            try db.execute(
                sql: """
                    INSERT INTO fetch_log (source_id, at, http_status, items_seen, items_new, bytes, duration_ms, error)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    outcome.sourceID, at, outcome.httpStatus, outcome.itemsSeen, outcome.itemsNew,
                    outcome.bytes, outcome.durationMillis, errorMessage
                ]
            )
        }
    }

    private static func source(_ row: Row) -> Source {
        let topicsJSON: String = row["topics"]
        let topics = (try? JSONDecoder().decode([String].self, from: Data(topicsJSON.utf8))) ?? []
        let lastFetch: Int64? = row["last_fetch_at"]
        let lastOK: Int64? = row["last_ok_at"]
        return Source(
            id: row["id"],
            // Unknown values can only come from a newer app version's database; fall back safely.
            kind: SourceKind(rawValue: row["kind"]) ?? .rss,
            name: row["name"],
            url: row["url"],
            siteURL: row["site_url"],
            tier: SourceTier(rawValue: row["tier"]) ?? .unverified,
            topics: topics,
            enabled: row["enabled"],
            refreshSeconds: row["refresh_secs"],
            validators: HTTPValidators(etag: row["etag"], lastModified: row["last_modified"]),
            lastFetchAt: lastFetch.map(Date.init(unixSeconds:)),
            lastOKAt: lastOK.map(Date.init(unixSeconds:)),
            failCount: row["fail_count"],
            lastError: row["last_error"],
            isUserAdded: (row["tier_origin"] as String) == "user",
            allowsInsecureHTTP: row["allow_http"],
            folder: row["folder"],
            alertsEnabled: row["alert"]
        )
    }
}

// MARK: - Articles

public struct GRDBArticleRepository: ArticleRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func upsert(_ articles: [NewArticle]) async throws -> Int {
        guard !articles.isEmpty else { return 0 }
        return try await database.writer.write { db in
            var inserted = 0
            for article in articles {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO article
                          (source_id, external_id, url, canonical_url, title, excerpt, author,
                           published_at, retrieved_at, content_hash, score, comment_count, discussion_url)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        article.sourceID, article.externalID, article.url, article.canonicalURL,
                        article.title, article.excerpt, article.author,
                        article.publishedAt?.unixSeconds, article.retrievedAt.unixSeconds,
                        article.contentHash, article.score, article.commentCount, article.discussionURL
                    ]
                )
                if db.changesCount == 1 {
                    inserted += 1
                    continue
                }
                // Already stored: refresh what can legitimately change. First-seen time and
                // publication time are kept as originally recorded.
                try db.execute(
                    sql: """
                        UPDATE article
                        SET title = ?, excerpt = ?, content_hash = ?,
                            score = COALESCE(?, score), comment_count = COALESCE(?, comment_count)
                        WHERE source_id = ? AND canonical_url = ?
                          AND (content_hash <> ? OR score IS NOT ? OR comment_count IS NOT ?)
                        """,
                    arguments: [
                        article.title, article.excerpt, article.contentHash,
                        article.score, article.commentCount,
                        article.sourceID, article.canonicalURL,
                        article.contentHash, article.score, article.commentCount
                    ]
                )
            }
            return inserted
        }
    }

    public func latestStories(limit: Int, matching query: String?) async throws -> [Story] {
        let pattern = query.flatMap(FTS5Pattern.init(matchingAllPrefixesIn:))
        let wantsSearch = !(query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A query made only of punctuation has no searchable tokens: that is "no results", not "everything".
        if wantsSearch && pattern == nil { return [] }

        return try await database.writer.read { db in
            let select = """
                SELECT a.*, s.name AS source_name, s.tier AS source_tier
                FROM article a JOIN source s ON s.id = a.source_id
                """
            let order = " ORDER BY COALESCE(a.published_at, a.retrieved_at) DESC, a.id DESC LIMIT ?"
            let rows: [Row]
            if let pattern {
                rows = try Row.fetchAll(
                    db,
                    sql: select + " JOIN article_fts f ON f.rowid = a.id WHERE article_fts MATCH ?" + order,
                    arguments: [pattern, limit]
                )
            } else {
                rows = try Row.fetchAll(db, sql: select + order, arguments: [limit])
            }
            return rows.map(Self.story)
        }
    }

    public func articleCount() async throws -> Int {
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article") ?? 0
        }
    }

    static func story(_ row: Row) -> Story {
        let published: Int64? = row["published_at"]
        let retrieved: Int64 = row["retrieved_at"]
        return Story(
            id: row["id"],
            url: row["url"],
            canonicalURL: row["canonical_url"],
            title: row["title"],
            excerpt: row["excerpt"],
            author: row["author"],
            publishedAt: published.map(Date.init(unixSeconds:)),
            retrievedAt: Date(unixSeconds: retrieved),
            score: row["score"],
            commentCount: row["comment_count"],
            discussionURL: row["discussion_url"],
            sourceID: row["source_id"],
            sourceName: row["source_name"],
            sourceTier: SourceTier(rawValue: row["source_tier"]) ?? .unverified
        )
    }
}
