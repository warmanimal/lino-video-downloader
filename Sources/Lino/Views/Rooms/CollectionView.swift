import SwiftUI
import AppKit

struct CollectionView: View {
    let collectionId: Int64
    let roomRepo: RoomRepository
    @Binding var selectedVideoId: Int64?
    var parentRoom: Room? = nil
    var onNavigateBack: (() -> Void)? = nil

    @Environment(\.appState) private var appState
    @State private var videos: [VideoInfo] = []
    @State private var collection: VideoCollection?
    @State private var showAddItems = false
    @State private var isDragTargeted = false
    @AppStorage("collection.isGridView") private var isGridView = true

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)]

    var body: some View {
        Group {
            if videos.isEmpty {
                emptyState
            } else if isGridView {
                gridContent
            } else {
                listContent
            }
        }
        .overlay {
            if isDragTargeted { dropOverlay }
        }
        .onDrop(of: [.fileURL, .image, .pdf, .movie], isTargeted: $isDragTargeted) { providers, _ in
            handleDrop(providers: providers)
            return true
        }
        .navigationTitle(collection?.name ?? "Collection")
        .toolbar {
            if let room = parentRoom, let back = onNavigateBack {
                ToolbarItem(placement: .navigation) {
                    Button(action: back) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .fontWeight(.medium)
                            Text(room.name)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.borderless)
                    .help("Back to \(room.name)")
                }
            }

            ToolbarItem(placement: .automatic) {
                HStack(spacing: 4) {
                    Button { isGridView = true } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isGridView ? .primary : .secondary)
                    .help("Grid view")

                    Button { isGridView = false } label: {
                        Image(systemName: "list.bullet")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(!isGridView ? .primary : .secondary)
                    .help("List view")
                }
            }

            ToolbarItem {
                Button {
                    showAddItems = true
                } label: {
                    Label("Add Items", systemImage: "plus")
                }
            }
        }
        .onAppear { loadData() }
        .onChange(of: collectionId) { _, _ in loadData() }
        .sheet(isPresented: $showAddItems, onDismiss: loadData) {
            AddToCollectionSheet(
                collectionId: collectionId,
                collectionVideos: videos,
                roomRepo: roomRepo
            )
        }
    }

    // MARK: - Grid

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(videos, id: \.video.id) { info in
                    Button {
                        selectedVideoId = info.video.id
                    } label: {
                        VideoGridItemView(
                            videoInfo: info,
                            isSelected: selectedVideoId == info.video.id
                        )
                        .contentShape(Rectangle())
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
                    .contextMenu { itemContextMenu(for: info) }
                }
            }
            .padding(12)
        }
    }

    // MARK: - List

    private var listContent: some View {
        List(selection: $selectedVideoId) {
            ForEach(videos, id: \.video.id) { info in
                VideoListRowView(videoInfo: info)
                    .tag(info.video.id)
                    .onTapGesture(count: 2) {
                        guard info.video.status == .completed else { return }
                        NSWorkspace.shared.open(info.video.absoluteFilePath)
                    }
                    .onDrag {
                        guard info.video.status == .completed else { return NSItemProvider() }
                        return NSItemProvider(object: info.video.absoluteFilePath as NSURL)
                    }
                    .contextMenu { itemContextMenu(for: info) }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Shared context menu

    @ViewBuilder
    private func itemContextMenu(for info: VideoInfo) -> some View {
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
        let originalUrl = info.video.originalUrl
        if originalUrl.hasPrefix("http") {
            Button {
                if let url = URL(string: originalUrl) { NSWorkspace.shared.open(url) }
            } label: {
                Label("Open Source URL", systemImage: "safari")
            }
            Divider()
        }
        Button(role: .destructive) {
            removeItem(info)
        } label: {
            Label("Remove from Collection", systemImage: "minus.circle")
        }
    }

    // MARK: - Helpers

    private func loadData() {
        collection = try? roomRepo.fetchCollection(id: collectionId)
        videos = (try? roomRepo.fetchItems(collectionId: collectionId)) ?? []
        if let id = selectedVideoId, !videos.contains(where: { $0.video.id == id }) {
            selectedVideoId = nil
        }
    }

    private func removeItem(_ info: VideoInfo) {
        guard let videoId = info.video.id else { return }
        try? roomRepo.removeItem(videoId: videoId, collectionId: collectionId)
        if selectedVideoId == videoId { selectedVideoId = nil }
        loadData()
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let colId = collectionId
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
            for id in ids { try? roomRepo.addItem(videoId: id, collectionId: colId) }
            loadData()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Items")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Add items from your library, or drop files here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Add Items") { showAddItems = true }
                .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.07)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text("Drop to Add")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Text("Videos, images, or PDFs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Add to Collection Sheet

struct AddToCollectionSheet: View {
    let collectionId: Int64
    let collectionVideos: [VideoInfo]
    let roomRepo: RoomRepository

    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var allVideos: [VideoInfo] = []
    @State private var selectedIds: Set<Int64> = []
    @State private var searchText = ""

    private var existingIds: Set<Int64> {
        Set(collectionVideos.compactMap { $0.video.id })
    }

    private var filteredVideos: [VideoInfo] {
        guard !searchText.isEmpty else { return allVideos }
        let q = searchText.lowercased()
        return allVideos.filter { info in
            info.video.title.lowercased().contains(q)
                || (info.video.uploader?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Collection")
                    .font(.headline)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Done") {
                    // Add newly checked items
                    for id in selectedIds.subtracting(existingIds) {
                        try? roomRepo.addItem(videoId: id, collectionId: collectionId)
                    }
                    // Remove unchecked items that were previously in the collection
                    for id in existingIds.subtracting(selectedIds) {
                        try? roomRepo.removeItem(videoId: id, collectionId: collectionId)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))

            Divider()

            // List — all library items; pre-checked if already in collection
            List(filteredVideos, id: \.video.id) { info in
                let id = info.video.id!
                let isSelected = selectedIds.contains(id)
                HStack(spacing: 10) {
                    Group {
                        if info.video.isTextOnly {
                            Rectangle()
                                .fill(Color(.controlBackgroundColor))
                                .overlay(alignment: .topLeading) {
                                    Text(info.video.description ?? info.video.title)
                                        .font(.system(size: 7))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                        .padding(3)
                                }
                        } else if let thumbPath = info.video.absoluteThumbnailPath,
                                  let img = NSImage(contentsOf: thumbPath) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle()
                                .fill(Color(.separatorColor))
                                .overlay {
                                    let icon = info.video.isPDF ? "doc.richtext"
                                        : (info.video.isImage ? "photo" : "film")
                                    Image(systemName: icon)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: 64, height: 36)
                    .cornerRadius(4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.video.title)
                            .lineLimit(1)
                        Text(info.video.uploader ?? info.video.platform.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        .onAppear {
            allVideos = (try? appState.videoRepo.fetchAll()) ?? []
            // Pre-select items already in the collection
            selectedIds = existingIds
        }
    }
}
