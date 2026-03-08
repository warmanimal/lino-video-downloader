import Testing
@testable import Lino

@Suite("PlatformDetector")
struct PlatformDetectorTests {
    @Test func detectsYouTube() {
        #expect(PlatformDetector.detect(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") == .youtube)
        #expect(PlatformDetector.detect(from: "https://youtu.be/dQw4w9WgXcQ") == .youtube)
    }

    @Test func detectsTikTok() {
        #expect(PlatformDetector.detect(from: "https://www.tiktok.com/@user/video/1234") == .tiktok)
    }

    @Test func detectsInstagram() {
        #expect(PlatformDetector.detect(from: "https://www.instagram.com/reel/ABC123") == .instagram)
    }

    @Test func detectsTwitter() {
        #expect(PlatformDetector.detect(from: "https://twitter.com/user/status/1234") == .twitter)
        #expect(PlatformDetector.detect(from: "https://x.com/user/status/1234") == .twitter)
    }

    @Test func detectsPinterest() {
        #expect(PlatformDetector.detect(from: "https://www.pinterest.com/pin/1234") == .pinterest)
        #expect(PlatformDetector.detect(from: "https://pin.it/abc123") == .pinterest)
    }

    @Test func detectsOther() {
        #expect(PlatformDetector.detect(from: "https://www.example.com/video") == .other)
    }

    @Test func validatesURLs() {
        #expect(PlatformDetector.isValidURL("https://www.youtube.com/watch?v=abc"))
        #expect(PlatformDetector.isValidURL("http://example.com"))
        #expect(!PlatformDetector.isValidURL("not a url"))
        #expect(!PlatformDetector.isValidURL("ftp://example.com"))
    }
}
