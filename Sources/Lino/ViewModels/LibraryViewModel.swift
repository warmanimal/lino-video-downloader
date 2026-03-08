import Foundation

@Observable
@MainActor
final class LibraryViewModel {
    private let videoRepo: VideoRepository

    var videos: [VideoInfo] = []
    var searchText = ""
    var selectedPlatform: Video.Platform?
    var selectedTagIds: [Int64] = []
    var sortBy: SortField = .addedAtDesc
    var selectedVideoId: Int64?
    var isGridView = true
    var isLoading = false
    var errorMessage: String?

    // Trash
    var showingTrash = false
    var trashedVideos: [VideoInfo] = []
    var trashedCount: Int = 0

    init(videoRepo: VideoRepository) {
        self.videoRepo = videoRepo
    }

    var selectedVideoInfo: VideoInfo? {
        let source = showingTrash ? trashedVideos : videos
        guard let id = selectedVideoId else { return nil }
        return source.first { $0.video.id == id }
    }

    func loadVideos() {
        isLoading = true
        errorMessage = nil
        do {
            videos = try videoRepo.fetchAll(
                searchText: searchText.isEmpty ? nil : searchText,
                platform: selectedPlatform,
                tagIds: selectedTagIds,
                sortBy: sortBy
            )
            trashedCount = try videoRepo.trashedCount()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadTrashedVideos() {
        do {
            trashedVideos = try videoRepo.fetchTrashed()
            trashedCount = trashedVideos.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Soft Delete (Move to Trash)

    func trashVideo(_ video: Video) {
        guard let id = video.id else { return }
        try? videoRepo.softDelete(id: id)

        if selectedVideoId == id {
            selectedVideoId = nil
        }

        loadVideos()
    }

    // MARK: - Restore from Trash

    func restoreVideo(id: Int64) {
        try? videoRepo.restore(id: id)

        if selectedVideoId == id {
            selectedVideoId = nil
        }

        loadTrashedVideos()
        loadVideos()
    }

    // MARK: - Permanent Delete

    func permanentlyDeleteVideo(_ video: Video) {
        guard let id = video.id else { return }

        // Delete file from disk
        try? FileManager.default.removeItem(at: video.absoluteFilePath)

        // Delete thumbnail
        if let thumbURL = video.absoluteThumbnailPath {
            try? FileManager.default.removeItem(at: thumbURL)
        }

        // Hard delete from database
        try? videoRepo.delete(id: id)

        if selectedVideoId == id {
            selectedVideoId = nil
        }

        loadTrashedVideos()
    }

    func emptyTrash() {
        for info in trashedVideos {
            permanentlyDeleteVideo(info.video)
        }
    }

    /// Purge trash items older than 7 days. Called on app launch.
    func purgeExpiredTrash() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        guard let expired = try? videoRepo.fetchExpiredTrash(olderThan: cutoff) else { return }

        for video in expired {
            permanentlyDeleteVideo(video)
        }
    }
}
