import Foundation
import GRDB

// Named VideoCollection to avoid shadowing Swift's Collection protocol
struct VideoCollection: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var roomId: Int64
    var name: String
    var sortOrder: Int

    static let databaseTableName = "collection"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension VideoCollection {
    static let room = belongsTo(Room.self)
    static let collectionItems = hasMany(CollectionItem.self)
}
