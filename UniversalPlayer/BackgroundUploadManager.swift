import Foundation
import SwiftUI
import UserNotifications
@preconcurrency import MobileVLCKit

@MainActor
class BackgroundUploadManager: ObservableObject {
    static let shared = BackgroundUploadManager()

    @Published var isUploading = false
    @Published var currentVideoTitle: String = ""
    @Published var overallProgress: Double = 0
    @Published var statusMessage: String = ""
    @Published var showCompletionAlert = false
    @Published var completionMessage: String = ""
    @Published var completionSuccess = false
    @Published var uploadedVideoId: String?

    private init() {
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func startUpload(url: URL, title: String, privacy: String) {
        guard !isUploading else { return }

        isUploading = true
        currentVideoTitle = title
        overallProgress = 0
        statusMessage = "Voorbereiden..."
        uploadedVideoId = nil

        Task {
            do {
                var fileToUpload = url
                let isSMBFile = url.scheme == "smb"

                // If SMB file, download first
                if isSMBFile {
                    statusMessage = "Downloaden van server..."
                    fileToUpload = try await downloadSMBFile(url: url)
                }

                // Upload to YouTube
                statusMessage = "Uploaden naar YouTube..."
                if !isSMBFile {
                    overallProgress = 0.1
                }

                let videoId = try await YouTubeService.shared.uploadVideo(
                    url: fileToUpload,
                    title: title,
                    description: "",
                    privacy: privacy
                )

                // Success!
                overallProgress = 1.0
                statusMessage = "Voltooid!"
                uploadedVideoId = videoId

                // Add to uploaded videos list
                UploadedVideosManager.shared.addVideo(id: videoId, title: title)

                // Clean up temp file if SMB
                if isSMBFile {
                    try? FileManager.default.removeItem(at: fileToUpload)
                }

                // Show completion
                completionSuccess = true
                completionMessage = "'\(title)' is succesvol geüpload naar YouTube!"
                showCompletionAlert = true

                // Send notification
                sendNotification(title: "Upload voltooid", body: "'\(title)' staat nu op YouTube")

                // Reset after delay
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                isUploading = false
                statusMessage = ""
                overallProgress = 0

            } catch {
                // Error
                completionSuccess = false
                completionMessage = "Upload mislukt: \(error.localizedDescription)"
                showCompletionAlert = true

                sendNotification(title: "Upload mislukt", body: error.localizedDescription)

                isUploading = false
                statusMessage = ""
                overallProgress = 0
            }
        }
    }

    private func downloadSMBFile(url: URL) async throws -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = url.lastPathComponent
        let localURL = documentsDir.appendingPathComponent("youtube_upload_\(fileName)")

        try? FileManager.default.removeItem(at: localURL)

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let media = VLCMedia(url: url)
                let player = VLCMediaPlayer()

                let escapedPath = localURL.path.replacingOccurrences(of: "'", with: "\\'")
                media.addOption(":sout=#file{dst='\(escapedPath)'}")
                media.addOption(":sout-all")
                media.addOption(":sout-keep")
                media.addOption(":no-video")
                media.addOption(":no-audio")

                player.media = media

                var isFinished = false
                var progressTimer: Timer?

                progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    if player.isPlaying {
                        let progress = Double(player.position)
                        Task { @MainActor in
                            self.overallProgress = min(0.49, progress * 0.5)
                        }
                    }
                }

                NotificationCenter.default.addObserver(forName: NSNotification.Name(VLCMediaPlayerStateChanged), object: player, queue: .main) { [weak self] _ in
                    let state = player.state

                    if state == .ended || state == .stopped {
                        if !isFinished {
                            isFinished = true
                            progressTimer?.invalidate()
                            player.stop()

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if FileManager.default.fileExists(atPath: localURL.path) {
                                    Task { @MainActor in
                                        self?.overallProgress = 0.5
                                        self?.statusMessage = "Uploaden naar YouTube..."
                                    }
                                    continuation.resume(returning: localURL)
                                } else {
                                    continuation.resume(throwing: NSError(domain: "Download", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bestand niet gevonden na download"]))
                                }
                            }
                        }
                    } else if state == .error {
                        if !isFinished {
                            isFinished = true
                            progressTimer?.invalidate()
                            player.stop()
                            continuation.resume(throwing: NSError(domain: "Download", code: -1, userInfo: [NSLocalizedDescriptionKey: "VLC fout bij downloaden"]))
                        }
                    }
                }

                player.play()

                DispatchQueue.main.asyncAfter(deadline: .now() + 1800) {
                    if !isFinished {
                        isFinished = true
                        progressTimer?.invalidate()
                        player.stop()
                        continuation.resume(throwing: NSError(domain: "Download", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download timeout"]))
                    }
                }
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
