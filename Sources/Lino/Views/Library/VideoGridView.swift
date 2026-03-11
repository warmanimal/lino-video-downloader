import SwiftUI
import AppKit

struct VideoGridView: View {
    let videos: [VideoInfo]
    @Binding var selectedVideoId: Int64?

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(videos, id: \.video.id) { videoInfo in
                    Button {
                        selectedVideoId = videoInfo.video.id
                    } label: {
                        VideoGridItemView(videoInfo: videoInfo, isSelected: selectedVideoId == videoInfo.video.id)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onTapGesture(count: 2) {
                        guard videoInfo.video.status == .completed else { return }
                        NSWorkspace.shared.open(videoInfo.video.absoluteFilePath)
                    }
                    .onDrag {
                        guard videoInfo.video.status == .completed else { return NSItemProvider() }
                        return NSItemProvider(object: videoInfo.video.absoluteFilePath as NSURL)
                    }
                    .contextMenu {
                        gridContextMenu(for: videoInfo)
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func gridContextMenu(for info: VideoInfo) -> some View {
        if info.video.status == .completed {
            Button("Open") {
                NSWorkspace.shared.open(info.video.absoluteFilePath)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([info.video.absoluteFilePath])
            }
            Divider()
        }
        if !info.video.isImage && !info.video.isPDF,
           let url = URL(string: info.video.originalUrl),
           url.scheme?.hasPrefix("http") == true {
            Button("Open Source URL") {
                NSWorkspace.shared.open(url)
            }
            Divider()
        }
    }
}
