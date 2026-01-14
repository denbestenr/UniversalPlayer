import Foundation
import UIKit
@preconcurrency import MobileVLCKit

/// Service die VLCKit gebruikt voor video playback
class VLCPlayerService: NSObject {
    private var mediaPlayer: VLCMediaPlayer
    private var media: VLCMedia?

    // Callback voor frame updates
    var onFrameUpdate: ((UIImage?) -> Void)?
    var onTimeUpdate: ((Double, Double) -> Void)?
    var onStateChange: ((VLCMediaPlayerState) -> Void)?

    // Properties
    var duration: Double {
        guard let media = media else { return 0 }
        return Double(media.length.intValue) / 1000.0
    }

    var currentTime: Double {
        return Double(mediaPlayer.time.intValue) / 1000.0
    }

    var isPlaying: Bool {
        return mediaPlayer.isPlaying
    }

    override init() {
        mediaPlayer = VLCMediaPlayer()
        super.init()
        mediaPlayer.delegate = self
    }

    func load(url: URL) {
        media = VLCMedia(url: url)
        mediaPlayer.media = media

        // Parse media om duration te krijgen
        media?.parse()
    }

    func setDrawable(_ view: UIView) {
        mediaPlayer.drawable = view
    }

    func play() {
        mediaPlayer.play()
    }

    func pause() {
        mediaPlayer.pause()
    }

    func stop() {
        mediaPlayer.stop()
        media = nil
    }

    func seek(to time: Double) {
        let position = Float(time / duration)
        mediaPlayer.position = max(0, min(1, position))
    }

    func seekToPosition(_ position: Float) {
        mediaPlayer.position = max(0, min(1, position))
    }
}

// MARK: - VLCMediaPlayerDelegate

extension VLCPlayerService: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        onStateChange?(mediaPlayer.state)
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        onTimeUpdate?(currentTime, duration)
    }
}
