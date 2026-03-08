import SwiftUI

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
                }
            }
            .padding(12)
        }
    }
}
