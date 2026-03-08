import Foundation
import GRDB

struct Video: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var ytdlpId: String
    var title: String
    var description: String?
    var uploader: String?
    var uploaderUrl: String?
    var platform: Platform
    var originalUrl: String
    var webpageUrl: String?
    var uploadDate: String?
    var duration: Double?
    var filePath: String
    var fileSize: Int64?
    var thumbnailPath: String?
    var width: Int?
    var height: Int?
    var addedAt: Date
    var status: DownloadStatus
    var errorMessage: String?
    var deletedAt: Date?

    enum DownloadStatus: String, Codable, DatabaseValueConvertible, Sendable {
        case saved       // metadata saved, file not downloaded
        case pending
        case downloading
        case completed
        case failed
    }

    enum Platform: String, Codable, DatabaseValueConvertible, CaseIterable, Sendable {
        case youtube
        case tiktok
        case instagram
        case twitter
        case pinterest
        case other

        var displayName: String {
            switch self {
            case .youtube: return "YouTube"
            case .tiktok: return "TikTok"
            case .instagram: return "Instagram"
            case .twitter: return "X"
            case .pinterest: return "Pinterest"
            case .other: return "Other"
            }
        }

        var systemImage: String {
            switch self {
            case .youtube: return "play.rectangle.fill"
            case .tiktok: return "music.note"
            case .instagram: return "camera.fill"
            case .twitter: return "bubble.left.fill"
            case .pinterest: return "pin.fill"
            case .other: return "globe"
            }
        }
    }

    static let databaseTableName = "video"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var formattedDuration: String {
        guard let duration else { return "--:--" }
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        guard let fileSize else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var isDeleted: Bool { deletedAt != nil }

    var absoluteFilePath: URL {
        Constants.storageDir.appendingPathComponent(filePath)
    }

    var absoluteThumbnailPath: URL? {
        guard let thumbnailPath else { return nil }
        return Constants.storageDir.appendingPathComponent(thumbnailPath)
    }
}

extension Video {
    static let tags = hasMany(VideoTag.self)
    static let tagsThroughVideoTags = hasMany(Tag.self, through: tags, using: VideoTag.tag)
}
