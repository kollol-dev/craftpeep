import Foundation
import GRDB

/// Owns the SQLite connection and the schema. Everything above this target talks to
/// repositories, never to GRDB.
public final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    /// Opens (creating if needed) the database file at `url` and migrates it.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        writer = try DatabasePool(path: url.path, configuration: configuration)
        try Self.migrator.migrate(writer)
    }

    /// A private in-memory database, for tests and previews.
    public init() throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        writer = try DatabaseQueue(configuration: configuration)
        try Self.migrator.migrate(writer)
    }

    /// Schema history. Never edit a registered migration after it has shipped; add a new one.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE source (
                  id            INTEGER PRIMARY KEY,
                  kind          TEXT NOT NULL,
                  name          TEXT NOT NULL,
                  url           TEXT NOT NULL UNIQUE,
                  site_url      TEXT,
                  tier          TEXT NOT NULL,
                  tier_origin   TEXT NOT NULL DEFAULT 'catalog',
                  topics        TEXT NOT NULL DEFAULT '[]',
                  priority      INTEGER NOT NULL DEFAULT 0,
                  enabled       INTEGER NOT NULL DEFAULT 1,
                  refresh_secs  INTEGER NOT NULL,
                  etag          TEXT,
                  last_modified TEXT,
                  last_fetch_at INTEGER,
                  last_ok_at    INTEGER,
                  fail_count    INTEGER NOT NULL DEFAULT 0,
                  last_error    TEXT
                );

                CREATE TABLE article (
                  id             INTEGER PRIMARY KEY,
                  source_id      INTEGER NOT NULL REFERENCES source(id) ON DELETE CASCADE,
                  external_id    TEXT,
                  url            TEXT NOT NULL,
                  canonical_url  TEXT NOT NULL,
                  title          TEXT NOT NULL,
                  excerpt        TEXT,
                  author         TEXT,
                  published_at   INTEGER,
                  retrieved_at   INTEGER NOT NULL,
                  content_hash   TEXT NOT NULL,
                  score          INTEGER,
                  comment_count  INTEGER,
                  discussion_url TEXT,
                  UNIQUE (source_id, canonical_url)
                );
                CREATE INDEX article_canonical ON article(canonical_url);
                CREATE INDEX article_sort ON article(COALESCE(published_at, retrieved_at) DESC);

                CREATE TABLE fetch_log (
                  id          INTEGER PRIMARY KEY,
                  source_id   INTEGER NOT NULL REFERENCES source(id) ON DELETE CASCADE,
                  at          INTEGER NOT NULL,
                  http_status INTEGER,
                  items_seen  INTEGER NOT NULL DEFAULT 0,
                  items_new   INTEGER NOT NULL DEFAULT 0,
                  bytes       INTEGER NOT NULL DEFAULT 0,
                  duration_ms INTEGER NOT NULL DEFAULT 0,
                  error       TEXT
                );
                CREATE INDEX fetch_log_source ON fetch_log(source_id, at DESC);
                """)

            // External-content FTS index kept in step with `article` by triggers GRDB generates.
            try db.create(virtualTable: "article_fts", using: FTS5()) { table in
                table.synchronize(withTable: "article")
                table.tokenizer = .porter(wrapping: .unicode61())
                table.column("title")
                table.column("excerpt")
            }
        }

        return migrator
    }
}

extension Date {
    var unixSeconds: Int64 { Int64(timeIntervalSince1970.rounded()) }

    init(unixSeconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(unixSeconds))
    }
}
