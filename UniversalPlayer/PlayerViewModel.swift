import SwiftUI
import Combine
@preconcurrency import MobileVLCKit

enum PlaybackState {
    case idle
    case loading
    case playing
    case paused
    case error(String)
}

@MainActor
class PlayerViewModel: ObservableObject {
    @Published var currentMediaURL: URL?
    @Published var playbackState: PlaybackState = .idle
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    private var playerService: VLCPlayerService?

    var isPlaying: Bool {
        if case .playing = playbackState { return true }
        return false
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var currentTimeFormatted: String {
        formatTime(currentTime)
    }

    var durationFormatted: String {
        formatTime(duration)
    }

    func loadMedia(url: URL) {
        stop()

        currentMediaURL = url
        playbackState = .loading

        playerService = VLCPlayerService()

        playerService?.onTimeUpdate = { [weak self] time, dur in
            Task { @MainActor in
                self?.currentTime = time
                if dur > 0 {
                    self?.duration = dur
                }
            }
        }

        playerService?.onStateChange = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .playing:
                    self?.playbackState = .playing
                case .paused, .stopped:
                    self?.playbackState = .paused
                case .error:
                    self?.playbackState = .error("Playback error")
                default:
                    break
                }
            }
        }

        playerService?.load(url: url)
        playbackState = .paused
    }

    func setDrawable(_ view: UIView) {
        playerService?.setDrawable(view)
    }

    func play() {
        playerService?.play()
        playbackState = .playing
    }

    func pause() {
        playerService?.pause()
        playbackState = .paused
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to progress: Double) {
        playerService?.seekToPosition(Float(progress))
        currentTime = progress * duration
    }

    func stop() {
        playerService?.stop()
        playerService = nil
        // Only stop security-scoped access for local files, not network URLs
        if let url = currentMediaURL, url.scheme == "file" {
            url.stopAccessingSecurityScopedResource()
        }
        currentMediaURL = nil
        playbackState = .idle
        currentTime = 0
        duration = 0
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
