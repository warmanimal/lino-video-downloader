import SwiftUI
import AVKit

struct VideoPlayerView: NSViewRepresentable {
    let videoURL: URL

    private var isRemote: Bool {
        videoURL.scheme == "https" || videoURL.scheme == "http"
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        if isRemote || FileManager.default.fileExists(atPath: videoURL.path) {
            let player = AVPlayer(url: videoURL)
            view.player = player
            if isRemote { player.play() }
        }
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url,
           currentURL != videoURL {
            nsView.player?.pause()
            if isRemote || FileManager.default.fileExists(atPath: videoURL.path) {
                let player = AVPlayer(url: videoURL)
                nsView.player = player
                if isRemote { player.play() }
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
