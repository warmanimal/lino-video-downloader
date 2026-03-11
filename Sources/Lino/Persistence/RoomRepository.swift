import Foundation
import GRDB

struct RoomRepository: Sendable {
    let db: AppDatabase

    // MARK: - Rooms

    func fetchAllRooms() throws -> [Room] {
        try db.dbQueue.read { db in
            try Room.order(Column("sortOrder").asc, Column("name").asc).fetchAll(db)
        }
    }

    @discardableResult
    func insertRoom(name: String) throws -> Room {
        try db.dbQueue.write { db in
            let count = try Room.fetchCount(db)
            var room = Room(id: nil, name: name, sortOrder: count)
            try room.insert(db)
            return room
        }
    }

    func updateRoom(id: Int64, name: String) throws {
        try db.dbQueue.write { db in
            try db.execute(sql: "UPDATE room SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    func deleteRoom(id: Int64) throws {
        try db.dbQueue.write { db in
            _ = try Room.deleteOne(db, id: id)
        }
    }

    func reorderRooms(_ ids: [Int64]) throws {
        try db.dbQueue.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE room SET sortOrder = ? WHERE id = ?", arguments: [index, id])
            }
        }
    }

    // MARK: - Collections

    func fetchCollections(roomId: Int64) throws -> [VideoCollection] {
        try db.dbQueue.read { db in
            try VideoCollection
                .filter(Column("roomId") == roomId)
                .order(Column("sortOrder").asc, Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetchCollection(id: Int64) throws -> VideoCollection? {
        try db.dbQueue.read { db in
            try VideoCollection.fetchOne(db, id: id)
        }
    }

    @discardableResult
    func insertCollection(roomId: Int64, name: String) throws -> VideoCollection {
        try db.dbQueue.write { db in
            let count = try VideoCollection.filter(Column("roomId") == roomId).fetchCount(db)
            var col = VideoCollection(id: nil, roomId: roomId, name: name, sortOrder: count)
            try col.insert(db)
            return col
        }
    }

    func updateCollection(id: Int64, name: String) throws {
        try db.dbQueue.write { db in
            try db.execute(sql: "UPDATE collection SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    func deleteCollection(id: Int64) throws {
        try db.dbQueue.write { db in
            _ = try VideoCollection.deleteOne(db, id: id)
        }
    }

    func reorderCollections(roomId: Int64, ids: [Int64]) throws {
        try db.dbQueue.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE collection SET sortOrder = ? WHERE id = ?", arguments: [index, id])
            }
        }
    }

    // MARK: - Collection Items

    func addItem(videoId: Int64, collectionId: Int64) throws {
        try db.dbQueue.write { db in
            let exists = try CollectionItem
                .filter(Column("collectionId") == collectionId)
                .filter(Column("videoId") == videoId)
                .fetchOne(db) != nil
            guard !exists else { return }
            let count = try CollectionItem.filter(Column("collectionId") == collectionId).fetchCount(db)
            let item = CollectionItem(collectionId: collectionId, videoId: videoId, sortOrder: count)
            try item.insert(db)
        }
    }

    func removeItem(videoId: Int64, collectionId: Int64) throws {
        try db.dbQueue.write { db in
            _ = try CollectionItem
                .filter(Column("collectionId") == collectionId)
                .filter(Column("videoId") == videoId)
                .deleteAll(db)
        }
    }

    func fetchItems(collectionId: Int64) throws -> [VideoInfo] {
        try db.dbQueue.read { db in
            let videoIds = try CollectionItem
                .filter(Column("collectionId") == collectionId)
                .order(Column("sortOrder").asc)
                .select(Column("videoId"), as: Int64.self)
                .fetchAll(db)

            guard !videoIds.isEmpty else { return [] }

            let videos = try Video
                .filter(videoIds.contains(Column("id")))
                .filter(Column("deletedAt") == nil)
                .including(all: Video.tagsThroughVideoTags)
                .asRequest(of: VideoInfo.self)
                .fetchAll(db)

            let videoMap = Dictionary(
                uniqueKeysWithValues: videos.compactMap { info -> (Int64, VideoInfo)? in
                    guard let id = info.video.id else { return nil }
                    return (id, info)
                }
            )
            return videoIds.compactMap { videoMap[$0] }
        }
    }

    func fetchItemCount(collectionId: Int64) throws -> Int {
        try db.dbQueue.read { db in
            try CollectionItem
                .filter(Column("collectionId") == collectionId)
                .fetchCount(db)
        }
    }

    func reorderItems(collectionId: Int64, videoIds: [Int64]) throws {
        try db.dbQueue.write { db in
            for (index, videoId) in videoIds.enumerated() {
                try db.execute(
                    sql: "UPDATE collectionItem SET sortOrder = ? WHERE collectionId = ? AND videoId = ?",
                    arguments: [index, collectionId, videoId]
                )
            }
        }
    }

    // MARK: - Shortcuts

    func fetchShortcuts(roomId: Int64) throws -> [RoomShortcut] {
        try db.dbQueue.read { db in
            try RoomShortcut
                .filter(Column("roomId") == roomId)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
        }
    }

    @discardableResult
    func insertShortcut(_ shortcut: RoomShortcut) throws -> RoomShortcut {
        try db.dbQueue.write { db in
            var s = shortcut
            try s.insert(db)
            return s
        }
    }

    func updateShortcut(_ shortcut: RoomShortcut) throws {
        try db.dbQueue.write { db in
            try shortcut.update(db)
        }
    }

    func deleteShortcut(id: Int64) throws {
        try db.dbQueue.write { db in
            _ = try RoomShortcut.deleteOne(db, id: id)
        }
    }

    // MARK: - Room Items (items directly in a room, not inside a collection)

    func addItemToRoom(videoId: Int64, roomId: Int64) throws {
        try db.dbQueue.write { db in
            let exists = try RoomItem
                .filter(Column("roomId") == roomId)
                .filter(Column("videoId") == videoId)
                .fetchOne(db) != nil
            guard !exists else { return }
            let count = try RoomItem.filter(Column("roomId") == roomId).fetchCount(db)
            let item = RoomItem(roomId: roomId, videoId: videoId, sortOrder: count)
            try item.insert(db)
        }
    }

    func removeItemFromRoom(videoId: Int64, roomId: Int64) throws {
        try db.dbQueue.write { db in
            _ = try RoomItem
                .filter(Column("roomId") == roomId)
                .filter(Column("videoId") == videoId)
                .deleteAll(db)
        }
    }

    func fetchRoomItems(roomId: Int64) throws -> [VideoInfo] {
        try db.dbQueue.read { db in
            // Items directly added to the room
            let directIds = try RoomItem
                .filter(Column("roomId") == roomId)
                .order(Column("sortOrder").asc)
                .select(Column("videoId"), as: Int64.self)
                .fetchAll(db)

            // Items in any collection belonging to this room
            let collectionIds = try VideoCollection
                .filter(Column("roomId") == roomId)
                .select(Column("id"), as: Int64.self)
                .fetchAll(db)

            var collectionItemIds: [Int64] = []
            if !collectionIds.isEmpty {
                collectionItemIds = try CollectionItem
                    .filter(collectionIds.contains(Column("collectionId")))
                    .select(Column("videoId"), as: Int64.self)
                    .fetchAll(db)
            }

            // Union, deduplicated, direct items first
            var seen = Set<Int64>()
            let uniqueIds = (directIds + collectionItemIds).filter { seen.insert($0).inserted }
            guard !uniqueIds.isEmpty else { return [] }

            let videos = try Video
                .filter(uniqueIds.contains(Column("id")))
                .filter(Column("deletedAt") == nil)
                .including(all: Video.tagsThroughVideoTags)
                .asRequest(of: VideoInfo.self)
                .fetchAll(db)

            let videoMap = Dictionary(
                uniqueKeysWithValues: videos.compactMap { info -> (Int64, VideoInfo)? in
                    guard let id = info.video.id else { return nil }
                    return (id, info)
                }
            )
            return uniqueIds.compactMap { videoMap[$0] }
        }
    }

    // MARK: - All collections (cross-room)

    func fetchAllCollections() throws -> [VideoCollection] {
        try db.dbQueue.read { db in
            try VideoCollection
                .order(Column("sortOrder").asc, Column("name").asc)
                .fetchAll(db)
        }
    }

    // MARK: - Membership queries

    func fetchMemberships(videoId: Int64) throws -> VideoMemberships {
        try db.dbQueue.read { db in
            // Direct room memberships
            let roomIds = try RoomItem
                .filter(Column("videoId") == videoId)
                .select(Column("roomId"), as: Int64.self)
                .fetchAll(db)

            let directRooms = roomIds.isEmpty ? [] : try Room
                .filter(roomIds.contains(Column("id")))
                .order(Column("sortOrder").asc)
                .fetchAll(db)

            // Collection memberships
            let collectionIds = try CollectionItem
                .filter(Column("videoId") == videoId)
                .select(Column("collectionId"), as: Int64.self)
                .fetchAll(db)

            let collectionList = collectionIds.isEmpty ? [] : try VideoCollection
                .filter(collectionIds.contains(Column("id")))
                .fetchAll(db)

            var withRooms: [(collection: VideoCollection, room: Room)] = []
            for col in collectionList {
                if let room = try Room.filter(Column("id") == col.roomId).fetchOne(db) {
                    withRooms.append((collection: col, room: room))
                }
            }

            return VideoMemberships(directRooms: directRooms, collections: withRooms)
        }
    }
}

/// Describes which Rooms and Collections a library item currently belongs to.
struct VideoMemberships: Sendable {
    let directRooms: [Room]
    let collections: [(collection: VideoCollection, room: Room)]

    var isEmpty: Bool { directRooms.isEmpty && collections.isEmpty }
}
