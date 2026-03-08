import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.lino.app", category: "LibraryView")

struct LibraryView: View {
    @Environment(\.appState) private var appState
    @State private var viewModel: LibraryViewModel?

    var body: some View {
        Group {
            if let viewModel {
                LibraryContentView(viewModel: viewModel)
                    .environment(\.appState, appState)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = LibraryViewModel(videoRepo: appState.videoRepo)
                vm.loadVideos()
                vm.purgeExpiredTrash()
                viewModel = vm
            }
        }
        .onChange(of: appState.downloadService.changeToken) { old, new in
            logger.notice("[LibraryView] changeToken \(old) -> \(new), reloading videos")
            viewModel?.loadVideos()
        }
    }
}

private struct LibraryContentView: View {
    @Bindable var viewModel: LibraryViewModel
    @Environment(\.appState) private var appState

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if viewModel.showingTrash {
                    trashHeader
                } else {
                    // Filter bar
                    FilterBarView(
                        searchText: $viewModel.searchText,
                        selectedPlatform: $viewModel.selectedPlatform,
                        selectedTagIds: $viewModel.selectedTagIds,
                        sortBy: $viewModel.sortBy
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .onChange(of: viewModel.searchText) { _, _ in viewModel.loadVideos() }
                    .onChange(of: viewModel.selectedPlatform) { _, _ in viewModel.loadVideos() }
                    .onChange(of: viewModel.selectedTagIds) { _, _ in viewModel.loadVideos() }
                    .onChange(of: viewModel.sortBy) { _, _ in viewModel.loadVideos() }
                }

                Divider()

                // Content
                let displayedVideos = viewModel.showingTrash ? viewModel.trashedVideos : viewModel.videos

                if displayedVideos.isEmpty {
                    if viewModel.showingTrash {
                        trashEmptyState
                    } else {
                        EmptyStateView()
                    }
                } else if viewModel.isGridView {
                    VideoGridView(
                        videos: displayedVideos,
                        selectedVideoId: $viewModel.selectedVideoId
                    )
                } else {
                    VideoListView(
                        videos: displayedVideos,
                        selectedVideoId: $viewModel.selectedVideoId
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 4) {
                        Button {
                            viewModel.isGridView = true
                        } label: {
                            Image(systemName: "square.grid.2x2")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(viewModel.isGridView ? .primary : .secondary)

                        Button {
                            viewModel.isGridView = false
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(!viewModel.isGridView ? .primary : .secondary)
                    }
                }

                ToolbarItem(placement: .automatic) {
                    SearchField(text: $viewModel.searchText)
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        viewModel.showingTrash.toggle()
                        viewModel.selectedVideoId = nil
                        if viewModel.showingTrash {
                            viewModel.loadTrashedVideos()
                        } else {
                            viewModel.loadVideos()
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: viewModel.showingTrash ? "trash.fill" : "trash")
                            if viewModel.trashedCount > 0 && !viewModel.showingTrash {
                                Text("\(viewModel.trashedCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 3)
                                    .background(Color.red, in: Capsule())
                                    .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .help(viewModel.showingTrash ? "Back to library" : "Trash")
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        if viewModel.showingTrash {
                            viewModel.loadTrashedVideos()
                        } else {
                            viewModel.loadVideos()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
            }
            .frame(minWidth: 400)
        } detail: {
            if let videoInfo = viewModel.selectedVideoInfo {
                let _ = logger.notice("[LibraryView] showing detail for id=\(videoInfo.video.id ?? -1)")
                VideoDetailView(
                    videoInfo: videoInfo,
                    isTrashView: viewModel.showingTrash,
                    onTrash: {
                        viewModel.trashVideo(videoInfo.video)
                    },
                    onRestore: {
                        viewModel.restoreVideo(id: videoInfo.video.id!)
                    },
                    onPermanentDelete: {
                        viewModel.permanentlyDeleteVideo(videoInfo.video)
                    }
                )
                .id(videoInfo.video.id)
                .environment(\.appState, appState)
            } else {
                Text(viewModel.showingTrash ? "Select a trashed video" : "Select a video")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel.showingTrash ? "Trash" : "Lino")
    }

    private var trashHeader: some View {
        HStack {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text("Trash")
                .font(.headline)
            Spacer()
            if !viewModel.trashedVideos.isEmpty {
                Button("Empty Trash") {
                    viewModel.emptyTrash()
                }
                .foregroundStyle(.red)
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var trashEmptyState: some View {
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
