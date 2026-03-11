import Foundation
import GRDB

struct RoomItem: Codable, FetchableRecord, PersistableRecord, Sendable {
    var roomId: Int64
    var videoId: Int64
    var sortOrder: Int

    static let databaseTableName = "roomItem"
}

extension RoomItem {
    static let video = belongsTo(Video.self)
    static let room = belongsTo(Room.self)
}
