import Foundation
import SwiftUI
import UserNotifications
import AMSMB2

// MARK: - Download Error Types

private enum SMBDownloadError: LocalizedError {
    case configuration(String)
    case stalled(String)
    case network(String)
    case insufficientDiskSpace(String)

    var errorDescription: String? {
        switch self {
        case .configuration(let msg): return msg
        case .stalled(let msg): return msg
        case .network(let msg): return msg
        case .insufficientDiskSpace(let msg): return msg
        }
    }

    var isConfiguration: Bool {
        if case .configuration = self { return true }
        return false
    }

    var isStalled: Bool {
        if case .stalled = self { return true }
        return false
    }
}

// MARK: - BackgroundUploadManager

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
    @Published var isRetrying = false
    @Published var retryAttempt = 0
    @Published var retryMaxAttempts = 0

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
                isRetrying = false
                statusMessage = ""
                overallProgress = 0

            } catch {
                // Error
                completionSuccess = false
                completionMessage = "Upload mislukt: \(error.localizedDescription)"
                showCompletionAlert = true

                sendNotification(title: "Upload mislukt", body: error.localizedDescription)

                isUploading = false
                isRetrying = false
                statusMessage = ""
                overallProgress = 0
            }
        }
    }

    private func downloadSMBFile(url: URL) async throws -> URL {
        let progressTracker = SendableProgressTracker()

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

        let maxRetries = 5
        retryMaxAttempts = maxRetries
        var lastError: Error?

        for attempt in 1...maxRetries {
            if attempt > 1 {
                progressTracker.reset()
                isRetrying = true
                retryAttempt = attempt

                // Backoff: 2s, 4s, 8s, 16s — max 30s; toon per seconde aftellen
                let delaySec = Int(min(30.0, pow(2.0, Double(attempt - 1))))
                for remaining in stride(from: delaySec, through: 1, by: -1) {
                    statusMessage = "Verbinding mislukt, opnieuw in \(remaining)s... (\(attempt)/\(maxRetries))"
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }

                isRetrying = false
                statusMessage = "Downloaden van server..."
            }

            do {
                return try await attemptSMBDownload(url: url, progressTracker: progressTracker)
            } catch let error as SMBDownloadError {
                if error.isConfiguration {
                    throw error
                }
                if error.isStalled {
                    statusMessage = error.localizedDescription
                }
                lastError = error
            } catch {
                lastError = error
            }
        }

        isRetrying = false
        let base = lastError?.localizedDescription ?? "onbekende fout"
        throw SMBDownloadError.network("SMB download mislukt na \(maxRetries) pogingen: \(base)")
    }

    private func attemptSMBDownload(url: URL, progressTracker: SendableProgressTracker) async throws -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = url.lastPathComponent
        let localURL = documentsDir.appendingPathComponent("youtube_upload_\(UUID().uuidString)_\(fileName)")

        // Parse SMB URL components
        guard let host = url.host, !host.isEmpty else {
            throw SMBDownloadError.configuration("Ongeldige SMB URL: geen hostnaam")
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else {
            throw SMBDownloadError.configuration("Ongeldige SMB URL: share of bestandspad ontbreekt")
        }

        let share = pathComponents[0]
        let filePath = pathComponents.dropFirst().joined(separator: "/")

        var serverURLString = "smb://\(host)"
        if let port = url.port { serverURLString += ":\(port)" }
        guard let serverURL = URL(string: serverURLString) else {
            throw SMBDownloadError.configuration("Kan server URL niet aanmaken")
        }

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
            throw SMBDownloadError.configuration("Kan SMB client niet initialiseren")
        }

        progressTracker.reset()
        progressTracker.resetStartTime()

        var connected = false
        defer {
            if connected { client.disconnectShare() }
        }

        // Verbinding met timeout van 20 seconden
        try await withSMBTimeout(seconds: 20, description: "verbinding met \(host)") {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.connectShare(name: share) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
        connected = true
        progressTracker.resetStartTime()

        // Check bestandsgrootte en schijfruimte vóór download
        let remoteSize = await fetchRemoteFileSize(client: client, atPath: filePath)
        if remoteSize > 0 {
            let freeSpace = availableDiskSpace()
            let buffer: Int64 = 200_000_000 // 200 MB marge
            if freeSpace < remoteSize + buffer {
                let needed = ByteCountFormatter.string(fromByteCount: remoteSize, countStyle: .file)
                let free = ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)
                throw SMBDownloadError.insufficientDiskSpace(
                    "Onvoldoende opslagruimte: \(needed) nodig, \(free) beschikbaar"
                )
            }
        }

        // Download met stall-detectie
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Download-taak
                group.addTask {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        client.downloadItem(atPath: filePath, to: localURL, progress: { bytes, total -> Bool in
                            progressTracker.update(bytes: bytes, total: total)
                            // Returning false cancels the AMSMB2 download cleanly
                            return !progressTracker.shouldCancel
                        }) { error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                }

                // Stall-detectie: als er 60 seconden geen bytes binnenkomen, annuleer
                group.addTask {
                    let checkInterval: Double = 10
                    let stallLimit: Double = 60
                    var lastBytes: Int64 = 0
                    var stalledSeconds: Double = 0

                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
                        let currentBytes = progressTracker.bytesDownloaded
                        if currentBytes > lastBytes {
                            lastBytes = currentBytes
                            stalledSeconds = 0
                        } else {
                            stalledSeconds += checkInterval
                            // Alleen reageren als de download al gestart is
                            if stalledSeconds >= stallLimit && lastBytes > 0 {
                                progressTracker.cancelDownload()
                                throw SMBDownloadError.stalled(
                                    "Download vastgelopen (\(Int(stallLimit))s geen voortgang). Opnieuw verbinden..."
                                )
                            }
                        }
                    }
                }

                // Wacht op de eerste die afrondt (download klaar of stall gedetecteerd)
                try await group.next()!
                group.cancelAll()
                // Drain geannuleerde taak, CancellationError negeren
                while let _ = try? await group.next() {}
            }
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            throw error
        }

        // Valideer gedownload bestand
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw SMBDownloadError.network("Bestand niet gevonden na download")
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0
        guard fileSize > 0 else {
            try? FileManager.default.removeItem(at: localURL)
            throw SMBDownloadError.network("Gedownload bestand is leeg (0 bytes)")
        }

        self.overallProgress = 0.5
        self.statusMessage = "Uploaden naar YouTube..."

        return localURL
    }

    // Ophalen bestandsgrootte van SMB server — niet-fataal, retourneert 0 bij fout
    private func fetchRemoteFileSize(client: AMSMB2, atPath path: String) async -> Int64 {
        await withCheckedContinuation { continuation in
            client.attributesOfItem(atPath: path) { result in
                let size: Int64
                if case .success(let attrs) = result {
                    size = (attrs[.fileSizeKey] as? NSNumber)?.int64Value ?? 0
                } else {
                    size = 0
                }
                continuation.resume(returning: size)
            }
        }
    }

    private func availableDiskSpace() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64 else {
            return Int64.max
        }
        return free
    }

    private func withSMBTimeout<T>(seconds: Double, description: String, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "Download", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "Time-out bij \(description) (>\(Int(seconds))s). Controleer de netwerkverbinding."])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
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
    private var _shouldCancel: Bool = false

    var shouldCancel: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _shouldCancel
    }

    func cancelDownload() {
        lock.lock()
        _shouldCancel = true
        lock.unlock()
    }

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

    func reset() {
        lock.lock()
        _progress = 0
        _bytesDownloaded = 0
        _totalBytes = 0
        _startTime = Date()
        _shouldCancel = false
        lock.unlock()
    }
}
