import Domain
import Foundation
import GRDB

public struct GRDBWidgetInstanceRepository: WidgetInstanceRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func allInstances() async throws -> [WidgetInstance] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM widget_instance ORDER BY created_at, id").map { row in
                let settingsJSON: String = row["settings"]
                let created: Int64 = row["created_at"]
                return WidgetInstance(
                    id: row["id"], widgetID: row["widget_id"],
                    // Settings that cannot be read are dropped; the widget then uses its defaults.
                    settings: (try? JSONDecoder().decode([String: WidgetSettingValue].self, from: Data(settingsJSON.utf8))) ?? [:],
                    size: row["size"], x: row["x"], y: row["y"], createdAt: Date(unixSeconds: created)
                )
            }
        }
    }

    public func save(_ instance: WidgetInstance) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let settings = String(decoding: try encoder.encode(instance.settings), as: UTF8.self)
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO widget_instance (id, widget_id, settings, size, x, y, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET settings = excluded.settings, size = excluded.size, x = excluded.x, y = excluded.y
                    """,
                arguments: [instance.id, instance.widgetID, settings, instance.size, instance.x, instance.y, instance.createdAt.unixSeconds]
            )
        }
    }

    public func delete(instanceID: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM widget_instance WHERE id = ?", arguments: [instanceID])
        }
    }
}
