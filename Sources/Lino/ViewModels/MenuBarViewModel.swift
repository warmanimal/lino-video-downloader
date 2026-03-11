import Foundation

// MARK: - Save destination

/// A room or collection the user wants to assign a newly added item to.
enum SaveDestination: Hashable, Sendable {
    case room(id: Int64)
    case collection(id: Int64)

    var roomId: Int64? {
        if case .room(let id) = self { return id }
        return nil
    }
    var collectionId: Int64? {
        if case .collection(let id) = self { return id }
        return nil
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class MenuBarViewModel {
    private let downloadService: DownloadService
    private let roomRepo: RoomRepository
    private let videoRepo: VideoRepository

    // MARK: Form fields
    var urlText = ""
    var tags: [String] = []
    var notes = ""
    var detectedPlatform: Video.Platform?
    var isValidURL = false
    var errorMessage: String?
    var selectedRoomId: Int64? = nil
    var selectedCollectionId: Int64? = nil

    /// Derived destination from the two pickers.
    var destination: SaveDestination? {
        if let colId = selectedCollectionId { return .collection(id: colId) }
        if let roomId = selectedRoomId { return .room(id: roomId) }
        return nil
    }

    // MARK: Room / Collection data (for the Save-to picker)
    var rooms: [Room] = []
    var allCollections: [VideoCollection] = []

    // MARK: Duplicate detection
    var existingVideo: VideoInfo? = nil
    var existingMemberships: VideoMemberships? = nil
    var isDuplicateChecking = false

    var isDuplicate: Bool { existingVideo != nil }

    // MARK: Init

    init(downloadService: DownloadService, roomRepo: RoomRepository, videoRepo: VideoRepository) {
        self.downloadService = downloadService
        self.roomRepo = roomRepo
        self.videoRepo = videoRepo
        loadDestinationData()
    }

    // MARK: Active downloads (forwarded from service)

    var activeDownloads: [Int64: DownloadTask] { downloadService.activeDownloads }
    var fetchingTasks: [FetchingTask] { downloadService.fetchingTasks }

    // MARK: Load helpers

    func loadDestinationData() {
        rooms = (try? roomRepo.fetchAllRooms()) ?? []
        allCollections = (try? roomRepo.fetchAllCollections()) ?? []
    }

    /// Returns all collections that belong to the given room.
    func collections(for roomId: Int64) -> [VideoCollection] {
        allCollections.filter { $0.roomId == roomId }
    }

    // MARK: URL validation + duplicate check

    func validateURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        isValidURL = PlatformDetector.isValidURL(trimmed)
        detectedPlatform = isValidURL ? PlatformDetector.detect(from: trimmed) : nil
        // Reset duplicate state whenever URL changes
        existingVideo = nil
        existingMemberships = nil
        if isValidURL {
            Task { await checkForDuplicate(url: trimmed) }
        }
    }

    private func checkForDuplicate(url: String) async {
        isDuplicateChecking = true
        defer { isDuplicateChecking = false }
        guard let info = try? videoRepo.findByOriginalURL(url),
              let videoId = info.video.id else { return }
        existingVideo = info
        existingMemberships = try? roomRepo.fetchMemberships(videoId: videoId)
        // Pre-populate notes with whatever is already saved
        if notes.isEmpty, let existing = info.video.notes {
            notes = existing
        }
    }

    // MARK: Submit / Save (new items)

    func submit() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlatformDetector.isValidURL(trimmed) else {
            errorMessage = "Please enter a valid URL."
            return
        }
        errorMessage = nil
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        downloadService.enqueueDownload(
            url: trimmed,
            tags: tags,
            notes: notesTrimmed.isEmpty ? nil : notesTrimmed,
            roomId: destination?.roomId,
            collectionId: destination?.collectionId
        )
        clearForm()
    }

    func save() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlatformDetector.isValidURL(trimmed) else {
            errorMessage = "Please enter a valid URL."
            return
        }
        errorMessage = nil
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        downloadService.saveURL(
            url: trimmed,
            tags: tags,
            notes: notesTrimmed.isEmpty ? nil : notesTrimmed,
            roomId: destination?.roomId,
            collectionId: destination?.collectionId
        )
        clearForm()
    }

    func saveArticle() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlatformDetector.isValidURL(trimmed) else {
            errorMessage = "Please enter a valid URL."
            return
        }
        errorMessage = nil
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        downloadService.saveAsArticle(
            url: trimmed,
            tags: tags,
            notes: notesTrimmed.isEmpty ? nil : notesTrimmed,
            roomId: destination?.roomId,
            collectionId: destination?.collectionId
        )
        clearForm()
    }

    func saveTextOnly() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlatformDetector.isValidURL(trimmed) else {
            errorMessage = "Please enter a valid URL."
            return
        }
        errorMessage = nil
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        downloadService.saveAsText(
            url: trimmed,
            tags: tags,
            notes: notesTrimmed.isEmpty ? nil : notesTrimmed,
            roomId: destination?.roomId,
            collectionId: destination?.collectionId
        )
        clearForm()
    }

    // MARK: Update existing item (duplicate path)

    func updateExisting() {
        guard let info = existingVideo, let videoId = info.video.id else { return }

        // Save notes if changed
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNotes: String? = notesTrimmed.isEmpty ? nil : notesTrimmed
        if newNotes != info.video.notes {
            try? videoRepo.updateNotes(videoId: videoId, notes: newNotes)
        }

        // Add to selected destination
        if let dest = destination {
            switch dest {
            case .collection(let id):
                try? roomRepo.addItem(videoId: videoId, collectionId: id)
            case .room(let id):
                try? roomRepo.addItemToRoom(videoId: videoId, roomId: id)
            }
        }

        // Refresh memberships for the updated card
        existingMemberships = try? roomRepo.fetchMemberships(videoId: videoId)
        selectedRoomId = nil
        selectedCollectionId = nil
        downloadService.notifyChange()
    }

    // MARK: Clear

    private func clearForm() {
        urlText = ""
        tags = []
        notes = ""
        detectedPlatform = nil
        isValidURL = false
        selectedRoomId = nil
        selectedCollectionId = nil
        existingVideo = nil
        existingMemberships = nil
    }

    func clear() {
        clearForm()
        errorMessage = nil
    }
}
