import SwiftUI
import UIKit

struct UploadedVideosView: View {
    @ObservedObject var manager = UploadedVideosManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Group {
                if manager.videos.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary)

                        Text("Geen geüploade video's")
                            .font(.title)
                            .foregroundColor(.secondary)

                        Text("Video's die je uploadt naar YouTube\nverschijnen hier.")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(manager.videos) { video in
                            UploadedVideoRow(video: video)
                                .id("\(video.id)_\(video.processingStatus)")
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let url = video.youtubeURL {
                                        UIApplication.shared.open(url)
                                    }
                                }
                        }
                        .onDelete(perform: deleteVideos)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Geüploade Video's")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") {
                        dismiss()
                    }
                    .font(.title3)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: refreshStatuses) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                Task {
                    await manager.checkAllProcessingStatuses()
                }
            }
        }
    }

    private func deleteVideos(at offsets: IndexSet) {
        for index in offsets {
            manager.removeVideo(id: manager.videos[index].id)
        }
    }

    private func refreshStatuses() {
        Task {
            await manager.checkAllProcessingStatuses()
        }
    }
}

struct UploadedVideoRow: View {
    let video: UploadedVideo
    @State private var thumbnail: UIImage?
    @State private var lastLoadedStatus: String = ""

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail or hourglass
            ZStack {
                if video.isProcessing {
                    // Processing - show hourglass
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 90)

                    Image(systemName: "hourglass")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                } else if let thumbnail = thumbnail {
                    // Show thumbnail
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 90)
                        .cornerRadius(8)
                        .clipped()
                } else {
                    // Loading thumbnail
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 90)

                    ProgressView()
                }
            }
            .frame(width: 120, height: 90)

            // Video info
            VStack(alignment: .leading, spacing: 8) {
                Text(video.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                HStack {
                    if video.isProcessing {
                        Image(systemName: "hourglass")
                            .foregroundColor(.orange)
                        Text("Wordt verwerkt...")
                            .foregroundColor(.orange)
                    } else if video.isProcessed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Klaar")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Mislukt")
                            .foregroundColor(.red)
                    }
                }
                .font(.title3)

                Text(formatDate(video.uploadDate))
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Mail button
            Button(action: {
                sendEmail()
            }) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
            }
            .buttonStyle(BorderlessButtonStyle())
            .padding(.trailing, 8)

            // YouTube link indicator
            Image(systemName: "play.rectangle.fill")
                .font(.title)
                .foregroundColor(.red)
        }
        .padding(.vertical, 8)
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: video.processingStatus) { newStatus in
            // Reload thumbnail when status changes from processing to processed
            if newStatus == "processed" && thumbnail == nil {
                loadThumbnail()
            }
        }
    }

    private func sendEmail() {
        guard let youtubeURL = video.youtubeURL else { return }

        let subject = "Nieuwe video op YouTube gezet"
        let body = "Deze video heb ik voor je op YouTube gezet (verborgen), klik op de link: \(youtubeURL.absoluteString)"

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let mailURL = URL(string: "mailto:?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(mailURL)
        }
    }

    private func loadThumbnail() {
        guard !video.isProcessing, let url = video.thumbnailImageURL else { return }

        // Don't reload if we already loaded for this status
        guard lastLoadedStatus != video.processingStatus else { return }

        Task {
            do {
                // Use a cache-busting request to force reload
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData

                let (data, _) = try await URLSession.shared.data(for: request)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.thumbnail = image
                        self.lastLoadedStatus = video.processingStatus
                    }
                }
            } catch {
                print("Failed to load thumbnail: \(error)")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "nl_NL")
        return formatter.string(from: date)
    }
}

#Preview {
    UploadedVideosView()
}
