import Foundation
import GRDB

struct VideoRepository: Sendable {
    let db: AppDatabase

    // MARK: - Read

    func fetchAll(
        searchText: String? = nil,
        platform: Video.Platform? = nil,
        tagIds: [Int64] = [],
        sortBy: SortField = .addedAtDesc
    ) throws -> [VideoInfo] {
        try db.dbQueue.read { db in
            var request = Video
                .filter(Column("deletedAt") == nil)
                .including(all: Video.tagsThroughVideoTags)
                .asRequest(of: VideoInfo.self)

            if let platform {
                request = request.filter(Column("platform") == platform.rawValue)
            }

            if let searchText, !searchText.isEmpty {
                let pattern = "%\(searchText)%"
                request = request.filter(
                    Column("title").like(pattern) ||
                    Column("uploader").like(pattern) ||
                    Column("description").like(pattern)
                )
            }

            if !tagIds.isEmpty {
                let videoIds = try VideoTag
                    .filter(tagIds.contains(Column("tagId")))
                    .select(Column("videoId"), as: Int64.self)
                    .fetchAll(db)
                request = request.filter(videoIds.contains(Column("id")))
            }

            switch sortBy {
            case .addedAtDesc:
                request = request.order(Column("addedAt").desc)
            case .addedAtAsc:
                request = request.order(Column("addedAt").asc)
            case .titleAsc:
                request = request.order(Column("title").collating(.localizedCaseInsensitiveCompare).asc)
            case .durationDesc:
                request = request.order(Column("duration").desc)
            }

            return try request.fetchAll(db)
        }
    }

    func fetchOne(id: Int64) throws -> VideoInfo? {
        try db.dbQueue.read { db in
            try Video
                .filter(id: id)
                .including(all: Video.tagsThroughVideoTags)
                .asRequest(of: VideoInfo.self)
                .fetchOne(db)
        }
    }

    /// Returns the first non-deleted video whose `originalUrl` exactly matches, or nil.
    func findByOriginalURL(_ url: String) throws -> VideoInfo? {
        try db.dbQueue.read { db in
            try Video
                .filter(Column("originalUrl") == url)
                .filter(Column("deletedAt") == nil)
                .including(all: Video.tagsThroughVideoTags)
                .asRequest(of: VideoInfo.self)
                .fetchOne(db)
        }
    }

    // MARK: - Write

    func insert(_ video: inout Video) throws {
        try db.dbQueue.write { db in
            try video.insert(db)
        }
    }

    func updateStatus(videoId: Int64, status: Video.DownloadStatus, error: String? = nil) throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE video SET status = ?, errorMessage = ? WHERE id = ?",
                arguments: [status.rawValue, error, videoId]
            )
        }
    }

    func updateFilePath(videoId: Int64, filePath: String, fileSize: Int64?) throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE video SET filePath = ?, fileSize = ? WHERE id = ?",
                arguments: [filePath, fileSize, videoId]
            )
        }
    }

    /// Updates all file-related fields at once — used when manually attaching a local file.
    func updateMedia(
        videoId: Int64,
        filePath: String,
        fileSize: Int64?,
        width: Int?,
        height: Int?,
        thumbnailPath: String?
    ) throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE video
                    SET filePath = ?, fileSize = ?, width = ?, height = ?,
                        status = 'completed', errorMessage = NULL
                    WHERE id = ?
                    """,
                arguments: [filePath, fileSize, width, height, videoId]
            )
            if let thumbnailPath {
                try db.execute(
                    sql: "UPDATE video SET thumbnailPath = ? WHERE id = ?",
                    arguments: [thumbnailPath, videoId]
                )
            }
        }
    }

    func updateNotes(videoId: Int64, notes: String?) throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE video SET notes = ? WHERE id = ?",
                arguments: [notes, videoId]
            )
        }
    }

    func updateThumbnailPath(videoId: Int64, thumbnailPath: String) throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE video SET thumbnailPath = ? WHERE id = ?",
                arguments: [thumbnailPath, videoId]
            )
        }
    }

    func setTags(videoId: Int64, tagNames: [String]) throws {
        try db.dbQueue.write { db in
            // Remove existing tags
            try VideoTag.filter(Column("videoId") == videoId).deleteAll(db)

            // Add new tags (find or create)
            for name in tagNames {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                var tag: Tag
                if let existing = try Tag.filter(Column("name").collating(.nocase) == trimmed).fetchOne(db) {
                    tag = existing
                } else {
                    tag = Tag(name: trimmed)
                    try tag.insert(db)
                }

                if let tagId = tag.id {
                    let videoTag = VideoTag(videoId: videoId, tagId: tagId)
                    try videoTag.insert(db)
                }
            }
        }
    }

    // MARK: - Trash

    func fetchTrashed() throws -> [VideoInfo] {
        try db.dbQueue.read { db in
            try Video
                .filter(Column("deletedAt") != nil)
                .including(all: Video.tagsThroughVideoTags)
                .asRequest(of: VideoInfo.self)
                .order(Column("deletedAt").desc)
                .fetchAll(db)
        }
    }

    func trashedCount() throws -> Int {
        try db.dbQueue.read { db in
            try Video.filter(Column("deletedAt") != nil).fetchCount(db)
        }
    }

    func softDelete(id: Int64) throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE video SET deletedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    func restore(id: Int64) throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE video SET deletedAt = NULL WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func fetchExpiredTrash(olderThan: Date) throws -> [Video] {
        try db.dbQueue.read { db in
            try Video
                .filter(Column("deletedAt") != nil)
                .filter(Column("deletedAt") < olderThan)
                .fetchAll(db)
        }
    }

    // MARK: - Permanent Delete

    func delete(id: Int64) throws {
        try db.dbQueue.write { db in
            _ = try Video.deleteOne(db, id: id)
        }
    }

    func deleteAll(ids: [Int64]) throws {
        try db.dbQueue.write { db in
            _ = try Video.filter(ids: ids).deleteAll(db)
        }
    }
}

enum SortField: String, CaseIterable, Sendable {
    case addedAtDesc = "Newest First"
    case addedAtAsc = "Oldest First"
    case titleAsc = "Title A-Z"
    case durationDesc = "Longest First"
}
