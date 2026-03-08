import Foundation

struct YtDlpMetadata: Codable, Sendable {
    let id: String
    let title: String?
    let description: String?
    let uploader: String?
    let uploaderUrl: String?
    let webpageUrl: String?
    let originalUrl: String?
    let uploadDate: String?
    let duration: Double?
    let thumbnail: String?
    let width: Int?
    let height: Int?
    let ext: String?
    let filesize: Int64?
    let filesizeApprox: Int64?

    enum CodingKeys: String, CodingKey {
        case id, title, description, uploader, duration, thumbnail, width, height, ext, filesize
        case uploaderUrl = "uploader_url"
        case webpageUrl = "webpage_url"
        case originalUrl = "original_url"
        case uploadDate = "upload_date"
        case filesizeApprox = "filesize_approx"
    }

    var effectiveFileSize: Int64? {
        filesize ?? filesizeApprox
    }
}
