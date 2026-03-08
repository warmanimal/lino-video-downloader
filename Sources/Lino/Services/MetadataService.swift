import Foundation

enum MetadataServiceError: LocalizedError {
    case ytdlpNotFound
    case fetchFailed(String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .ytdlpNotFound:
            return "yt-dlp binary not found. Please check Settings."
        case .fetchFailed(let raw):
            return Self.friendlyMessage(from: raw)
        case .decodingFailed(let error):
            return "Failed to parse metadata: \(error.localizedDescription)"
        }
    }

    /// Parse raw yt-dlp stderr into a concise, human-readable message.
    private static func friendlyMessage(from raw: String) -> String {
        // Extract the platform tag, e.g. "[Pinterest]"
        let platform: String? = {
            guard let open = raw.range(of: "["),
                  let close = raw.range(of: "]", range: open.upperBound..<raw.endIndex) else { return nil }
            return String(raw[open.upperBound..<close.lowerBound])
        }()
        let prefix = platform.map { "\($0): " } ?? ""

        let lowered = raw.lowercased()

        if lowered.contains("http error 404") || lowered.contains("not found") {
            return "\(prefix)This content was not found. It may have been removed or made private."
        }
        if lowered.contains("http error 403") || lowered.contains("forbidden") {
            return "\(prefix)Access denied. This content may be private or require login."
        }
        if lowered.contains("http error 429") || lowered.contains("too many requests") {
            return "\(prefix)Rate limited. Please wait a moment and try again."
        }
        if lowered.contains("video unavailable") || lowered.contains("is not available") {
            return "\(prefix)This video is unavailable."
        }
        if lowered.contains("unsupported url") {
            return "This URL is not supported."
        }
        if lowered.contains("is not a valid url") || lowered.contains("no video formats") {
            return "\(prefix)No downloadable video was found at this URL."
        }
        if lowered.contains("private video") || lowered.contains("sign in") || lowered.contains("login required") {
            return "\(prefix)This content is private or requires authentication."
        }

        // Fallback: strip the verbose yt-dlp prefix
        let cleaned = raw
            .replacingOccurrences(of: "ERROR: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}

actor MetadataService {
    private let ytdlpPathProvider: () -> URL

    init(ytdlpPathProvider: @escaping () -> URL = { Constants.ytdlpPath }) {
        self.ytdlpPathProvider = ytdlpPathProvider
    }

    func fetchMetadata(url: String) async throws -> YtDlpMetadata {
        let ytdlpPath = ytdlpPathProvider()

        guard FileManager.default.isExecutableFile(atPath: ytdlpPath.path) else {
            throw MetadataServiceError.ytdlpNotFound
        }

        // Run the blocking subprocess off the cooperative thread pool
        // to avoid starving the main actor.
        let (data, errorData, status) = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(Data, Data, Int32), any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = ytdlpPath
                process.environment = Constants.subprocessEnvironment
                var args = [
                    "--dump-json",
                    "--no-download",
                    "--no-warnings",
                    "--no-playlist",
                ]
                if let ffmpeg = Constants.ffmpegPath {
                    args += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
                }
                args.append(url)
                process.arguments = args

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(returning: (outData, errData, process.terminationStatus))
            }
        }

        guard status == 0 else {
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw MetadataServiceError.fetchFailed(errorString)
        }

        do {
            return try JSONDecoder().decode(YtDlpMetadata.self, from: data)
        } catch {
            throw MetadataServiceError.decodingFailed(error)
        }
    }
}
