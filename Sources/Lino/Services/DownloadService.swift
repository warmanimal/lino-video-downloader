import Foundation

enum DownloadError: LocalizedError {
    case ytdlpNotFound
    case downloadFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ytdlpNotFound:
            return "yt-dlp binary not found. Please check Settings."
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .cancelled:
            return "Download was cancelled."
        }
    }
}

@Observable
@MainActor
final class DownloadService {
    private(set) var activeDownloads: [Int64: DownloadTask] = [:]
    private var runningProcesses: [Int64: Process] = [:]
    private var pendingQueue: [(url: String, videoId: Int64, tags: [String])] = []
    var maxConcurrent = Constants.maxConcurrentDownloads

    /// Incremented whenever a download is enqueued, completes, or fails.
    /// Observe this from the library to trigger a refresh.
    private(set) var changeToken: Int = 0

    private let videoRepo: VideoRepository
    private let metadataService: MetadataService
    private let thumbnailService: ThumbnailService

    init(videoRepo: VideoRepository, metadataService: MetadataService, thumbnailService: ThumbnailService) {
        self.videoRepo = videoRepo
        self.metadataService = metadataService
        self.thumbnailService = thumbnailService
    }

    var activeCount: Int { activeDownloads.count }
    var hasActiveDownloads: Bool { !activeDownloads.isEmpty }

    func enqueueDownload(url: String, tags: [String]) async throws {
        let metadata = try await metadataService.fetchMetadata(url: url)

        let platform = PlatformDetector.detect(from: url)
        let fileName = "\(metadata.id).\(metadata.ext ?? "mp4")"

        var video = Video(
            ytdlpId: metadata.id,
            title: metadata.title ?? "Untitled",
            description: metadata.description,
            uploader: metadata.uploader,
            uploaderUrl: metadata.uploaderUrl,
            platform: platform,
            originalUrl: url,
            webpageUrl: metadata.webpageUrl,
            uploadDate: metadata.uploadDate,
            duration: metadata.duration,
            filePath: fileName,
            fileSize: metadata.effectiveFileSize,
            thumbnailPath: nil,
            width: metadata.width,
            height: metadata.height,
            addedAt: Date(),
            status: .pending,
            errorMessage: nil
        )

        try videoRepo.insert(&video)

        guard let videoId = video.id else { return }

        if !tags.isEmpty {
            try videoRepo.setTags(videoId: videoId, tagNames: tags)
        }

        if let thumbnailUrl = metadata.thumbnail {
            let thumbService = self.thumbnailService
            let vRepo = self.videoRepo
            let metaId = metadata.id
            Task {
                do {
                    let thumbPath = try await thumbService.downloadThumbnail(
                        from: thumbnailUrl,
                        videoId: metaId
                    )
                    try vRepo.updateThumbnailPath(videoId: videoId, thumbnailPath: thumbPath)
                } catch {
                    print("Thumbnail download failed: \(error)")
                }
            }
        }

        changeToken += 1

        if activeCount < maxConcurrent {
            await startDownload(url: url, videoId: videoId, platform: platform)
        } else {
            pendingQueue.append((url: url, videoId: videoId, tags: tags))
        }
    }

    func cancelDownload(videoId: Int64) {
        if let process = runningProcesses[videoId] {
            process.terminate()
            runningProcesses.removeValue(forKey: videoId)
        }
        activeDownloads[videoId]?.isCancelled = true
        activeDownloads.removeValue(forKey: videoId)
        try? videoRepo.updateStatus(videoId: videoId, status: .failed, error: "Cancelled")
        processQueue()
    }

    func retryDownload(videoId: Int64) async throws {
        guard let info = try videoRepo.fetchOne(id: videoId) else { return }
        try videoRepo.updateStatus(videoId: videoId, status: .pending)
        await startDownload(
            url: info.video.originalUrl,
            videoId: videoId,
            platform: info.video.platform
        )
    }

    // MARK: - Private

