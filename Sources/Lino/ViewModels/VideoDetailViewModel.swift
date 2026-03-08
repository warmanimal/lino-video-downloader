import Foundation
import AppKit

@Observable
@MainActor
final class VideoDetailViewModel {
    private let videoRepo: VideoRepository
    private let downloadService: DownloadService
    private let metadataService: MetadataService

    var videoInfo: VideoInfo
    var editableTags: [String]
    var isEditingTags = false

    // Streaming state for saved (not-yet-downloaded) videos
    var streamURL: URL?
    var isLoadingStream = false
    var streamError: String?

    init(videoInfo: VideoInfo, videoRepo: VideoRepository, downloadService: DownloadService, metadataService: MetadataService) {
        self.videoInfo = videoInfo
        self.videoRepo = videoRepo
        self.downloadService = downloadService
        self.metadataService = metadataService
        self.editableTags = videoInfo.tags.map(\.name)
    }

    func saveTags() {
        guard let videoId = videoInfo.video.id else { return }
        do {
            try videoRepo.setTags(videoId: videoId, tagNames: editableTags)
            // Refresh
            if let updated = try videoRepo.fetchOne(id: videoId) {
                videoInfo = updated
            }
            isEditingTags = false
        } catch {
            print("Failed to save tags: \(error)")
        }
    }

    func openOriginalURL() {
        if let url = URL(string: videoInfo.video.originalUrl) {
            NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder() {
        let fileURL = videoInfo.video.absoluteFilePath
        NSWorkspace.shared.activatingAccessor(at: fileURL)
    }

    func retryDownload() async {
        guard let videoId = videoInfo.video.id else { return }
        try? await downloadService.retryDownload(videoId: videoId)
    }

    func downloadVideo() async {
        guard let videoId = videoInfo.video.id else { return }
        try? await downloadService.retryDownload(videoId: videoId)
    }

    func loadStreamURL() async {
        guard streamURL == nil, !isLoadingStream else { return }
        isLoadingStream = true
        streamError = nil
        do {
            streamURL = try await metadataService.fetchStreamURL(url: videoInfo.video.originalUrl)
        } catch {
            streamError = error.localizedDescription
        }
        isLoadingStream = false
    }
}

private extension NSWorkspace {
    func activatingAccessor(at url: URL) {
        selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
}
