import SwiftUI
import AppKit

struct RoomView: View {
    let room: Room
    @Bindable var roomsVM: RoomsViewModel
    let roomRepo: RoomRepository
    @Binding var selectedVideoId: Int64?
    let onSelectCollection: (VideoCollection) -> Void

    @Environment(\.appState) private var appState
    @State private var roomItems: [VideoInfo] = []
    @State private var shortcuts: [RoomShortcut] = []
    @State private var showAddCollection = false
    @State private var newCollectionName = ""
    @State private var showAddItems = false
    @State private var collectionToRename: VideoCollection?
    @State private var renameText = ""
    @State private var showShortcutSheet = false
    @State private var shortcutToEdit: RoomShortcut? = nil
    @State private var isDragTargeted = false

    private var collections: [VideoCollection] {
        roomsVM.collections(for: room.id!)
    }

    private let cardColumns  = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)]
    private let thumbColumns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            // Pinned shortcuts bar — always visible at top of Room
            ShortcutBarView(
                shortcuts: shortcuts,
                onAdd: { shortcutToEdit = nil; showShortcutSheet = true },
                onEdit: { s in shortcutToEdit = s; showShortcutSheet = true },
                onDelete: { deleteShortcut($0) }
            )
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    collectionsSection
                    itemsSection
                }
                .padding(20)
            }
        }
        .navigationTitle(room.name)
        .toolbar {
            ToolbarItem {
                Button {
                    newCollectionName = ""
                    showAddCollection = true
                } label: {
                    Label("New Collection", systemImage: "folder.badge.plus")
                }
            }
            ToolbarItem {
                Button { showAddItems = true } label: {
                    Label("Add Items", systemImage: "plus")
                }
            }
        }
        .onAppear { loadItems(); loadShortcuts() }
        .onChange(of: room.id) { _, _ in loadItems(); loadShortcuts() }
        .alert("New Collection", isPresented: $showAddCollection) {
            TextField("Collection name", text: $newCollectionName)
            Button("Create") { roomsVM.addCollection(to: room.id!, name: newCollectionName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Collection", isPresented: Binding(
            get: { collectionToRename != nil },
            set: { if !$0 { collectionToRename = nil } }
        )) {
            TextField("Collection name", text: $renameText)
            Button("Rename") {
                if let col = collectionToRename { roomsVM.renameCollection(col, to: renameText) }
                collectionToRename = nil
            }
            Button("Cancel", role: .cancel) { collectionToRename = nil }
        }
        .sheet(isPresented: $showAddItems, onDismiss: loadItems) {
            AddToRoomSheet(roomId: room.id!, roomItems: roomItems, roomRepo: roomRepo)
        }
        .sheet(isPresented: $showShortcutSheet, onDismiss: loadShortcuts) {
            AddShortcutSheet(
                roomId: room.id!,
                roomRepo: roomRepo,
                editingShortcut: shortcutToEdit
            )
        }
    }

    // MARK: - Collections Section

    @ViewBuilder
    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoomSectionHeader(title: "Collections", count: collections.count)

            if collections.isEmpty {
                placeholderButton("New Collection", icon: "folder.badge.plus") {
                    newCollectionName = ""; showAddCollection = true
                }
            } else {
                LazyVGrid(columns: cardColumns, spacing: 14) {
                    ForEach(collections) { col in
                        CollectionCard(collection: col)
                            .onTapGesture { onSelectCollection(col) }
                            .contextMenu {
                                Button("Open") { onSelectCollection(col) }
                                Divider()
                                Button("Rename") { renameText = col.name; collectionToRename = col }
                                Button("Delete", role: .destructive) { roomsVM.deleteCollection(col) }
                            }
                    }
                }
            }
        }
    }

    // MARK: - Items Section

    @ViewBuilder
    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoomSectionHeader(title: "Items", count: roomItems.count)

            if roomItems.isEmpty {
                placeholderButton("Add Items", icon: "plus") { showAddItems = true }
                    .overlay(alignment: .bottom) {
                        if isDragTargeted {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentColor,
                                              style: StrokeStyle(lineWidth: 2, dash: [6]))
                                .background(Color.accentColor.opacity(0.07).cornerRadius(8))
                        }
                    }
            } else {
                ZStack(alignment: .center) {
                    LazyVGrid(columns: thumbColumns, spacing: 12) {
                        ForEach(roomItems, id: \.video.id) { info in
                            Button { selectedVideoId = info.video.id } label: {
                                VideoGridItemView(
                                    videoInfo: info,
                                    isSelected: selectedVideoId == info.video.id
                                )
                            }
                            .buttonStyle(.plain)
                            .onTapGesture(count: 2) {
                                guard info.video.status == .completed else { return }
                                NSWorkspace.shared.open(info.video.absoluteFilePath)
                            }
                            .onDrag {
                                guard info.video.status == .completed else { return NSItemProvider() }
                                return NSItemProvider(object: info.video.absoluteFilePath as NSURL)
                            }
                            .contextMenu {
                                if info.video.status == .completed {
                                    Button {
                                        NSWorkspace.shared.open(info.video.absoluteFilePath)
                                    } label: {
                                        Label("Open", systemImage: "arrow.up.forward.app")
                                    }
                                    Button {
                                        NSWorkspace.shared.selectFile(
                                            info.video.absoluteFilePath.path,
                                            inFileViewerRootedAtPath: info.video.absoluteFilePath
                                                .deletingLastPathComponent().path
                                        )
                                    } label: {
                                        Label("Show in Finder", systemImage: "folder")
                                    }
                                    Divider()
                                }
                                Button(role: .destructive) { removeItem(info) } label: {
                                    Label("Remove from Room", systemImage: "minus.circle")
                                }
                            }
                        }
                    }

                    if isDragTargeted {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.accentColor,
                                                  style: StrokeStyle(lineWidth: 2, dash: [6]))
                            )
                            .overlay {
                                VStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.title2)
                                        .foregroundStyle(Color.accentColor)
                                    Text("Drop to Add")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .onDrop(of: [.fileURL, .image, .pdf, .movie], isTargeted: $isDragTargeted) { providers, _ in
            handleDrop(providers: providers)
            return true
        }
    }

    private func placeholderButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
        .buttonStyle(.bordered)
        .foregroundStyle(.secondary)
    }

    private func loadItems() {
        roomItems = (try? roomRepo.fetchRoomItems(roomId: room.id!)) ?? []
    }

    private func loadShortcuts() {
        shortcuts = (try? roomRepo.fetchShortcuts(roomId: room.id!)) ?? []
    }

    private func deleteShortcut(_ shortcut: RoomShortcut) {
        guard let id = shortcut.id else { return }
        try? roomRepo.deleteShortcut(id: id)
        loadShortcuts()
    }

    private func removeItem(_ info: VideoInfo) {
        guard let videoId = info.video.id else { return }
        try? roomRepo.removeItemFromRoom(videoId: videoId, roomId: room.id!)
        if selectedVideoId == videoId { selectedVideoId = nil }
        loadItems()
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let roomId = room.id!
        Task {
            var fileURLs: [URL] = []
            for provider in providers {
                guard let url = await provider.loadLocalFileURL() else { continue }
                let ext = url.pathExtension.lowercased()
                guard FileImportService.videoExtensions.contains(ext)
                    || FileImportService.imageExtensions.contains(ext)
                    || FileImportService.documentExtensions.contains(ext) else { continue }
                fileURLs.append(url)
            }
            guard !fileURLs.isEmpty else { return }
            let ids = await appState.fileImportService.importFiles(fileURLs)
            for id in ids { try? roomRepo.addItemToRoom(videoId: id, roomId: roomId) }
            loadItems()
        }
    }
}

