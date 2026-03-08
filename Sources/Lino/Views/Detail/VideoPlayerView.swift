import SwiftUI
import AVKit

struct VideoPlayerView: NSViewRepresentable {
    let videoURL: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        if FileManager.default.fileExists(atPath: videoURL.path) {
            view.player = AVPlayer(url: videoURL)
        }
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // If URL changed, update the player
        if let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url,
           currentURL != videoURL {
            nsView.player?.pause()
            if FileManager.default.fileExists(atPath: videoURL.path) {
                nsView.player = AVPlayer(url: videoURL)
            } else {
                nsView.player = nil
            }
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}
