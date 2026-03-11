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
                    .frame(maxWidth: .infinity, minHeight: 140)

                // Platform badge (top-left) — hidden for local PDFs/images
                if !video.isPDF && !video.isImage {
                    PlatformBadgeView(platform: video.platform, size: 14)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(4)
                        .padding(6)
                }

                // PDF badge (top-right)
                if video.isPDF {
                    HStack {
                        Spacer()
                        Text("PDF")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(3)
                            .padding(6)
                    }
                }

                // Duration badge (bottom-right) — videos only
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
            .frame(height: 140)
            .clipped()

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
        if video.isTextOnly {
            // Text-only tweet: show a snippet of the tweet body
            Rectangle()
                .fill(Color(.controlBackgroundColor))
                .overlay(alignment: .topLeading) {
                    Text(video.description ?? video.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .padding(8)
                }
        } else if let thumbPath = video.absoluteThumbnailPath,
                  let image = NSImage(contentsOf: thumbPath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            let icon = video.isPDF ? "doc.richtext" : (video.isImage ? "photo" : "film")
            Rectangle()
                .fill(Color(.separatorColor))
                .overlay {
                    Image(systemName: icon)
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
            case .saved:
                Label("Saved", systemImage: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
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