    private func startDownload(url: String, videoId: Int64, platform: Video.Platform) async {
        let task = DownloadTask(id: videoId, url: url, platform: platform)
        activeDownloads[videoId] = task
        try? videoRepo.updateStatus(videoId: videoId, status: .downloading)

        let vRepo = self.videoRepo

        Task.detached {
            do {
                let result = try await Self.runYtDlpDownload(url: url, videoId: videoId) { progress in
                    Task { @MainActor in
                        task.progress = progress
                    }
                }

                // Ensure the file is playable by AVPlayer (correct container + supported codec).
                if let result {
                    let fileName = URL(fileURLWithPath: result).lastPathComponent
                    let fileURL = Constants.storageDir.appendingPathComponent(fileName)

                    await MainActor.run {
                        task.progress = DownloadProgress(percent: 100, phase: .remuxing)
                    }
                    do {
                        try await VideoRemuxer.ensurePlayable(at: fileURL)
                    } catch {
                        print("Post-processing failed (video may not play): \(error)")
                    }
                }

                await MainActor.run {
                    if let result {
                        let fileName = URL(fileURLWithPath: result).lastPathComponent
                        let fileSizeVal = Self.fileSize(at: Constants.storageDir.appendingPathComponent(fileName))
                        try? vRepo.updateFilePath(
                            videoId: videoId,
                            filePath: fileName,
                            fileSize: fileSizeVal
                        )
                    }
                    try? vRepo.updateStatus(videoId: videoId, status: .completed)
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    try? vRepo.updateStatus(videoId: videoId, status: .failed, error: message)
                }
            }

            await MainActor.run { [weak self] in
                self?.activeDownloads.removeValue(forKey: videoId)
                self?.runningProcesses.removeValue(forKey: videoId)
                self?.changeToken += 1
                self?.processQueue()
            }
        }
    }

    private func processQueue() {
        while activeCount < maxConcurrent, !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            let platform = PlatformDetector.detect(from: next.url)
            Task {
                await startDownload(url: next.url, videoId: next.videoId, platform: platform)
            }
        }
    }

    private static func runYtDlpDownload(
        url: String,
        videoId: Int64,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> String? {
        let ytdlpPath = Constants.ytdlpPath

        guard FileManager.default.isExecutableFile(atPath: ytdlpPath.path) else {
            throw DownloadError.ytdlpNotFound
        }

        final class LineBuffer: @unchecked Sendable {
            var lastLine = ""
            let lock = NSLock()

            func processChunk(_ data: Data, onProgress: @escaping @Sendable (DownloadProgress) -> Void) {
                guard !data.isEmpty else { return }
                guard let text = String(data: data, encoding: .utf8) else { return }

                for line in text.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    lock.lock()
                    lastLine = trimmed
                    lock.unlock()

                    if trimmed.hasPrefix("{"), let jsonData = trimmed.data(using: .utf8) {
                        if let update = try? JSONDecoder().decode(YtDlpProgressUpdate.self, from: jsonData) {
                            onProgress(update.toDownloadProgress())
                        }
                    }
                }
            }

            func getLastLine() -> String {
                lock.lock()
                defer { lock.unlock() }
                return lastLine
            }
        }

        // Run the blocking subprocess off the cooperative thread pool.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = ytdlpPath
                process.environment = Constants.subprocessEnvironment
                var args = [
                    "--newline",
                    "--progress",
                    "--progress-template",
                    "download:{\"percent\":\"%(progress._percent_str)s\",\"speed\":\"%(progress._speed_str)s\",\"eta\":\"%(progress._eta_str)s\",\"total\":\"%(progress._total_bytes_str)s\"}",
                    "--progress-template",
                    "postprocess:{\"status\":\"postprocessing\"}",
                    "--print", "after_move:filepath",
                    "-S", "vcodec:h264,ext:mp4:m4a",
                    "--merge-output-format", "mp4",
                    "-o", "%(id)s.%(ext)s",
                    "-P", Constants.storageDir.path,
                ]
                // Point yt-dlp at a working ffmpeg so it can merge multi-stream downloads.
                if let ffmpeg = Constants.ffmpegPath {
                    args += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
                }
                args.append(url)
                process.arguments = args

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                let lineBuffer = LineBuffer()
                let readHandle = stdout.fileHandleForReading
                readHandle.readabilityHandler = { handle in
                    lineBuffer.processChunk(handle.availableData, onProgress: onProgress)
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                process.waitUntilExit()

                readHandle.readabilityHandler = nil
                let remainingData = readHandle.readDataToEndOfFile()
                lineBuffer.processChunk(remainingData, onProgress: onProgress)

                guard process.terminationStatus == 0 else {
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: DownloadError.downloadFailed(errorString))
                    return
                }

                let result = lineBuffer.getLastLine()
                continuation.resume(returning: result.isEmpty ? nil : result)
            }
        }
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return nil }
        return size
    }
}

private struct YtDlpProgressUpdate: Codable {
    let status: String?
    let percent: String?
    let speed: String?
    let eta: String?
    let total: String?

    func toDownloadProgress() -> DownloadProgress {
        let pct = percent?
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "%", with: "")
        return DownloadProgress(
            percent: Double(pct ?? "0") ?? 0,
            speed: speed?.trimmingCharacters(in: .whitespaces),
            eta: eta?.trimmingCharacters(in: .whitespaces),
            totalSize: total?.trimmingCharacters(in: .whitespaces),
            phase: status == "postprocessing" ? .postProcessing : .downloading
        )
    }
}
