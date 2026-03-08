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
                    VideoGridItemView(videoInfo: videoInfo, isSelected: selectedVideoId == videoInfo.video.id)
                        .onTapGesture {
                            selectedVideoId = videoInfo.video.id
                        }
                }
            }
            .padding(12)
        }
    }
}
