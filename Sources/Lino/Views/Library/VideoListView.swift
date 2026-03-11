import SwiftUI
import AppKit

struct VideoListView: View {
    let videos: [VideoInfo]
    @Binding var selectedVideoId: Int64?

    var body: some View {
        List(selection: $selectedVideoId) {
            ForEach(videos) { videoInfo in
                VideoListRowView(videoInfo: videoInfo)
                    .tag(videoInfo.video.id)
                    .onTapGesture(count: 2) {
                        guard videoInfo.video.status == .completed,
                              !videoInfo.video.isTextOnly else { return }
                        NSWorkspace.shared.open(videoInfo.video.absoluteFilePath)
                    }
                    .onDrag {
                        guard videoInfo.video.status == .completed,
                              !videoInfo.video.isTextOnly else { return NSItemProvider() }
                        return NSItemProvider(object: videoInfo.video.absoluteFilePath as NSURL)
                    }
                    .contextMenu {
                        if videoInfo.video.status == .completed && !videoInfo.video.isTextOnly {
                            Button {
                                NSWorkspace.shared.open(videoInfo.video.absoluteFilePath)
                            } label: {
                                Label("Open", systemImage: "arrow.up.forward.app")
                            }
                            Button {
                                NSWorkspace.shared.selectFile(
                                    videoInfo.video.absoluteFilePath.path,
                                    inFileViewerRootedAtPath: videoInfo.video.absoluteFilePath
                                        .deletingLastPathComponent().path
                                )
                            } label: {
                                Label("Show in Finder", systemImage: "folder")
                            }
                            Divider()
                        }
                        let originalUrl = videoInfo.video.originalUrl
                        if originalUrl.hasPrefix("http") {
                            Button {
                                if let url = URL(string: originalUrl) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Label("Open Source URL", systemImage: "safari")
                            }
                        }
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

struct VideoListRowView: View {
    let videoInfo: VideoInfo

    private var video: Video { videoInfo.video }

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail
            thumbnailCell
                .frame(width: 64, height: 36)
                .cornerRadius(3)

            // Title + uploader
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.body)
                    .lineLimit(1)
                if let uploader = video.uploader {
                    Text(uploader)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer()

            // Platform / type indicator
            if video.isPDF {
                Text("PDF")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(3)
                    .frame(width: 70, alignment: .leading)
            } else if video.isImage {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.caption2)
                    Text("Image")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            } else if video.isTextOnly {
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.caption2)
                    Text("Post")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            } else {
                HStack(spacing: 4) {
                    PlatformBadgeView(platform: video.platform, size: 10)
                    Text(video.platform.displayName)
                        .font(.caption)
                }
                .frame(width: 70, alignment: .leading)
            }

            // Tags
            if !videoInfo.tags.isEmpty {
                HStack(spacing: 3) {
                    ForEach(videoInfo.tags.prefix(2)) { tag in
                        TagChipView(name: tag.name)
                    }
                    if videoInfo.tags.count > 2 {
                        Text("+\(videoInfo.tags.count - 2)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, alignment: .leading)
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 120, alignment: .leading)
            }

            // Duration
            Text(video.formattedDuration)
                .font(.caption)
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)

            // Added
            Text(DateFormatters.relativeDate(video.addedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Size
            Text(video.formattedFileSize)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .trailing)

            // Status
            statusBadge(for: video.status)
                .frame(width: 70, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnailCell: some View {
        if video.isTextOnly {
            Rectangle()
                .fill(Color(.controlBackgroundColor))
                .overlay(alignment: .topLeading) {
                    Text(video.description ?? video.title)
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(4)
                }
        } else if let thumbPath = video.absoluteThumbnailPath,
                  let image = NSImage(contentsOf: thumbPath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color(.separatorColor))
                .overlay {
                    let icon = video.isPDF ? "doc.richtext" : (video.isImage ? "photo" : "film")
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private func statusBadge(for status: Video.DownloadStatus) -> some View {
        switch status {
        case .saved:
            Label("Saved", systemImage: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(.purple)
        case .completed:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .downloading:
            Label("Downloading", systemImage: "arrow.down.circle.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .pending:
            Label("Queued", systemImage: "clock.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}
