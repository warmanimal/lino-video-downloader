import Foundation

actor FaviconService {
    static let shared = FaviconService()
    private init() {}

    /// Fetches a favicon for the given URL string.
    /// Tries Google's favicon service first, then falls back to /favicon.ico.
    func fetchFavicon(for urlString: String) async -> Data? {
        var normalized = urlString.trimmingCharacters(in: .whitespaces)
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        guard let url = URL(string: normalized), let host = url.host else { return nil }

        // 1. Google's favicon service — reliable, returns 64px icons
        let googleStr = "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
        if let googleURL = URL(string: googleStr),
           let data = await fetch(googleURL),
           isValidImage(data) {
            return data
        }

        // 2. Direct /favicon.ico fallback
        let scheme = url.scheme ?? "https"
        if let icoURL = URL(string: "\(scheme)://\(host)/favicon.ico"),
           let data = await fetch(icoURL),
           isValidImage(data) {
            return data
        }

        return nil
    }

    // MARK: - Private helpers

    private func fetch(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Validates that the data looks like a real image by checking magic bytes.
    private func isValidImage(_ data: Data) -> Bool {
        guard data.count > 64 else { return false }
        let bytes = Array(data.prefix(8))
        let isPNG  = bytes.starts(with: [0x89, 0x50, 0x4E, 0x47] as [UInt8])
        let isJPEG = bytes.starts(with: [0xFF, 0xD8] as [UInt8])
        let isGIF  = bytes.starts(with: [0x47, 0x49, 0x46] as [UInt8])
        let isICO  = bytes.starts(with: [0x00, 0x00, 0x01, 0x00] as [UInt8])
        let isWebP = bytes.starts(with: [0x52, 0x49, 0x46, 0x46] as [UInt8]) // "RIFF"
        return isPNG || isJPEG || isGIF || isICO || isWebP
    }
}
