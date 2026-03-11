import SwiftUI

struct LibraryView: View {
    @Environment(\.appState) private var appState
    @State private var libraryVM: LibraryViewModel?
    @State private var roomsVM: RoomsViewModel?

    var body: some View {
        Group {
            if let libraryVM, let roomsVM {
                LibraryContentView(libraryVM: libraryVM, roomsVM: roomsVM)
                    .environment(\.appState, appState)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if libraryVM == nil {
                let vm = LibraryViewModel(videoRepo: appState.videoRepo)
                vm.loadVideos()
                vm.purgeExpiredTrash()
                libraryVM = vm
            }
            if roomsVM == nil {
                let vm = RoomsViewModel(roomRepo: appState.roomRepo)
                vm.load()
                roomsVM = vm
            }
        }
        .onChange(of: appState.downloadService.changeToken) { _, _ in
            libraryVM?.loadVideos()
        }
    }
}

// MARK: - Main Content

private struct LibraryContentView: View {
    @Bindable var libraryVM: LibraryViewModel
    @Bindable var roomsVM: RoomsViewModel
    @Environment(\.appState) private var appState

    @State private var sidebarSelection: LibrarySelection? = .allItems

    private var selectedVideoInfo: VideoInfo? {
        libraryVM.selectedVideoInfo
    }

    var body: some View {
        // 2-column split: sidebar stays visible; detail area hosts content + optional inspector
        NavigationSplitView {
            LibrarySidebarView(
                selection: $sidebarSelection,
                roomsVM: roomsVM,
                trashedCount: libraryVM.trashedCount
            )
            .frame(minWidth: 180)
        } detail: {
            HStack(spacing: 0) {
                contentPane
                    .frame(minWidth: 360)

                if let videoInfo = selectedVideoInfo {
                    Divider()
                    detailPanel(for: videoInfo)
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 400)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: libraryVM.selectedVideoId)
        }
        .onChange(of: sidebarSelection) { _, newValue in
            let isTrash = (newValue == .trash)
            if libraryVM.showingTrash != isTrash {
                libraryVM.showingTrash = isTrash
                if isTrash {
                    libraryVM.loadTrashedVideos()
                } else {
                    libraryVM.loadVideos()
                }
            }
            libraryVM.selectedVideoId = nil
        }
    }

    private func detailPanel(for videoInfo: VideoInfo) -> some View {
        let isTrash = (sidebarSelection == .trash)
        return VideoDetailView(
            videoInfo: videoInfo,
            isTrashView: isTrash,
            onTrash: { libraryVM.trashVideo(videoInfo.video) },
            onRestore: { libraryVM.restoreVideo(id: videoInfo.video.id!) },
            onPermanentDelete: { libraryVM.permanentlyDeleteVideo(videoInfo.video) },
            onVideoUpdated: { libraryVM.loadVideos() }
        )
        .id(videoInfo.video.id)
        .environment(\.appState, appState)
    }

    // MARK: - Content Pane

    @ViewBuilder
    private var contentPane: some View {
        switch sidebarSelection {
        case .allItems, nil:
            AllItemsView(libraryVM: libraryVM)
                .environment(\.appState, appState)
        case .room(let roomId):
            if let room = roomsVM.rooms.first(where: { $0.id == roomId }) {
                RoomView(
                    room: room,
                    roomsVM: roomsVM,
                    roomRepo: appState.roomRepo,
                    selectedVideoId: $libraryVM.selectedVideoId,
                    onSelectCollection: { col in
                        sidebarSelection = .collection(col.id!)
                    }
                )
                .environment(\.appState, appState)
            }
        case .collection(let collectionId):
            let parentRoom = roomsVM.room(forCollectionId: collectionId)
            CollectionView(
                collectionId: collectionId,
                roomRepo: appState.roomRepo,
                selectedVideoId: $libraryVM.selectedVideoId,
                parentRoom: parentRoom,
                onNavigateBack: parentRoom.map { room in
                    { sidebarSelection = .room(room.id!) }
                }
            )
            .environment(\.appState, appState)
        case .trash:
            TrashView(libraryVM: libraryVM)
                .environment(\.appState, appState)
        }
    }
}

// MARK: - All Items View

private struct AllItemsView: View {
    @Bindable var libraryVM: LibraryViewModel
    @Environment(\.appState) private var appState
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                searchText: $libraryVM.searchText,
                selectedPlatform: $libraryVM.selectedPlatform,
                selectedTagIds: $libraryVM.selectedTagIds,
                sortBy: $libraryVM.sortBy
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onChange(of: libraryVM.searchText) { _, _ in libraryVM.loadVideos() }
            .onChange(of: libraryVM.selectedPlatform) { _, _ in libraryVM.loadVideos() }
            .onChange(of: libraryVM.selectedTagIds) { _, _ in libraryVM.loadVideos() }
            .onChange(of: libraryVM.sortBy) { _, _ in libraryVM.loadVideos() }

