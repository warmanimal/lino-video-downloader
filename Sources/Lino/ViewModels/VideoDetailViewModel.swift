import Foundation
import AppKit

@Observable
@MainActor
final class VideoDetailViewModel {
    private let videoRepo: VideoRepository
    private let downloadService: DownloadService

    var videoInfo: VideoInfo
    var editableTags: [String]
    var isEditingTags = false
    var isRemuxing = false
    /// Incremented after a successful remux so the player view refreshes.
    var remuxToken: Int = 0

    init(videoInfo: VideoInfo, videoRepo: VideoRepository, downloadService: DownloadService) {
        self.videoInfo = videoInfo
        self.videoRepo = videoRepo
        self.downloadService = downloadService
        self.editableTags = videoInfo.tags.map(\.name)

        // Auto-remux existing videos stored in non-MP4 containers.
        if videoInfo.video.status == .completed {
            let fileURL = videoInfo.video.absoluteFilePath
            if FileManager.default.fileExists(atPath: fileURL.path),
               !VideoRemuxer.isPlayableContainer(at: fileURL) {
                Task { await self.remuxExistingFile() }
            }
        }
    }

    /// Remux an existing completed video whose file is not a proper MP4 container.
    private func remuxExistingFile() async {
        let fileURL = videoInfo.video.absoluteFilePath
        isRemuxing = true
        do {
            _ = try await VideoRemuxer.remux(source: fileURL)
            // Update file size in DB after remux
            if let videoId = videoInfo.video.id {
                let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let newSize = attrs?[.size] as? Int64
                try? videoRepo.updateFilePath(videoId: videoId, filePath: videoInfo.video.filePath, fileSize: newSize)
            }
            remuxToken += 1
        } catch {
            print("On-demand remux failed: \(error)")
        }
        isRemuxing = false
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
}

private extension NSWorkspace {
    func activatingAccessor(at url: URL) {
        selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
}
