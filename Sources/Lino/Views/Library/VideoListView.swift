import SwiftUI

struct VideoListView: View {
    let videos: [VideoInfo]
    @Binding var selectedVideoId: Int64?

    var body: some View {
        List(selection: $selectedVideoId) {
            ForEach(videos) { videoInfo in
                VideoListRowView(videoInfo: videoInfo)
                    .tag(videoInfo.video.id)
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

            // Platform
            HStack(spacing: 4) {
                PlatformBadgeView(platform: video.platform, size: 10)
                Text(video.platform.displayName)
                    .font(.caption)
            }
            .frame(width: 70, alignment: .leading)

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
        if let thumbPath = video.absoluteThumbnailPath,
           let image = NSImage(contentsOf: thumbPath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color(.separatorColor))
                .overlay {
                    Image(systemName: "film")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private func statusBadge(for status: Video.DownloadStatus) -> some View {
        switch status {
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