// MARK: - Section Header

struct RoomSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.headline)
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
            Spacer()
        }
    }
}

// MARK: - Collection Card

struct CollectionCard: View {
    let collection: VideoCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
                    .frame(height: 100)
                Image(systemName: "folder.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
            }

            Text(collection.name)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
        }
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Add to Room Sheet

struct AddToRoomSheet: View {
    let roomId: Int64
    let roomItems: [VideoInfo]
    let roomRepo: RoomRepository

    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var allVideos: [VideoInfo] = []
    @State private var selectedIds: Set<Int64> = []
    @State private var searchText = ""

    private var existingIds: Set<Int64> {
        Set(roomItems.compactMap { $0.video.id })
    }

    private var availableVideos: [VideoInfo] {
        allVideos.filter { info in
            guard !existingIds.contains(info.video.id ?? -1) else { return false }
            if searchText.isEmpty { return true }
            let q = searchText.lowercased()
            return info.video.title.lowercased().contains(q)
                || (info.video.uploader?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Items to Room")
                    .font(.headline)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add\(selectedIds.isEmpty ? "" : " (\(selectedIds.count))")") {
                    for id in selectedIds {
                        try? roomRepo.addItemToRoom(videoId: id, roomId: roomId)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIds.isEmpty)
            }
            .padding()

            Divider()

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search...", text: $searchText).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))

            Divider()

            List(availableVideos, id: \.video.id) { info in
                let id = info.video.id!
                let isSelected = selectedIds.contains(id)
                HStack(spacing: 10) {
                    Group {
                        if let thumbPath = info.video.absoluteThumbnailPath,
                           let img = NSImage(contentsOf: thumbPath) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle()
                                .fill(Color(.separatorColor))
                                .overlay {
                                    Image(systemName: "film").font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: 64, height: 36)
                    .cornerRadius(4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.video.title).lineLimit(1)
                        Text(info.video.uploader ?? info.video.platform.displayName)
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .font(.title3)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelected { selectedIds.remove(id) } else { selectedIds.insert(id) }
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear { allVideos = (try? appState.videoRepo.fetchAll()) ?? [] }
    }
}
