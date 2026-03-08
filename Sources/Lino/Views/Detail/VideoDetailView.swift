import SwiftUI

struct VideoDetailView: View {
    let videoInfo: VideoInfo
    var isTrashView: Bool = false
    var onTrash: (() -> Void)?
    var onRestore: (() -> Void)?
    var onPermanentDelete: (() -> Void)?
    @Environment(\.appState) private var appState
    @State private var viewModel: VideoDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                VideoDetailContent(
                    viewModel: viewModel,
                    isTrashView: isTrashView,
                    onTrash: onTrash,
                    onRestore: onRestore,
                    onPermanentDelete: onPermanentDelete
                )
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = VideoDetailViewModel(
                    videoInfo: videoInfo,
                    videoRepo: appState.videoRepo,
                    downloadService: appState.downloadService
                )
            }
        }
        .onChange(of: videoInfo.video.id) { _, _ in
            viewModel = VideoDetailViewModel(
                videoInfo: videoInfo,
                videoRepo: appState.videoRepo,
                downloadService: appState.downloadService
            )
        }
    }
}

private struct VideoDetailContent: View {
    @Bindable var viewModel: VideoDetailViewModel
    var isTrashView: Bool
    var onTrash: (() -> Void)?
    var onRestore: (() -> Void)?
    var onPermanentDelete: (() -> Void)?
    @State private var showTrashConfirmation = false
    @State private var showPermanentDeleteConfirmation = false

    private var video: Video { viewModel.videoInfo.video }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Trash banner
                if isTrashView, let deletedAt = video.deletedAt {
                    trashBanner(deletedAt: deletedAt)
                }

                // Video player
                if video.status == .completed,
                   !isTrashView,
                   FileManager.default.fileExists(atPath: video.absoluteFilePath.path) {
                    if viewModel.isRemuxing {
                        remuxingPlaceholder
                            .frame(height: 300)
                            .cornerRadius(8)
                    } else {
                        VideoPlayerView(videoURL: video.absoluteFilePath)
                            .id(viewModel.remuxToken)
                            .frame(height: 300)
                            .cornerRadius(8)
                    }
                } else {
                    // Thumbnail or placeholder
                    thumbnailView
                        .frame(height: 200)
                        .cornerRadius(8)
                }

                // Title and uploader
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)

                    if let uploader = video.uploader {
                        HStack(spacing: 4) {
                            PlatformBadgeView(platform: video.platform)
                            Text(uploader)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Tags (read-only in trash view)
                if !isTrashView {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Tags")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Button(viewModel.isEditingTags ? "Save" : "Edit") {
                                if viewModel.isEditingTags {
                                    viewModel.saveTags()
                                } else {
                                    viewModel.isEditingTags = true
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }

                        if viewModel.isEditingTags {
                            TagInputView(tags: $viewModel.editableTags)
                        } else if viewModel.videoInfo.tags.isEmpty {
                            Text("No tags")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            FlowLayout(spacing: 4) {
                                ForEach(viewModel.videoInfo.tags) { tag in
                                    TagChipView(name: tag.name)
                                }
                            }
                        }
                    }
                } else if !viewModel.videoInfo.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        FlowLayout(spacing: 4) {
                            ForEach(viewModel.videoInfo.tags) { tag in
                                TagChipView(name: tag.name)
                            }
                        }
                    }
                }

                Divider()

                // Metadata
                VStack(alignment: .leading, spacing: 8) {
                    Text("Details")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    metadataRow("Platform", value: video.platform.displayName)
                    metadataRow("Duration", value: video.formattedDuration)
                    metadataRow("File Size", value: video.formattedFileSize)
                    if let width = video.width, let height = video.height {
                        metadataRow("Resolution", value: "\(width) x \(height)")
                    }
                    if let uploadDate = video.uploadDate {
                        if let date = DateFormatters.parseYtDlpDate(uploadDate) {
                            metadataRow("Upload Date", value: DateFormatters.displayDate(date))
                        }
                    }
                    metadataRow("Added", value: DateFormatters.displayDate(video.addedAt))
                    metadataRow("Status", value: video.status.rawValue.capitalized)

                    if let error = video.errorMessage {
                        metadataRow("Error", value: error, valueColor: .red)
                    }
                }

                if let description = video.description, !description.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(10)
                    }
                }

                Divider()

                // Actions
                if isTrashView {
                    trashActions
                } else {
                    libraryActions
                }
            }
            .padding(16)
        }
        .alert("Move to Trash", isPresented: $showTrashConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                onTrash?()
            }
        } message: {
            Text("This video will be moved to the trash. You can restore it within 7 days.")
        }
        .alert("Delete Permanently", isPresented: $showPermanentDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) {
                onPermanentDelete?()
            }
        } message: {
            Text("This will permanently delete the video file and all associated data. This cannot be undone.")
        }
    }

    private var libraryActions: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.openOriginalURL()
            } label: {
                Label("Open URL", systemImage: "safari")
            }

            if video.status == .completed {
                Button {
                    viewModel.revealInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }

            if video.status == .failed {
                Button {
                    Task { await viewModel.retryDownload() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }

            Spacer()

            Button(role: .destructive) {
                showTrashConfirmation = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }

    private var trashActions: some View {
        HStack(spacing: 12) {
            Button {
                onRestore?()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.accentColor)

            Spacer()

            Button(role: .destructive) {
                showPermanentDeleteConfirmation = true
            } label: {
                Label("Delete Permanently", systemImage: "trash.slash")
            }
        }
    }

    private func trashBanner(deletedAt: Date) -> some View {
        let daysLeft = max(0, 7 - Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day!)
        return HStack(spacing: 8) {
            Image(systemName: "trash")
                .foregroundStyle(.orange)
            Text("In trash \u{2022} \(daysLeft) day\(daysLeft == 1 ? "" : "s") until permanent deletion")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private var remuxingPlaceholder: some View {
        Rectangle()
            .fill(Color(.controlBackgroundColor))
            .overlay {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Preparing video for playback\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbPath = video.absoluteThumbnailPath,
           let image = NSImage(contentsOf: thumbPath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(Color(.separatorColor))
                .overlay {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func metadataRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
        }
    }
}
