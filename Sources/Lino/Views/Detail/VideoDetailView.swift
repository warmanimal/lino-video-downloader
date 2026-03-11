import SwiftUI
import PDFKit

struct VideoDetailView: View {
    let videoInfo: VideoInfo
    var isTrashView: Bool = false
    var onTrash: (() -> Void)?
    var onRestore: (() -> Void)?
    var onPermanentDelete: (() -> Void)?
    var onVideoUpdated: (() -> Void)?
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
                let vm = VideoDetailViewModel(
                    videoInfo: videoInfo,
                    videoRepo: appState.videoRepo,
                    downloadService: appState.downloadService,
                    metadataService: appState.metadataService
                )
                vm.onVideoUpdated = onVideoUpdated
                viewModel = vm
            }
        }
        .onChange(of: videoInfo.video.id) { _, _ in
            let vm = VideoDetailViewModel(
                videoInfo: videoInfo,
                videoRepo: appState.videoRepo,
                downloadService: appState.downloadService,
                metadataService: appState.metadataService
            )
            vm.onVideoUpdated = onVideoUpdated
            viewModel = vm
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
    @State private var panelHeight: CGFloat = 500
    @State private var isDropTargeted = false

    private var video: Video { viewModel.videoInfo.video }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Trash banner
                if isTrashView, let deletedAt = video.deletedAt {
                    trashBanner(deletedAt: deletedAt)
                }

                // Image or video player — also a drop target for manual video attachment
                previewArea
                    .dropDestination(for: URL.self) { urls, _ in
                        guard !isTrashView, !video.isImage, !video.isPDF, !video.isTextOnly,
                              let url = urls.first, url.isFileURL else { return false }
                        let ext = url.pathExtension.lowercased()
                        guard FileImportService.videoExtensions.contains(ext) else { return false }
                        Task { await viewModel.attachDroppedFile(url: url) }
                        return true
                    } isTargeted: { targeted in
                        guard !isTrashView && !video.isImage && !video.isPDF else { return }
                        isDropTargeted = targeted
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

                // Notes — always shown, editable
                if !isTrashView {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Notes")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Button(viewModel.isEditingNotes ? "Save" : "Edit") {
                                if viewModel.isEditingNotes {
                                    viewModel.saveNotes()
                                } else {
                                    viewModel.editableNotes = viewModel.videoInfo.video.notes ?? ""
                                    viewModel.isEditingNotes = true
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }

                        if viewModel.isEditingNotes {
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $viewModel.editableNotes)
                                    .font(.body)
                                    .frame(minHeight: 80, maxHeight: 200)
                                    .scrollContentBackground(.hidden)
                                    .padding(4)

                                if viewModel.editableNotes.isEmpty {
                                    Text("Add a note…")
                                        .font(.body)
                                        .foregroundStyle(.tertiary)
                                        .allowsHitTesting(false)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 12)
                                }
                            }
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                            )
                        } else if let notes = video.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        } else {
                            Text("No notes")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else if let notes = video.notes, !notes.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
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
        .background(GeometryReader { geo in
            Color.clear.onAppear { panelHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, h in panelHeight = h }
        })
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

    private var isPortrait: Bool {
        guard let w = video.width, let h = video.height, w > 0 else { return false }
        return h > w
    }

    @ViewBuilder
    private func wrappedPlayer(url: URL) -> some View {
        if isPortrait, let w = video.width, let h = video.height {
            VideoPlayerView(videoURL: url)
                .aspectRatio(CGFloat(w) / CGFloat(h), contentMode: .fit)
                .frame(maxHeight: panelHeight * 0.85)
                .cornerRadius(8)
        } else {
            VideoPlayerView(videoURL: url)
                .frame(height: 300)
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            // Main content
            if video.isTextOnly {
                if video.platform == .twitter { tweetCard } else { articleCard }
            } else if video.isImage {
                fullImageView(maxHeight: panelHeight * 0.85)
            } else if video.isPDF && video.status == .completed {
                PDFPreviewView(url: video.absoluteFilePath)
                    .frame(height: min(panelHeight * 0.65, 480))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            } else if video.status == .completed {
                wrappedPlayer(url: video.absoluteFilePath)
            } else {
                streamablePreview
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(8)
            }

            // Drop-hover overlay
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Color.accentColor.opacity(0.1).cornerRadius(8))
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                                .font(.title)
                                .foregroundStyle(Color.accentColor)
                            Text("Drop video to attach")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
            }

            // Attaching overlay
            if viewModel.isAttaching {
                Color.black.opacity(0.5)
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Attaching…")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var libraryActions: some View {
        HStack(spacing: 12) {
            // "Open URL" only makes sense for remote sources (not local files)
            if !(video.isPDF || video.isImage) {
                Button {
                    viewModel.openOriginalURL()
                } label: {
                    Label("Open URL", systemImage: "safari")
                }
            }

            // "Open" and "Show in Finder" only make sense when there's a local file
            if video.status == .completed && !video.isTextOnly {
                Button {
                    viewModel.openFile()
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                Button {
                    viewModel.revealInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }

            if video.status == .saved {
                Button {
                    Task { await viewModel.downloadVideo() }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
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

    /// Thumbnail with a play-to-stream overlay for saved videos, plain thumbnail otherwise.
    @ViewBuilder
    private var streamablePreview: some View {
        ZStack {
            thumbnailView

            if video.status == .saved, !isTrashView {
                if viewModel.isLoadingStream {
                    Color.black.opacity(0.35)
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else if let error = viewModel.streamError {
                    Color.black.opacity(0.35)
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                        Button("Try Again") {
                            Task {
                                viewModel.streamError = nil
                                await viewModel.loadStreamURL()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else {
                    Button {
                        Task { await viewModel.loadStreamURL() }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func fullImageView(maxHeight: CGFloat) -> some View {
        let nsImage = NSImage(contentsOf: video.absoluteFilePath)
            ?? (try? Data(contentsOf: video.absoluteFilePath)).flatMap { NSImage(data: $0) }
        if let image = nsImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: maxHeight)
                .cornerRadius(8)
        } else {
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(height: 200)
                .cornerRadius(8)
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
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

    /// Card shown for saved web articles (Open Graph bookmark, no local file).
    @ViewBuilder
    private var articleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Site name + open button
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(video.uploader ?? (URL(string: video.originalUrl)?.host ?? "Article"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.openOriginalURL()
                } label: {
                    Label("Open Article", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Divider()

            // og:image thumbnail
            if let thumbPath = video.absoluteThumbnailPath,
               let img = NSImage(contentsOf: thumbPath) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .clipped()
                    .cornerRadius(8)
            }

            // Title
            Text(video.title)
                .font(.headline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            // Description
            if let desc = video.description, !desc.isEmpty {
                Text(desc)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    /// Styled card shown for text-only tweets (no downloadable media).
    @ViewBuilder
    private var tweetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(Color(red: 0.11, green: 0.63, blue: 0.95))
                Text(video.uploader ?? "X / Twitter")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    viewModel.openOriginalURL()
                } label: {
                    Image(systemName: "arrow.up.right.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open tweet in browser")
            }

            Divider()

            // Tweet body
            Text(video.description ?? video.title)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
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
