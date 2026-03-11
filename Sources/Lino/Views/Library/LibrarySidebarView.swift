import SwiftUI

enum LibrarySelection: Hashable {
    case allItems
    case room(Int64)
    case collection(Int64)
    case trash
}

struct LibrarySidebarView: View {
    @Binding var selection: LibrarySelection?
    @Bindable var roomsVM: RoomsViewModel
    let trashedCount: Int

    @State private var showAddRoom = false
    @State private var newRoomName = ""
    @State private var roomToRename: Room?
    @State private var renameRoomText = ""

    var body: some View {
        List(selection: $selection) {
            // Library
            Section("Library") {
                Label("All Items", systemImage: "square.grid.2x2")
                    .tag(LibrarySelection.allItems)
            }

            // Rooms
            Section("Rooms") {
                ForEach(roomsVM.rooms) { room in
                    roomRow(room)
                }

                Button {
                    newRoomName = ""
                    showAddRoom = true
                } label: {
                    Label("New Room", systemImage: "plus")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }

            // Trash
            Section {
                HStack {
                    Label("Trash", systemImage: "trash")
                    Spacer()
                    if trashedCount > 0 {
                        Text("\(trashedCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                    }
                }
                .tag(LibrarySelection.trash)
            }
        }
        .listStyle(.sidebar)
        // Add Room
        .alert("New Room", isPresented: $showAddRoom) {
            TextField("Room name", text: $newRoomName)
            Button("Create") { roomsVM.addRoom(name: newRoomName) }
            Button("Cancel", role: .cancel) {}
        }
        // Rename Room
        .alert("Rename Room", isPresented: Binding(
            get: { roomToRename != nil },
            set: { if !$0 { roomToRename = nil } }
        )) {
            TextField("Room name", text: $renameRoomText)
            Button("Rename") {
                if let room = roomToRename { roomsVM.renameRoom(room, to: renameRoomText) }
                roomToRename = nil
            }
            Button("Cancel", role: .cancel) { roomToRename = nil }
        }
    }

    private func roomRow(_ room: Room) -> some View {
        Label(room.name, systemImage: "square.3.layers.3d")
            .tag(LibrarySelection.room(room.id!))
            .contextMenu {
                Button("Rename") {
                    renameRoomText = room.name
                    roomToRename = room
                }
                Button("Delete Room", role: .destructive) {
                    roomsVM.deleteRoom(room)
                    if case .room(let id) = selection, id == room.id { selection = .allItems }
                }
            }
    }
}
