import Foundation
import GRDB

struct CollectionItem: Codable, FetchableRecord, PersistableRecord, Sendable {
    var collectionId: Int64
    var videoId: Int64
    var sortOrder: Int

    static let databaseTableName = "collectionItem"
}

extension CollectionItem {
    static let video = belongsTo(Video.self)
    static let collection = belongsTo(VideoCollection.self)
}
