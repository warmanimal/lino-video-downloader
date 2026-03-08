import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.lino.app", category: "GridView")

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
                        logger.notice("[GridView] TAP on id=\(videoInfo.video.id ?? -1) title=\(videoInfo.video.title)")
                        selectedVideoId = videoInfo.video.id
                        logger.notice("[GridView] selectedVideoId is now \(String(describing: selectedVideoId))")
                    } label: {
                        VideoGridItemView(videoInfo: videoInfo, isSelected: selectedVideoId == videoInfo.video.id)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .onChange(of: selectedVideoId) { old, new in
            logger.notice("[GridView] selectedVideoId changed: \(String(describing: old)) -> \(String(describing: new))")
        }
    }
}
