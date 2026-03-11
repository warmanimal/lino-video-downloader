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
    private(set) var fetchingTasks: [FetchingTask] = []
    private var runningProcesses: [Int64: Process] = [:]
    private var pendingQueue: [(url: String, videoId: Int64, tags: [String])] = []
    var maxConcurrent = Constants.maxConcurrentDownloads

    /// Incremented whenever a download is enqueued, completes, or fails.
    /// Observe this from the library to trigger a refresh.
    private(set) var changeToken: Int = 0

    private let videoRepo: VideoRepository
    private let metadataService: MetadataService
    private let thumbnailService: ThumbnailService
    private let tweetTextService: TweetTextService
    private let articleMetadataService: ArticleMetadataService = ArticleMetadataService()
    private let roomRepo: RoomRepository

    init(
        videoRepo: VideoRepository,
        metadataService: MetadataService,
        thumbnailService: ThumbnailService,
        tweetTextService: TweetTextService = TweetTextService(),
        roomRepo: RoomRepository
    ) {
        self.videoRepo = videoRepo
        self.metadataService = metadataService
        self.thumbnailService = thumbnailService
        self.tweetTextService = tweetTextService
        self.roomRepo = roomRepo
    }

    var activeCount: Int { activeDownloads.count }
    var hasActiveDownloads: Bool { !activeDownloads.isEmpty }

    /// Immediately registers a fetching placeholder and kicks off metadata lookup + download
    /// in the background. Returns instantly so the caller can submit more URLs right away.
    func enqueueDownload(
        url: String,
        tags: [String],
        notes: String? = nil,
        roomId: Int64? = nil,
        collectionId: Int64? = nil
    ) {
        let platform = PlatformDetector.detect(from: url)
        let fetchingTask = FetchingTask(url: url, platform: platform)
        fetchingTasks.append(fetchingTask)

        Task {
            do {
                try await performEnqueue(
                    url: url, tags: tags, notes: notes,
                    roomId: roomId, collectionId: collectionId,
                    platform: platform, fetchingTask: fetchingTask
                )
            } catch {
                fetchingTask.error = error.localizedDescription
                // Auto-dismiss the error row after 5 s
                try? await Task.sleep(for: .seconds(5))
                fetchingTasks.removeAll { $0.id == fetchingTask.id }
            }
        }
    }

    private func performEnqueue(
        url: String,
        tags: [String],
        notes: String?,
        roomId: Int64?,
        collectionId: Int64?,
        platform: Video.Platform,
        fetchingTask: FetchingTask
    ) async throws {
        // PDF URLs skip yt-dlp entirely and are downloaded directly.
        if PlatformDetector.isPDFURL(url) {
            await downloadPDF(url: url, tags: tags, notes: notes, roomId: roomId, collectionId: collectionId, fetchingTask: fetchingTask)
            return
        }

        let metadata: YtDlpMetadata
        do {
            metadata = try await metadataService.fetchMetadata(url: url)
        } catch {
            // For Twitter/X, a "no video formats" failure means a text-only post.
            // Save it as a completed text-only entry instead of surfacing an error.
            let msg = error.localizedDescription.lowercased()
            let isNoMedia = msg.contains("no video") || msg.contains("no downloadable")
                || msg.contains("no media") || msg.contains("unsupported url")
            if platform == .twitter && isNoMedia {
                await saveTextTweet(
                    url: url, tags: tags, notes: notes,
                    roomId: roomId, collectionId: collectionId,
                    fetchingTask: fetchingTask
                )
                return
            }
            throw error
        }

        fetchingTasks.removeAll { $0.id == fetchingTask.id }

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
            errorMessage: nil,
            notes: notes
        )

        try videoRepo.insert(&video)

        guard let videoId = video.id else { return }

        if !tags.isEmpty {
            try videoRepo.setTags(videoId: videoId, tagNames: tags)
        }

        assignToRoomOrCollection(videoId: videoId, roomId: roomId, collectionId: collectionId)

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

    /// Saves a web article as a bookmark using Open Graph metadata.
    func saveAsArticle(url: String, tags: [String], notes: String? = nil, roomId: Int64? = nil, collectionId: Int64? = nil) {
        let fetchingTask = FetchingTask(url: url, platform: .other)
        fetchingTasks.append(fetchingTask)
        Task { await downloadArticleMetadata(url: url, tags: tags, notes: notes, roomId: roomId, collectionId: collectionId, fetchingTask: fetchingTask) }
    }

    private func downloadArticleMetadata(
        url: String, tags: [String], notes: String?,
        roomId: Int64?, collectionId: Int64?,
        fetchingTask: FetchingTask
    ) async {
        fetchingTasks.removeAll { $0.id == fetchingTask.id }

        let info = await articleMetadataService.fetchMetadata(url: url)
        let urlId = String(abs(url.hashValue), radix: 16)

        var video = Video(
            ytdlpId: urlId,
            title: info.title,
            description: info.description,
            uploader: info.siteName,
            uploaderUrl: nil,
            platform: .other,
            originalUrl: url,
            webpageUrl: url,
            uploadDate: nil,
            duration: nil,
            filePath: "",   // isTextOnly
            fileSize: nil,
            thumbnailPath: nil,
            width: nil,
            height: nil,
            addedAt: Date(),
            status: .completed,
            errorMessage: nil,
            notes: notes
        )

        guard (try? videoRepo.insert(&video)) != nil, let videoId = video.id else { return }
        if !tags.isEmpty { try? videoRepo.setTags(videoId: videoId, tagNames: tags) }
        assignToRoomOrCollection(videoId: videoId, roomId: roomId, collectionId: collectionId)

        if let thumbStr = info.thumbnailURL {
            let thumbSvc = thumbnailService
            let vRepo = videoRepo
            Task {
                if let path = try? await thumbSvc.downloadThumbnail(from: thumbStr, videoId: urlId) {
                    try? vRepo.updateThumbnailPath(videoId: videoId, thumbnailPath: path)
                }
            }
        }

        changeToken += 1
    }

    /// On-demand text-only save for Twitter/X URLs.
    func saveAsText(url: String, tags: [String], notes: String? = nil, roomId: Int64? = nil, collectionId: Int64? = nil) {
        let fetchingTask = FetchingTask(url: url, platform: .twitter)
        fetchingTasks.append(fetchingTask)
        Task { await saveTextTweet(url: url, tags: tags, notes: notes, roomId: roomId, collectionId: collectionId, fetchingTask: fetchingTask) }
    }

    /// Downloads a PDF from a direct URL and saves it as a completed library entry.
    private func downloadPDF(
        url: String,
        tags: [String],
        notes: String?,
        roomId: Int64?,
        collectionId: Int64?,
        fetchingTask: FetchingTask
    ) async {
        fetchingTasks.removeAll { $0.id == fetchingTask.id }

        guard let urlObj = URL(string: url) else { return }

        // Use a stable ID derived from the URL so re-adding the same PDF doesn't duplicate.
        let urlHash = String(abs(url.hashValue), radix: 16)
        let originalFilename = urlObj.lastPathComponent.isEmpty ? "document.pdf" : urlObj.lastPathComponent
        let filename = "\(urlHash)_\(originalFilename)"
        let destURL = Constants.storageDir.appendingPathComponent(filename)
        let title = (urlObj.deletingPathExtension().lastPathComponent)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: urlObj)

            let fm = FileManager.default
            try fm.createDirectory(at: Constants.storageDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
            try fm.moveItem(at: tempURL, to: destURL)

            let fileSize = (try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? nil

            var video = Video(
                ytdlpId: urlHash,
                title: title.isEmpty ? "Document" : title,
                description: nil,
                uploader: urlObj.host,
                uploaderUrl: nil,
                platform: .other,
                originalUrl: url,
                webpageUrl: url,
                uploadDate: nil,
                duration: nil,
                filePath: filename,
                fileSize: fileSize,
                thumbnailPath: nil,
                width: nil,
                height: nil,
                addedAt: Date(),
                status: .completed,
                errorMessage: nil,
                notes: notes
            )

            try videoRepo.insert(&video)
            guard let videoId = video.id else { return }

            if !tags.isEmpty { try? videoRepo.setTags(videoId: videoId, tagNames: tags) }
            assignToRoomOrCollection(videoId: videoId, roomId: roomId, collectionId: collectionId)
            changeToken += 1
        } catch {
            print("[DownloadService] PDF download failed: \(error)")
        }
    }

    /// Saves a text-only tweet (no downloadable media) as a completed library entry.
    private func saveTextTweet(
        url: String,
        tags: [String],
        notes: String?,
        roomId: Int64?,
        collectionId: Int64?,
        fetchingTask: FetchingTask
    ) async {
        fetchingTasks.removeAll { $0.id == fetchingTask.id }

        let tweetSvc = tweetTextService
        let info = await tweetSvc.fetchTweet(url: url)

        // Truncate tweet text to ~120 chars for the title field
        let title: String
        if info.text.isEmpty || info.text == "Tweet" {
            title = "Tweet"
        } else {
            title = info.text.count > 120
                ? String(info.text.prefix(117)) + "…"
                : info.text
        }

        var video = Video(
            ytdlpId: info.id,
            title: title,
            description: info.text == "Tweet" ? nil : info.text,
            uploader: info.authorName,
            uploaderUrl: info.authorUrl,
            platform: .twitter,
            originalUrl: url,
            webpageUrl: url,
            uploadDate: nil,
            duration: nil,
            filePath: "",       // No local file — marks as text-only
            fileSize: nil,
            thumbnailPath: nil,
            width: nil,
            height: nil,
            addedAt: Date(),
            status: .completed,
            errorMessage: nil,
            notes: notes
        )

        guard (try? videoRepo.insert(&video)) != nil, let videoId = video.id else { return }

        if !tags.isEmpty {
            try? videoRepo.setTags(videoId: videoId, tagNames: tags)
        }

        assignToRoomOrCollection(videoId: videoId, roomId: roomId, collectionId: collectionId)
        changeToken += 1
    }

    /// Fetches metadata and saves the record without starting a download.
    func saveURL(
        url: String,
        tags: [String],
        notes: String? = nil,
        roomId: Int64? = nil,
        collectionId: Int64? = nil
    ) {
        let platform = PlatformDetector.detect(from: url)
        let fetchingTask = FetchingTask(url: url, platform: platform)
        fetchingTasks.append(fetchingTask)

        Task {
            do {
                try await performSave(
                    url: url, tags: tags, notes: notes,
                    roomId: roomId, collectionId: collectionId,
                    platform: platform, fetchingTask: fetchingTask
                )
            } catch {
                fetchingTask.error = error.localizedDescription
                try? await Task.sleep(for: .seconds(5))
                fetchingTasks.removeAll { $0.id == fetchingTask.id }
            }
        }
    }

    private func performSave(
        url: String,
        tags: [String],
        notes: String?,
        roomId: Int64?,
        collectionId: Int64?,
        platform: Video.Platform,
        fetchingTask: FetchingTask
    ) async throws {
        let metadata = try await metadataService.fetchMetadata(url: url)

        fetchingTasks.removeAll { $0.id == fetchingTask.id }

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
            status: .saved,
            errorMessage: nil,
            notes: notes
        )

        try videoRepo.insert(&video)

        guard let videoId = video.id else { return }

        if !tags.isEmpty {
            try videoRepo.setTags(videoId: videoId, tagNames: tags)
        }

        assignToRoomOrCollection(videoId: videoId, roomId: roomId, collectionId: collectionId)

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
    }

    /// Adds the video directly to a room (if only roomId given) or to a specific
    /// collection (if collectionId given — collections are implicitly part of their room).
    private func assignToRoomOrCollection(videoId: Int64, roomId: Int64?, collectionId: Int64?) {
        if let collectionId {
            try? roomRepo.addItem(videoId: videoId, collectionId: collectionId)
        } else if let roomId {
            try? roomRepo.addItemToRoom(videoId: videoId, roomId: roomId)
        }
    }

    /// Notifies observers (e.g. LibraryView) that library data changed outside of a download.
    func notifyChange() { changeToken += 1 }

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