            Divider()

            if libraryVM.videos.isEmpty {
                EmptyStateView()
            } else if libraryVM.isGridView {
                VideoGridView(videos: libraryVM.videos, selectedVideoId: $libraryVM.selectedVideoId)
            } else {
                VideoListView(videos: libraryVM.videos, selectedVideoId: $libraryVM.selectedVideoId)
            }
        }
        .overlay {
            if isDragTargeted { dropOverlay }
        }
        .onDrop(of: [.fileURL, .image, .pdf, .movie, .url], isTargeted: $isDragTargeted) { providers, _ in
            handleDrop(providers: providers)
            return true
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 4) {
                    Button { libraryVM.isGridView = true } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(libraryVM.isGridView ? .primary : .secondary)

                    Button { libraryVM.isGridView = false } label: {
                        Image(systemName: "list.bullet")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(!libraryVM.isGridView ? .primary : .secondary)
                }
            }

            ToolbarItem(placement: .automatic) {
                SearchField(text: $libraryVM.searchText)
            }

            ToolbarItem(placement: .automatic) {
                Button { libraryVM.loadVideos() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .navigationTitle("All Items")
    }

    private func handleDrop(providers: [NSItemProvider]) {
        Task {
            var fileURLs: [URL] = []
            for provider in providers {
                // Web URL → enqueue download
                if let webURL = await provider.loadWebURL() {
                    appState.downloadService.enqueueDownload(url: webURL.absoluteString, tags: [])
                    continue
                }
                // Local file or Photos image → import
                guard let url = await provider.loadLocalFileURL() else { continue }
                let ext = url.pathExtension.lowercased()
                if FileImportService.videoExtensions.contains(ext)
                    || FileImportService.imageExtensions.contains(ext)
                    || FileImportService.documentExtensions.contains(ext) {
                    fileURLs.append(url)
                }
            }
            if !fileURLs.isEmpty {
                _ = await appState.fileImportService.importFiles(fileURLs)
                libraryVM.loadVideos()
            }
        }
    }

    private var dropOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.07)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text("Drop to Import")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Text("Videos, images, PDFs, or URLs")
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

// MARK: - Trash View

private struct TrashView: View {
    @Bindable var libraryVM: LibraryViewModel
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                Text("Trash")
                    .font(.headline)
                Spacer()
                if !libraryVM.trashedVideos.isEmpty {
                    Button("Empty Trash") { libraryVM.emptyTrash() }
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if libraryVM.trashedVideos.isEmpty {
                trashEmpty
            } else {
                VideoGridView(
                    videos: libraryVM.trashedVideos,
                    selectedVideoId: $libraryVM.selectedVideoId
                )
            }
        }
        .navigationTitle("Trash")
        .onAppear { libraryVM.loadTrashedVideos() }
    }

    private var trashEmpty: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "trash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Trash is empty")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Deleted videos will appear here for 7 days before being permanently removed.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Search Field

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search...", text: $text)
                .textFieldStyle(.plain)
                .frame(width: 150)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}
