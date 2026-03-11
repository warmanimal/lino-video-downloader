import Foundation

/// Fetches Open Graph metadata from any web URL.
/// Used for saving article/page bookmarks without downloading media.
actor ArticleMetadataService {

    struct ArticleInfo {
        let title: String
        let description: String?
        let thumbnailURL: String?
        let siteName: String?
    }

    func fetchMetadata(url: String) async -> ArticleInfo {
        guard let urlObj = URL(string: url) else {
            return ArticleInfo(title: "Article", description: nil, thumbnailURL: nil, siteName: nil)
        }

        var request = URLRequest(url: urlObj)
        // Identify as a browser so sites return full HTML rather than a redirect
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
        else {
            return ArticleInfo(
                title: urlObj.host ?? "Article",
                description: nil, thumbnailURL: nil,
                siteName: urlObj.host
            )
        }

        let title = (ogContent(html, "og:title")
            ?? metaContent(html, "title")
            ?? htmlTitle(html)
            ?? urlObj.host
            ?? "Article"
        ).trimmingCharacters(in: .whitespacesAndNewlines).htmlDecoded

        let description = (ogContent(html, "og:description")
            ?? metaContent(html, "description")
        )?.trimmingCharacters(in: .whitespacesAndNewlines).htmlDecoded

        let thumbnailURL = ogContent(html, "og:image")

        let siteName = (ogContent(html, "og:site_name") ?? urlObj.host)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ArticleInfo(
            title: title,
            description: description,
            thumbnailURL: thumbnailURL,
            siteName: siteName
        )
    }

    // MARK: - Private HTML parsers

    private func ogContent(_ html: String, _ property: String) -> String? {
        extractMeta(html, attrName: "property", attrValue: property)
    }

    private func metaContent(_ html: String, _ name: String) -> String? {
        extractMeta(html, attrName: "name", attrValue: name)
    }

    /// Matches both attribute orderings: `attr content` and `content attr`.
    private func extractMeta(_ html: String, attrName: String, attrValue: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: attrValue)
        let patterns = [
            "<meta[^>]+\(attrName)=[\"']\(escaped)[\"'][^>]+content=[\"']([^\"'<>]+)[\"']",
            "<meta[^>]+content=[\"']([^\"'<>]+)[\"'][^>]+\(attrName)=[\"']\(escaped)[\"']",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html)
            else { continue }
            return String(html[range])
        }
        return nil
    }

    private func htmlTitle(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(
                  pattern: "<title[^>]*>([^<]+)</title>",
                  options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[range])
    }
}

private extension String {
    var htmlDecoded: String {
        self
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
