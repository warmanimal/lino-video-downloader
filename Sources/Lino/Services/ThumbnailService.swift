import Foundation
import AVFoundation
import AppKit
import CoreMedia

actor ThumbnailService {
    func downloadThumbnail(from urlString: String, videoId: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw ThumbnailError.invalidURL
        }

        let fileName = "\(videoId).jpg"
        let destination = Constants.thumbnailDir.appendingPathComponent(fileName)

        // Ensure thumbnail directory exists
        try FileManager.default.createDirectory(
            at: Constants.thumbnailDir,
            withIntermediateDirectories: true
        )

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ThumbnailError.downloadFailed
        }

        try data.write(to: destination)

        return ".thumbnails/\(fileName)"
    }

    func generateThumbnail(from videoURL: URL, videoId: String) async throws -> String {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw ThumbnailError.conversionFailed
        }

        let fileName = "\(videoId).jpg"
        let destination = Constants.thumbnailDir.appendingPathComponent(fileName)

        try FileManager.default.createDirectory(
            at: Constants.thumbnailDir,
            withIntermediateDirectories: true
        )

        try jpegData.write(to: destination)

        return ".thumbnails/\(fileName)"
    }

    func thumbnailURL(for video: Video) -> URL? {
        video.absoluteThumbnailPath
    }
}

enum ThumbnailError: LocalizedError {
    case invalidURL
    case downloadFailed
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid thumbnail URL"
        case .downloadFailed: return "Failed to download thumbnail"
        case .conversionFailed: return "Failed to convert thumbnail image"
        }
    }
}
