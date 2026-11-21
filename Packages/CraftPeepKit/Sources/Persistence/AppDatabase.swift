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

        migrator.registerMigration("v2-clusters") { db in
            try db.execute(sql: """
                CREATE TABLE cluster (
                  id              INTEGER PRIMARY KEY,
                  headline        TEXT NOT NULL DEFAULT '',
                  lead_article_id INTEGER REFERENCES article(id) ON DELETE SET NULL,
                  first_seen_at   INTEGER NOT NULL,
                  last_seen_at    INTEGER NOT NULL,
                  member_count    INTEGER NOT NULL DEFAULT 0,
                  source_count    INTEGER NOT NULL DEFAULT 0,
                  independent_count INTEGER NOT NULL DEFAULT 0,
                  best_tier       TEXT NOT NULL DEFAULT 'unverified',
                  kind            TEXT,
                  kind_basis      TEXT,
                  kind_confidence TEXT,
                  verification    TEXT NOT NULL DEFAULT 'unverified',
                  score           INTEGER,
                  comment_count   INTEGER
                );
                CREATE INDEX cluster_last_seen ON cluster(last_seen_at DESC);

                ALTER TABLE article ADD COLUMN cluster_id INTEGER REFERENCES cluster(id) ON DELETE SET NULL;
                CREATE INDEX article_cluster ON article(cluster_id);

                CREATE TABLE cluster_entity (
                  cluster_id INTEGER NOT NULL REFERENCES cluster(id) ON DELETE CASCADE,
                  name       TEXT NOT NULL,
                  kind       TEXT NOT NULL,
                  PRIMARY KEY (cluster_id, name)
                );
                CREATE INDEX cluster_entity_name ON cluster_entity(name);

                CREATE TABLE interest (
                  keyword TEXT PRIMARY KEY COLLATE NOCASE,
                  level   INTEGER NOT NULL
                );
                """)
        }

        migrator.registerMigration("v3-user-state") { db in
            // Kept apart from content so that a future sync moves this small table, not the corpus.
            try db.execute(sql: """
                CREATE TABLE cluster_state (
                  cluster_id INTEGER PRIMARY KEY REFERENCES cluster(id) ON DELETE CASCADE,
                  read_at    INTEGER,
                  saved_at   INTEGER,
                  favourite  INTEGER NOT NULL DEFAULT 0
                );
                """)
        }

        migrator.registerMigration("v4-future-dates") { db in
            // Earlier builds accepted publication dates up to a day ahead, which showed as "in 18 hours"
            // and ranked as brand new. Such dates are now treated as missing.
            try db.execute(sql: "UPDATE article SET published_at = NULL WHERE published_at > retrieved_at + 300")
        }

        migrator.registerMigration("v5-ai") { db in
            try db.execute(sql: """
                CREATE TABLE summary (
                  cluster_id      INTEGER PRIMARY KEY REFERENCES cluster(id) ON DELETE CASCADE,
                  input_hash      TEXT NOT NULL,
                  text            TEXT NOT NULL,
                  why_it_matters  TEXT NOT NULL,
                  provider        TEXT NOT NULL,
                  model           TEXT NOT NULL,
                  created_at      INTEGER NOT NULL
                );

                CREATE TABLE briefing (
                  for_date   TEXT PRIMARY KEY,
                  body       TEXT NOT NULL,
                  created_at INTEGER NOT NULL
                );

                CREATE TABLE ai_usage (
                  id              INTEGER PRIMARY KEY,
                  at              INTEGER NOT NULL,
                  feature         TEXT NOT NULL,
                  provider        TEXT NOT NULL,
                  model           TEXT NOT NULL,
                  input_tokens    INTEGER,
                  output_tokens   INTEGER,
                  est_cost_micros INTEGER,
                  outcome         TEXT NOT NULL
                );
                CREATE INDEX ai_usage_at ON ai_usage(at);
                """)
        }

        migrator.registerMigration("v6-repositories") { db in
            try db.execute(sql: """
                CREATE TABLE repository (
                  id            INTEGER PRIMARY KEY,
                  full_name     TEXT NOT NULL,
                  description   TEXT,
                  url           TEXT NOT NULL,
                  language      TEXT,
                  topics        TEXT NOT NULL DEFAULT '[]',
                  stars         INTEGER NOT NULL,
                  forks         INTEGER NOT NULL DEFAULT 0,
                  created_at    INTEGER,
                  pushed_at     INTEGER,
                  first_seen_at INTEGER NOT NULL,
                  last_seen_at  INTEGER NOT NULL
                );

                -- One row per repository per day: enough to measure change, small enough to keep.
                CREATE TABLE repo_snapshot (
                  repo_id INTEGER NOT NULL REFERENCES repository(id) ON DELETE CASCADE,
                  day     INTEGER NOT NULL,
                  at      INTEGER NOT NULL,
                  stars   INTEGER NOT NULL,
                  PRIMARY KEY (repo_id, day)
                );

                CREATE TABLE meta (
                  key   TEXT PRIMARY KEY,
                  value TEXT NOT NULL
                );
                """)
        }

        migrator.registerMigration("v7-widget-instances") { db in
            try db.execute(sql: """
                CREATE TABLE widget_instance (
                  id         TEXT PRIMARY KEY,
                  widget_id  TEXT NOT NULL,
                  settings   TEXT NOT NULL DEFAULT '{}',
                  size       TEXT NOT NULL,
                  x          REAL,
                  y          REAL,
                  created_at INTEGER NOT NULL
                );
                """)
        }

        migrator.registerMigration("v8-widget-appearance") { db in
            try db.execute(sql: """
                ALTER TABLE widget_instance ADD COLUMN style TEXT NOT NULL DEFAULT 'automatic';
                ALTER TABLE widget_instance ADD COLUMN tint TEXT NOT NULL DEFAULT 'blue';
                """)
        }

        migrator.registerMigration("v9-source-allow-http") { db in
            try db.execute(sql: "ALTER TABLE source ADD COLUMN allow_http INTEGER NOT NULL DEFAULT 0")
        }

        migrator.registerMigration("v10-source-folders") { db in
            try db.execute(sql: "ALTER TABLE source ADD COLUMN folder TEXT")
            try db.execute(sql: "CREATE INDEX source_folder ON source(folder)")
        }

        migrator.registerMigration("v11-trending-alerts") { db in
            try db.execute(sql: """
                ALTER TABLE source ADD COLUMN alert INTEGER NOT NULL DEFAULT 0;
                CREATE TABLE alert_log (
                  cluster_id INTEGER PRIMARY KEY REFERENCES cluster(id) ON DELETE CASCADE,
                  sent_at    INTEGER NOT NULL
                );
                """)
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
