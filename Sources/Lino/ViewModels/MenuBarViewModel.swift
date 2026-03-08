import Foundation

@Observable
@MainActor
final class MenuBarViewModel {
    private let downloadService: DownloadService

    var urlText = ""
    var tags: [String] = []
    var detectedPlatform: Video.Platform?
    var isValidURL = false
    var errorMessage: String?

    init(downloadService: DownloadService) {
        self.downloadService = downloadService
    }

    var activeDownloads: [Int64: DownloadTask] {
        downloadService.activeDownloads
    }

    var fetchingTasks: [FetchingTask] {
        downloadService.fetchingTasks
    }

    func validateURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        isValidURL = PlatformDetector.isValidURL(trimmed)
        detectedPlatform = isValidURL ? PlatformDetector.detect(from: trimmed) : nil
    }

    func submit() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlatformDetector.isValidURL(trimmed) else {
            errorMessage = "Please enter a valid URL."
            return
        }

        errorMessage = nil
        downloadService.enqueueDownload(url: trimmed, tags: tags)
        clearForm()
    }

    func save() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlatformDetector.isValidURL(trimmed) else {
            errorMessage = "Please enter a valid URL."
            return
        }

        errorMessage = nil
        downloadService.saveURL(url: trimmed, tags: tags)
        clearForm()
    }

    private func clearForm() {
        urlText = ""
        tags = []
        detectedPlatform = nil
        isValidURL = false
    }

    func clear() {
        clearForm()
        errorMessage = nil
    }
}
