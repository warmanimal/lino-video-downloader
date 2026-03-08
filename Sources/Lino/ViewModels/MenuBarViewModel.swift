import Foundation

@Observable
@MainActor
final class MenuBarViewModel {
    private let downloadService: DownloadService

    var urlText = ""
    var tags: [String] = []
    var detectedPlatform: Video.Platform?
    var isValidURL = false
    var isSubmitting = false
    var errorMessage: String?
    var successMessage: String?

    init(downloadService: DownloadService) {
        self.downloadService = downloadService
    }

    var activeDownloads: [Int64: DownloadTask] {
        downloadService.activeDownloads
    }

    func validateURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        isValidURL = PlatformDetector.isValidURL(trimmed)
        detectedPlatform = isValidURL ? PlatformDetector.detect(from: trimmed) : nil
    }

    func submit() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlatformDetector.isValidURL(trimmed) else {
            errorMessage = "Please enter a valid URL."
            return
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil

        do {
            try await downloadService.enqueueDownload(url: trimmed, tags: tags)
            successMessage = "Download started!"
            urlText = ""
            tags = []
            detectedPlatform = nil
            isValidURL = false
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    func clear() {
        urlText = ""
        tags = []
        detectedPlatform = nil
        isValidURL = false
        errorMessage = nil
        successMessage = nil
    }
}
