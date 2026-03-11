import Foundation

@Observable
@MainActor
final class RoomsViewModel {
    private let roomRepo: RoomRepository

    var rooms: [Room] = []
    var collectionsByRoom: [Int64: [VideoCollection]] = [:]

    init(roomRepo: RoomRepository) {
        self.roomRepo = roomRepo
    }

    func load() {
        rooms = (try? roomRepo.fetchAllRooms()) ?? []
        var byRoom: [Int64: [VideoCollection]] = [:]
        for room in rooms {
            if let id = room.id {
                byRoom[id] = (try? roomRepo.fetchCollections(roomId: id)) ?? []
            }
        }
        collectionsByRoom = byRoom
    }

    func collections(for roomId: Int64) -> [VideoCollection] {
        collectionsByRoom[roomId] ?? []
    }

    // MARK: - Rooms

    func addRoom(name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? roomRepo.insertRoom(name: name)
        load()
    }

    func renameRoom(_ room: Room, to name: String) {
        guard let id = room.id,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? roomRepo.updateRoom(id: id, name: name)
        load()
    }

    func deleteRoom(_ room: Room) {
        guard let id = room.id else { return }
        try? roomRepo.deleteRoom(id: id)
        load()
    }

    // MARK: - Collections

    func addCollection(to roomId: Int64, name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? roomRepo.insertCollection(roomId: roomId, name: name)
        load()
    }

    func renameCollection(_ collection: VideoCollection, to name: String) {
        guard let id = collection.id,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? roomRepo.updateCollection(id: id, name: name)
        load()
    }

    func deleteCollection(_ collection: VideoCollection) {
        guard let id = collection.id else { return }
        try? roomRepo.deleteCollection(id: id)
        load()
    }

    func room(forCollectionId collectionId: Int64) -> Room? {
        for room in rooms {
            guard let roomId = room.id else { continue }
            if let cols = collectionsByRoom[roomId], cols.contains(where: { $0.id == collectionId }) {
                return room
            }
        }
        return nil
    }

    func collection(id: Int64) -> VideoCollection? {
        for cols in collectionsByRoom.values {
            if let col = cols.first(where: { $0.id == id }) { return col }
        }
        return nil
    }
}
