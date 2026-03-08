import Foundation
import GRDB

struct Tag: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable, Sendable {
    var id: Int64?
    var name: String

    static let databaseTableName = "tag"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Tag {
    static let videoTags = hasMany(VideoTag.self)
    static let videos = hasMany(Video.self, through: videoTags, using: VideoTag.video)
}
