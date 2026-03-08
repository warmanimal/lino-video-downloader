import Foundation
import GRDB

struct VideoTag: Codable, FetchableRecord, PersistableRecord, Sendable {
    var videoId: Int64
    var tagId: Int64

    static let databaseTableName = "videoTag"
}

extension VideoTag {
    static let video = belongsTo(Video.self)
    static let tag = belongsTo(Tag.self)
}
