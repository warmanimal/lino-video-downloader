import Foundation
import GRDB

struct VideoInfo: Decodable, FetchableRecord, Sendable, Identifiable {
    var video: Video
    var tags: [Tag]

    var id: Int64? { video.id }
}
