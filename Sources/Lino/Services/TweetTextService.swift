import Foundation

/// Fetches metadata for text-only Twitter/X posts that yt-dlp cannot download.
/// Uses Twitter's free, unauthenticated oEmbed API.
actor TweetTextService {

    struct TweetInfo {
        let id: String
        let text: String
        let authorName: String?
        let authorUrl: String?
    }

    // MARK: - Public API

    /// Fetch tweet text and author info via the oEmbed API.
    /// Falls back gracefully to URL-derived info if the network call fails.
    func fetchTweet(url: String) async -> TweetInfo {
        let id = extractTweetId(from: url) ?? UUID().uuidString

        guard let oembedURL = buildOEmbedURL(for: url) else {
            return TweetInfo(id: id, text: "Tweet", authorName: nil, authorUrl: nil)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: oembedURL)
            let json = try JSONDecoder().decode(OEmbedResponse.self, from: data)
            let text = extractText(from: json.html)
            return TweetInfo(
                id: id,
                text: text.isEmpty ? "Tweet" : text,
                authorName: json.authorName,
                authorUrl: json.authorUrl
            )
        } catch {
            print("[TweetTextService] oEmbed fetch failed: \(error)")
            return TweetInfo(id: id, text: "Tweet", authorName: nil, authorUrl: nil)
        }
    }

    // MARK: - Private helpers

    private struct OEmbedResponse: Decodable {
        let html: String
        let authorName: String?
        let authorUrl: String?

        enum CodingKeys: String, CodingKey {
            case html
            case authorName = "author_name"
            case authorUrl  = "author_url"
        }
    }

    private func buildOEmbedURL(for tweetURL: String) -> URL? {
        var components = URLComponents(string: "https://publish.twitter.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "url", value: tweetURL),
            URLQueryItem(name: "omit_script", value: "true"),
        ]
        return components?.url
    }

    /// Extracts the visible tweet text from the oEmbed HTML snippet.
    ///
    /// oEmbed HTML shape:
    /// `<blockquote …><p lang="en">Tweet text <a href="…">link</a></p>&mdash; Name …</blockquote>`
    private func extractText(from html: String) -> String {
        // 1. Grab content inside the first <p …>…</p>
        guard let pStart = html.range(of: "<p", options: .caseInsensitive),
              let pTagEnd = html.range(of: ">", range: pStart.upperBound..<html.endIndex),
              let pClose = html.range(of: "</p>", options: .caseInsensitive,
                                      range: pTagEnd.upperBound..<html.endIndex)
        else { return stripTags(html) }

        let inner = String(html[pTagEnd.upperBound..<pClose.lowerBound])
        return stripTags(inner)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;",  with: "<")
            .replacingOccurrences(of: "&gt;",  with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips all `<…>` HTML tags from a string using a simple regex.
    private func stripTags(_ html: String) -> String {
        (try? html.replacing(#/<[^>]+>/#, with: "")) ?? html
    }

    /// Extracts the numeric tweet ID from a twitter.com or x.com status URL.
    private func extractTweetId(from url: String) -> String? {
        guard let match = url.firstMatch(of: #/\/status\/(\d+)/#) else { return nil }
        return String(match.1)
    }
}
