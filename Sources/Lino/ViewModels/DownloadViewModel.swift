import Foundation

@Observable
@MainActor
final class DownloadViewModel {
    private let downloadService: DownloadService

    init(downloadService: DownloadService) {
        self.downloadService = downloadService
    }

    var activeDownloads: [DownloadTask] {
        Array(downloadService.activeDownloads.values)
    }

    var hasActiveDownloads: Bool {
        downloadService.hasActiveDownloads
    }

    func cancelDownload(videoId: Int64) {
        downloadService.cancelDownload(videoId: videoId)
    }
}
