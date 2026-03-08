import Foundation
import GRDB

struct TagRepository: Sendable {
    let db: AppDatabase

    func fetchAll() throws -> [Tag] {
        try db.dbQueue.read { db in
            try Tag.order(Column("name").collating(.nocase).asc).fetchAll(db)
        }
    }

    func fetchMatching(prefix: String, limit: Int = 10) throws -> [Tag] {
        try db.dbQueue.read { db in
            try Tag
                .filter(Column("name").like("\(prefix)%"))
                .order(Column("name").collating(.nocase).asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func findOrCreate(name: String) throws -> Tag {
        try db.dbQueue.write { db in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = try Tag.filter(Column("name").collating(.nocase) == trimmed).fetchOne(db) {
                return existing
            }
            var tag = Tag(name: trimmed)
            try tag.insert(db)
            return tag
        }
    }

    func tagsForVideo(videoId: Int64) throws -> [Tag] {
        try db.dbQueue.read { db in
            try Video
                .filter(id: videoId)
                .including(all: Video.tagsThroughVideoTags)
                .asRequest(of: VideoInfo.self)
                .fetchOne(db)?
                .tags ?? []
        }
    }
}
