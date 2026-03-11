import Foundation
import GRDB

struct Room: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var name: String
    var sortOrder: Int

    static let databaseTableName = "room"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Room {
    static let collections = hasMany(VideoCollection.self)
}
