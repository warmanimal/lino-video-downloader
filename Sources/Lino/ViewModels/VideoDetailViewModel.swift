import Foundation
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

@Observable
@MainActor
final class VideoDetailViewModel {
    private let videoRepo: VideoRepository
    private let downloadService: DownloadService
    private let metadataService: MetadataService

    var videoInfo: VideoInfo
    var editableTags: [String]
    var isEditingTags = false

    // Notes editing state
    var editableNotes: String = ""
    var isEditingNotes = false

    // Streaming state for saved (not-yet-downloaded) videos
    var streamURL: URL?
    var isLoadingStream = false
    var streamError: String?

    // Manual file attachment state
    var isAttaching = false
    var onVideoUpdated: (() -> Void)?

    init(videoInfo: VideoInfo, videoRepo: VideoRepository, downloadService: DownloadService, metadataService: MetadataService) {
        self.videoInfo = videoInfo
        self.videoRepo = videoRepo
        self.downloadService = downloadService
        self.metadataService = metadataService
        self.editableTags = videoInfo.tags.map(\.name)
        self.editableNotes = videoInfo.video.notes ?? ""
    }

    func saveNotes() {
        guard let videoId = videoInfo.video.id else { return }
        let trimmed = editableNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNotes: String? = trimmed.isEmpty ? nil : trimmed
        try? videoRepo.updateNotes(videoId: videoId, notes: newNotes)
        if let updated = try? videoRepo.fetchOne(id: videoId) {
            videoInfo = updated
            editableNotes = videoInfo.video.notes ?? ""
        }
        isEditingNotes = false
        onVideoUpdated?()
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

    func openFile() {
        NSWorkspace.shared.open(videoInfo.video.absoluteFilePath)
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

    /// Copies a locally-dropped video file into the storage directory and attaches it
    /// to this library entry, preserving all existing metadata.
    func attachDroppedFile(url: URL) async {
        guard let videoId = videoInfo.video.id else { return }

        let ext = url.pathExtension.lowercased()
        let fileName = "\(videoInfo.video.ytdlpId).\(ext)"
        let destURL = Constants.storageDir.appendingPathComponent(fileName)
        let fm = FileManager.default

        isAttaching = true
        defer { isAttaching = false }

        try? fm.removeItem(at: destURL)
        guard (try? fm.copyItem(at: url, to: destURL)) != nil else { return }

        // Extract dimensions off-main
        let assetURL = destURL
        let (width, height) = await Task.detached(priority: .userInitiated) {
            var w: Int?
            var h: Int?
            let asset = AVURLAsset(url: assetURL)
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let natural = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                let t = natural.applying(transform)
                w = abs(Int(t.width))
                h = abs(Int(t.height))
            }
            return (w, h)
        }.value

        let ytdlpId = videoInfo.video.ytdlpId
        let thumbnailPath = await Task.detached(priority: .userInitiated) {
            try? await VideoDetailViewModel.generateThumbnail(from: assetURL, id: ytdlpId)
        }.value

        let fileSize = (try? fm.attributesOfItem(atPath: destURL.path))?[.size] as? Int64

        try? videoRepo.updateMedia(
            videoId: videoId,
            filePath: fileName,
            fileSize: fileSize,
            width: width,
            height: height,
            thumbnailPath: thumbnailPath
        )

        if let updated = try? videoRepo.fetchOne(id: videoId) {
            videoInfo = updated
        }
        onVideoUpdated?()
    }

    private static func generateThumbnail(from url: URL, id: String) async throws -> String {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        let (cgImage, _) = try await generator.image(at: .zero)

        let thumbDir = Constants.storageDir.appendingPathComponent(".thumbnails")
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)

        let thumbFileName = ".thumbnails/\(id).jpg"
        let thumbURL = Constants.storageDir.appendingPathComponent(thumbFileName)
        try? FileManager.default.removeItem(at: thumbURL)

        guard let dest = CGImageDestinationCreateWithURL(
            thumbURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw NSError(domain: "VideoDetailViewModel", code: 1) }

        CGImageDestinationAddImage(dest, cgImage, [
            kCGImageDestinationLossyCompressionQuality: 0.85
        ] as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "VideoDetailViewModel", code: 2)
        }

        return thumbFileName
    }
}

private extension NSWorkspace {
    func activatingAccessor(at url: URL) {
        selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
}
