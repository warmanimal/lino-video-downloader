import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

actor FileImportService {
    private let videoRepo: VideoRepository

    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "avi", "mkv", "webm",
        "ts", "m2ts", "flv", "wmv", "3gp", "ogv", "mpeg", "mpg"
    ]

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp"
    ]

    static let documentExtensions: Set<String> = ["pdf"]

    init(videoRepo: VideoRepository) {
        self.videoRepo = videoRepo
    }

    /// Import local file URLs, returning the database IDs of successfully imported records.
    func importFiles(_ urls: [URL]) async -> [Int64] {
        var ids: [Int64] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            do {
                if Self.videoExtensions.contains(ext) {
                    if let id = try await importVideoFile(url) { ids.append(id) }
                } else if Self.imageExtensions.contains(ext) {
                    if let id = try await importImageFile(url) { ids.append(id) }
                } else if Self.documentExtensions.contains(ext) {
                    if let id = try importPDFFile(url) { ids.append(id) }
                }
            } catch {
                print("FileImportService: failed to import \(url.lastPathComponent): \(error)")
            }
        }
        return ids
    }

    // MARK: - Private

    private func importVideoFile(_ sourceURL: URL) async throws -> Int64? {
        let fileId = UUID().uuidString.lowercased()
        let ext = sourceURL.pathExtension.lowercased()
        let fileName = "\(fileId).\(ext)"
        let destURL = Constants.storageDir.appendingPathComponent(fileName)

        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Extract duration + dimensions via AVAsset (async, off-main)
        let asset = AVURLAsset(url: destURL)
        var duration: Double?
        var width: Int?
        var height: Int?
        do {
            let d = try await asset.load(.duration)
            duration = d.seconds.isFinite && d.seconds > 0 ? d.seconds : nil
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let natural = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let transformed = natural.applying(transform)
                width = abs(Int(transformed.width))
                height = abs(Int(transformed.height))
            }
        } catch {
            // Non-fatal — proceed without metadata
        }

        let thumbnailPath = try? await generateVideoThumbnail(from: destURL, id: fileId)
        let fileSize = byteSize(at: destURL)
        let title = sourceURL.deletingPathExtension().lastPathComponent

        var video = Video(
            ytdlpId: fileId,
            title: title.isEmpty ? fileName : title,
            description: nil,
            uploader: nil,
            uploaderUrl: nil,
            platform: .other,
            originalUrl: sourceURL.absoluteString,
            webpageUrl: nil,
            uploadDate: nil,
            duration: duration,
            filePath: fileName,
            fileSize: fileSize,
            thumbnailPath: thumbnailPath,
            width: width,
            height: height,
            addedAt: Date(),
            status: .completed,
            errorMessage: nil
        )

        try videoRepo.insert(&video)
        return video.id
    }

    private func importImageFile(_ sourceURL: URL) async throws -> Int64? {
        let fileId = UUID().uuidString.lowercased()
        let ext = sourceURL.pathExtension.lowercased()
        let fileName = "\(fileId).\(ext)"
        let destURL = Constants.storageDir.appendingPathComponent(fileName)

        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Get dimensions via ImageIO (thread-safe, no decoding overhead)
        var width: Int?
        var height: Int?
        if let src = CGImageSourceCreateWithURL(destURL as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int
            height = props[kCGImagePropertyPixelHeight] as? Int
        }

        // Use the image itself as its thumbnail
        let thumbFileName = ".thumbnails/\(fileId).\(ext)"
        let thumbDir = Constants.storageDir.appendingPathComponent(".thumbnails")
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        let thumbURL = Constants.storageDir.appendingPathComponent(thumbFileName)
        try? FileManager.default.copyItem(at: destURL, to: thumbURL)

        let fileSize = byteSize(at: destURL)
        let title = sourceURL.deletingPathExtension().lastPathComponent

        var video = Video(
            ytdlpId: fileId,
            title: title.isEmpty ? fileName : title,
            description: nil,
            uploader: nil,
            uploaderUrl: nil,
            platform: .other,
            originalUrl: sourceURL.absoluteString,
            webpageUrl: nil,
            uploadDate: nil,
            duration: nil,
            filePath: fileName,
            fileSize: fileSize,
            thumbnailPath: thumbFileName,
            width: width,
            height: height,
            addedAt: Date(),
            status: .completed,
            errorMessage: nil
        )

        try videoRepo.insert(&video)
        return video.id
    }

    /// Import a PDF file. Uses CoreGraphics to render a JPEG thumbnail of page 1.
    private func importPDFFile(_ sourceURL: URL) throws -> Int64? {
        let fileId = UUID().uuidString.lowercased()
        let fileName = "\(fileId).pdf"
        let destURL = Constants.storageDir.appendingPathComponent(fileName)

        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Extract page count and first-page dimensions via CoreGraphics (thread-safe)
        var width: Int?
        var height: Int?
        var pageCount: Int?
        if let provider = CGDataProvider(url: destURL as CFURL),
           let pdfDoc = CGPDFDocument(provider) {
            pageCount = pdfDoc.numberOfPages
            if let page = pdfDoc.page(at: 1) { // CGPDFDocument is 1-indexed
                let box = page.getBoxRect(.cropBox)
                width = Int(box.width)
                height = Int(box.height)
            }
        }

        let thumbnailPath = generatePDFThumbnail(from: destURL, id: fileId)
        let fileSize = byteSize(at: destURL)
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let pagesDesc = pageCount.map { "\($0) page\($0 == 1 ? "" : "s")" }

        var video = Video(
            ytdlpId: fileId,
            title: title.isEmpty ? fileName : title,
            description: pagesDesc,
            uploader: nil,
            uploaderUrl: nil,
            platform: .other,
            originalUrl: sourceURL.absoluteString,
            webpageUrl: nil,
            uploadDate: nil,
            duration: nil,
            filePath: fileName,
            fileSize: fileSize,
            thumbnailPath: thumbnailPath,
            width: width,
            height: height,
            addedAt: Date(),
            status: .completed,
            errorMessage: nil
        )

        try videoRepo.insert(&video)
        return video.id
    }

    /// Renders the first page of a PDF to a JPEG thumbnail using CoreGraphics (no AppKit).
    private func generatePDFThumbnail(from url: URL, id: String) -> String? {
        guard let provider = CGDataProvider(url: url as CFURL),
              let pdfDoc = CGPDFDocument(provider),
              let page = pdfDoc.page(at: 1) else { return nil }

        let mediaBox = page.getBoxRect(.cropBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }

        let maxDim: CGFloat = 640
        let scale = min(maxDim / mediaBox.width, maxDim / mediaBox.height)
        let w = Int(ceil(mediaBox.width * scale))
        let h = Int(ceil(mediaBox.height * scale))

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        // White background
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Scale and render the PDF page
        ctx.scaleBy(x: CGFloat(w) / mediaBox.width, y: CGFloat(h) / mediaBox.height)
        ctx.drawPDFPage(page)

        guard let cgImage = ctx.makeImage() else { return nil }

        let thumbDir = Constants.storageDir.appendingPathComponent(".thumbnails")
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        let thumbFileName = ".thumbnails/\(id).jpg"
        let thumbURL = Constants.storageDir.appendingPathComponent(thumbFileName)

        guard let dest = CGImageDestinationCreateWithURL(
            thumbURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        CGImageDestinationAddImage(dest, cgImage, [
            kCGImageDestinationLossyCompressionQuality: 0.88
        ] as CFDictionary)

        return CGImageDestinationFinalize(dest) ? thumbFileName : nil
    }

    private func generateVideoThumbnail(from url: URL, id: String) async throws -> String {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        let (cgImage, _) = try await generator.image(at: .zero)

        let thumbDir = Constants.storageDir.appendingPathComponent(".thumbnails")
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)

        let thumbFileName = ".thumbnails/\(id).jpg"
        let thumbURL = Constants.storageDir.appendingPathComponent(thumbFileName)

        guard let dest = CGImageDestinationCreateWithURL(
            thumbURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1, nil
        ) else { throw NSError(domain: "FileImportService", code: 1) }

        CGImageDestinationAddImage(dest, cgImage, [
            kCGImageDestinationLossyCompressionQuality: 0.85
        ] as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "FileImportService", code: 2)
        }

        return thumbFileName
    }

    private func byteSize(at url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
    }
}
