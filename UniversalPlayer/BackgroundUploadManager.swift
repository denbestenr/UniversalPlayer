import Foundation
import SwiftUI
import UserNotifications
import AMSMB2

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
    @Published var downloadTotalBytes: Int64 = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var downloadSpeedBytesPerSec: Double = 0
    @Published var isDownloadingFromSMB = false
    @Published var uploadTotalBytes: Int64 = 0
    @Published var uploadedBytes: Int64 = 0
    @Published var uploadStartTime: Date?

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
                    isDownloadingFromSMB = true
                    downloadTotalBytes = 0
                    downloadedBytes = 0
                    downloadSpeedBytesPerSec = 0
                    fileToUpload = try await downloadSMBFile(url: url)
                    isDownloadingFromSMB = false
                }

                // Upload to YouTube
                statusMessage = "Uploaden naar YouTube..."
                uploadTotalBytes = 0
                uploadedBytes = 0
                uploadStartTime = Date()
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

        // Parse SMB URL components
        guard let host = url.host, !host.isEmpty else {
            throw NSError(domain: "Download", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Ongeldige SMB URL: geen hostnaam"])
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else {
            throw NSError(domain: "Download", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Ongeldige SMB URL: share of bestandspad ontbreekt"])
        }

        let share = pathComponents[0]
        let filePath = pathComponents.dropFirst().joined(separator: "/")

        // Build server URL
        var serverURLString = "smb://\(host)"
        if let port = url.port { serverURLString += ":\(port)" }
        guard let serverURL = URL(string: serverURLString) else {
            throw NSError(domain: "Download", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Kan server URL niet aanmaken"])
        }

        // Load credentials from Keychain
        let credential: URLCredential
        if let user = url.user, !user.isEmpty {
            credential = URLCredential(user: user, password: url.password ?? "", persistence: .forSession)
        } else if let creds = KeychainService.shared.loadCredentials(for: "\(host)/\(share)"),
                  !creds.username.isEmpty {
            credential = URLCredential(user: creds.username, password: creds.password, persistence: .forSession)
        } else {
            credential = URLCredential(user: "guest", password: "", persistence: .forSession)
        }

        guard let client = AMSMB2(url: serverURL, domain: "WORKGROUP", credential: credential) else {
            throw NSError(domain: "Download", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Kan SMB client niet initialiseren"])
        }

        let progressTracker = SendableProgressTracker()

        progressTracker.resetStartTime()

        let progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self = self else { break }
                self.overallProgress = min(0.49, progressTracker.progress * 0.5)
                self.downloadedBytes = progressTracker.bytesDownloaded
                self.downloadTotalBytes = progressTracker.totalBytes
                self.downloadSpeedBytesPerSec = progressTracker.bytesPerSecond
            }
        }

        defer { progressTask.cancel() }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.connectShare(name: share) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            progressTracker.resetStartTime()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.downloadItem(atPath: filePath, to: localURL, progress: { bytes, total -> Bool in
                    progressTracker.update(bytes: bytes, total: total)
                    return true
                }) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            client.disconnectShare()

            guard FileManager.default.fileExists(atPath: localURL.path) else {
                throw NSError(domain: "Download", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Bestand niet gevonden na download"])
            }

            self.overallProgress = 0.5
            self.statusMessage = "Uploaden naar YouTube..."

            return localURL

        } catch {
            client.disconnectShare()
            try? FileManager.default.removeItem(at: localURL)
            throw NSError(domain: "Download", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "SMB download mislukt: \(error.localizedDescription)"])
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

private final class SendableProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _progress: Double = 0
    private var _bytesDownloaded: Int64 = 0
    private var _totalBytes: Int64 = 0
    private var _startTime: Date = Date()

    var progress: Double {
        lock.lock()
        defer { lock.unlock() }
        return _progress
    }

    var bytesDownloaded: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _bytesDownloaded
    }

    var totalBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _totalBytes
    }

    var bytesPerSecond: Double {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = Date().timeIntervalSince(_startTime)
        guard elapsed > 0 else { return 0 }
        return Double(_bytesDownloaded) / elapsed
    }

    func update(bytes: Int64, total: Int64) {
        lock.lock()
        _bytesDownloaded = bytes
        _totalBytes = total
        _progress = total > 0 ? Double(bytes) / Double(total) : 0
        lock.unlock()
    }

    func resetStartTime() {
        lock.lock()
        _startTime = Date()
        lock.unlock()
    }
}
