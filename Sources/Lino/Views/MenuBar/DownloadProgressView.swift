import SwiftUI

struct DownloadProgressView: View {
    let downloads: [DownloadTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Downloads")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ForEach(downloads) { task in
                DownloadItemView(task: task)
            }
        }
    }
}

private struct DownloadItemView: View {
    @Bindable var task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                PlatformBadgeView(platform: task.platform, size: 10)
                Text(task.url)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            HStack(spacing: 8) {
                ProgressView(value: task.progress.percent, total: 100)
                    .progressViewStyle(.linear)

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            if let speed = task.progress.speed, let eta = task.progress.eta {
                HStack {
                    Text(speed)
                    Spacer()
                    Text("ETA: \(eta)")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }

    private var statusText: String {
        switch task.progress.phase {
        case .downloading:
            return "\(Int(task.progress.percent))%"
        case .postProcessing:
            return "Processing"
        case .remuxing:
            return "Remuxing"
        }
    }
}
