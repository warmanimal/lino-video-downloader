import Foundation
import GRDB

final class AppDatabase: Sendable {
    let dbQueue: DatabaseQueue

    init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "video") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ytdlpId", .text).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("uploader", .text)
                t.column("uploaderUrl", .text)
                t.column("platform", .text).notNull()
                t.column("originalUrl", .text).notNull()
                t.column("webpageUrl", .text)
                t.column("uploadDate", .text)
                t.column("duration", .double)
                t.column("filePath", .text).notNull()
                t.column("fileSize", .integer)
                t.column("thumbnailPath", .text)
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("addedAt", .datetime).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("errorMessage", .text)
            }

            try db.create(index: "video_on_platform", on: "video", columns: ["platform"])
            try db.create(index: "video_on_status", on: "video", columns: ["status"])
            try db.create(index: "video_on_addedAt", on: "video", columns: ["addedAt"])

            try db.create(table: "tag") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique().collate(.nocase)
            }

            try db.create(table: "videoTag") { t in
                t.column("videoId", .integer).notNull()
                    .references("video", onDelete: .cascade)
                t.column("tagId", .integer).notNull()
                    .references("tag", onDelete: .cascade)
                t.primaryKey(["videoId", "tagId"])
            }

            try db.create(index: "videoTag_on_tagId", on: "videoTag", columns: ["tagId"])
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "video") { t in
                t.add(column: "deletedAt", .datetime)
            }
            try db.create(index: "video_on_deletedAt", on: "video", columns: ["deletedAt"])
        }

        return migrator
    }
}

extension AppDatabase {
    /// Creates the shared on-disk database
    static func makeShared() throws -> AppDatabase {
        try Constants.ensureDirectoriesExist()
        let dbQueue = try DatabaseQueue(path: Constants.databasePath.path)
        return try AppDatabase(dbQueue)
    }

    /// Creates an in-memory database for testing
    static func makeEmpty() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: .init())
        return try AppDatabase(dbQueue)
    }
}
