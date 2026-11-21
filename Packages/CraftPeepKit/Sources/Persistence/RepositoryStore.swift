import Domain
import Foundation
import GRDB

public struct GRDBRepositoryStore: RepositoryStore {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func record(_ repositories: [Repository], at now: Date) async throws {
        guard !repositories.isEmpty else { return }
        try await database.writer.write { db in
            let seconds = now.unixSeconds
            for repository in repositories {
                let topics = String(decoding: (try? JSONEncoder().encode(repository.topics)) ?? Data("[]".utf8), as: UTF8.self)
                try db.execute(
                    sql: """
                        INSERT INTO repository
                          (id, full_name, description, url, language, topics, stars, forks, created_at, pushed_at, first_seen_at, last_seen_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                          full_name = excluded.full_name, description = excluded.description, url = excluded.url,
                          language = excluded.language, topics = excluded.topics, stars = excluded.stars, forks = excluded.forks,
                          created_at = excluded.created_at, pushed_at = excluded.pushed_at, last_seen_at = excluded.last_seen_at
                        """,
                    arguments: [
                        repository.id, repository.fullName, repository.description, repository.url, repository.language, topics,
                        repository.stars, repository.forks, repository.createdAt?.unixSeconds, repository.pushedAt?.unixSeconds,
                        seconds, seconds
                    ]
                )
                // The first reading of the day is kept, so a baseline is as old as it can be.
                try db.execute(
                    sql: "INSERT OR IGNORE INTO repo_snapshot (repo_id, day, at, stars) VALUES (?, ?, ?, ?)",
                    arguments: [repository.id, seconds / 86_400, seconds, repository.stars]
                )
            }
        }
    }

    public func histories(seenSince: Date, baselineSince: Date) async throws -> [RepositoryHistory] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT r.*, s.stars AS baseline_stars, s.at AS baseline_at
                    FROM repository r
                    LEFT JOIN repo_snapshot s ON s.repo_id = r.id
                      AND s.at = (SELECT MIN(at) FROM repo_snapshot WHERE repo_id = r.id AND at >= ?)
                    WHERE r.last_seen_at >= ?
                    ORDER BY r.stars DESC
                    """,
                arguments: [baselineSince.unixSeconds, seenSince.unixSeconds]
            )
            return rows.map { row in
                let topicsJSON: String = row["topics"]
                let created: Int64? = row["created_at"]
                let pushed: Int64? = row["pushed_at"]
                let baselineAt: Int64? = row["baseline_at"]
                return RepositoryHistory(
                    repository: Repository(
                        id: row["id"], fullName: row["full_name"], description: row["description"], url: row["url"],
                        language: row["language"],
                        topics: (try? JSONDecoder().decode([String].self, from: Data(topicsJSON.utf8))) ?? [],
                        stars: row["stars"], forks: row["forks"],
                        createdAt: created.map(Date.init(unixSeconds:)), pushedAt: pushed.map(Date.init(unixSeconds:))
                    ),
                    baselineStars: row["baseline_stars"],
                    baselineAt: baselineAt.map(Date.init(unixSeconds:))
                )
            }
        }
    }

    public func purgeRepositories(notSeenSince before: Date, snapshotsBefore: Date) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM repository WHERE last_seen_at < ?", arguments: [before.unixSeconds])
            try db.execute(sql: "DELETE FROM repo_snapshot WHERE at < ?", arguments: [snapshotsBefore.unixSeconds])
        }
    }

    public func meta(_ key: String) async throws -> String? {
        try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key])
        }
    }

    public func setMeta(_ value: String?, for key: String) async throws {
        try await database.writer.write { db in
            if let value {
                try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM meta WHERE key = ?", arguments: [key])
            }
        }
    }
}
