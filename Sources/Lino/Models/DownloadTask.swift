import Foundation

struct DownloadProgress: Sendable {
    var percent: Double
    var speed: String?
    var eta: String?
    var totalSize: String?
    var phase: Phase

    enum Phase: Sendable {
        case downloading
        case postProcessing
        case remuxing
    }

    static let zero = DownloadProgress(percent: 0, phase: .downloading)
}

@Observable
@MainActor
final class DownloadTask: Identifiable {
    let id: Int64
    let url: String
    let platform: Video.Platform
    var progress: DownloadProgress = .zero
    var isCancelled = false

    init(id: Int64, url: String, platform: Video.Platform) {
        self.id = id
        self.url = url
        self.platform = platform
    }
}
