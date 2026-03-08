import SwiftUI

struct VideoGridItemView: View {
    let videoInfo: VideoInfo
    let isSelected: Bool

    private var video: Video { videoInfo.video }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack(alignment: .topLeading) {
                thumbnailView
                    .frame(height: 140)
                    .clipped()

                // Platform badge
                PlatformBadgeView(platform: video.platform, size: 14)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(4)
                    .padding(6)

                // Duration badge
                if video.duration != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(video.formattedDuration)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7))
                                .cornerRadius(3)
                                .padding(6)
                        }
                    }
                }

                // Status overlay for non-completed
                if video.status != .completed {
                    statusOverlay
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let uploader = video.uploader {
                    Text(uploader)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !videoInfo.tags.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(videoInfo.tags.prefix(3)) { tag in
                            TagChipView(name: tag.name)
                        }
                        if videoInfo.tags.count > 3 {
                            Text("+\(videoInfo.tags.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    }

    @ViewBuilder
    private var thumbnailView: some View {
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
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)

            switch video.status {
            case .pending:
                Label("Queued", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.white)
            case .downloading:
                VStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading...")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            case .failed:
                Label("Failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            case .completed:
                EmptyView()
            }
        }
    }
}
