import SwiftUI
import AVKit

struct VideoPlayerView: NSViewRepresentable {
    let videoURL: URL

    private var isRemote: Bool {
        videoURL.scheme == "https" || videoURL.scheme == "http"
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        if isRemote || FileManager.default.fileExists(atPath: videoURL.path) {
            let player = AVPlayer(url: videoURL)
            view.player = player
            context.coordinator.observe(player: player)
            if isRemote { player.play() }
        }
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url,
           currentURL != videoURL {
            nsView.player?.pause()
            context.coordinator.stopObserving()
            if isRemote || FileManager.default.fileExists(atPath: videoURL.path) {
                let player = AVPlayer(url: videoURL)
                nsView.player = player
                context.coordinator.observe(player: player)
                if isRemote { player.play() }
            } else {
                nsView.player = nil
            }
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.stopObserving()
        nsView.player?.pause()
        nsView.player = nil
    }

    final class Coordinator {
        private var token: NSObjectProtocol?

        func observe(player: AVPlayer) {
            token = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        func stopObserving() {
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
            token = nil
        }
    }
}
