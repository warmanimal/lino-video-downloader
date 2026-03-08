import Foundation

enum MetadataServiceError: LocalizedError {
    case ytdlpNotFound
    case fetchFailed(String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .ytdlpNotFound:
            return "yt-dlp binary not found. Please check Settings."
        case .fetchFailed(let message):
            return "Failed to fetch metadata: \(message)"
        case .decodingFailed(let error):
            return "Failed to parse metadata: \(error.localizedDescription)"
        }
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
                process.arguments = [
                    "--dump-json",
                    "--no-download",
                    "--no-warnings",
                    "--no-playlist",
                    url
                ]

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
