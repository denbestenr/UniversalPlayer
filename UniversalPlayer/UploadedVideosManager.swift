import Foundation
import SwiftUI

struct UploadedVideo: Identifiable, Codable {
    let id: String // YouTube video ID
    let title: String
    let uploadDate: Date
    var thumbnailURL: String?
    var processingStatus: String // "processing", "processed", "failed"

    var youtubeURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    var thumbnailImageURL: URL? {
        // YouTube thumbnail URL format
        URL(string: "https://img.youtube.com/vi/\(id)/mqdefault.jpg")
    }

    var isProcessing: Bool {
        processingStatus == "processing"
    }

    var isProcessed: Bool {
        processingStatus == "processed"
    }
}

@MainActor
class UploadedVideosManager: ObservableObject {
    static let shared = UploadedVideosManager()

    @Published var videos: [UploadedVideo] = []

    private let storageKey = "uploaded_youtube_videos"

    private init() {
        loadVideos()
    }

    func addVideo(id: String, title: String) {
        let video = UploadedVideo(
            id: id,
            title: title,
            uploadDate: Date(),
            thumbnailURL: nil,
            processingStatus: "processing"
        )
        videos.insert(video, at: 0)
        saveVideos()

        // Check processing status after a delay
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // Wait 10 seconds
            await checkProcessingStatus(for: id)
        }
    }

    func removeVideo(id: String) {
        videos.removeAll { $0.id == id }
        saveVideos()
    }

    func checkAllProcessingStatuses() async {
        for video in videos where video.isProcessing {
            await checkProcessingStatus(for: video.id)
        }
    }

    func checkProcessingStatus(for videoId: String) async {
        do {
            let status = try await YouTubeService.shared.getVideoStatus(videoId: videoId)
            if let index = videos.firstIndex(where: { $0.id == videoId }) {
                videos[index].processingStatus = status.rawValue
                saveVideos()
            }
        } catch {
            print("Failed to check processing status: \(error)")
        }
    }

    private func loadVideos() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([UploadedVideo].self, from: data) else {
            return
        }
        videos = decoded
    }

    private func saveVideos() {
        guard let encoded = try? JSONEncoder().encode(videos) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
}
