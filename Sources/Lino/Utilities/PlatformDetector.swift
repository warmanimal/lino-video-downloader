import Foundation

enum PlatformDetector {
    static func detect(from urlString: String) -> Video.Platform {
        let lowered = urlString.lowercased()

        if lowered.contains("youtube.com") || lowered.contains("youtu.be") {
            return .youtube
        }
        if lowered.contains("tiktok.com") {
            return .tiktok
        }
        if lowered.contains("instagram.com") || lowered.contains("instagr.am") {
            return .instagram
        }
        if lowered.contains("twitter.com") || lowered.contains("x.com") {
            return .twitter
        }
        if lowered.contains("pinterest.com") || lowered.contains("pin.it") {
            return .pinterest
        }
        if lowered.contains("suno.com") {
            return .suno
        }

        return .other
    }

    static func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        guard let scheme = url.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }
}
