import Foundation
import GRDB

struct RoomShortcut: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var roomId: Int64
    var title: String
    var url: String
    var notes: String?
    var iconData: Data?        // Favicon image bytes (BLOB)
    var customSymbol: String?  // SF Symbol name chosen by user
    var symbolColor: String?   // Named color for the symbol
    var sortOrder: Int

    static let databaseTableName = "roomShortcut"
}
