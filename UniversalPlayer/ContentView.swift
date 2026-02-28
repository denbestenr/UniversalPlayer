import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var playerViewModel = PlayerViewModel()
    @ObservedObject var uploadManager = BackgroundUploadManager.shared
    @State private var showFilePicker = false
    @State private var showNetworkBrowser = false
    @State private var showPlayer = false
    @State private var showSettings = false
    @State private var showUploadedVideos = false

    var body: some View {
        NavigationView {
            ZStack {
                emptyStateView

                // Upload progress overlay
                if uploadManager.isUploading {
                    uploadProgressView
                }
            }
            .navigationTitle("Universal Player")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker(onSelect: { url in
                    playerViewModel.loadMedia(url: url)
                    showPlayer = true
                })
            }
            .fullScreenCover(isPresented: $showNetworkBrowser) {
                SMBBrowserView(
                    showDiscovery: false,
                    onSelectMedia: { url in
                        playerViewModel.loadMedia(url: url)
                        showNetworkBrowser = false
                        showPlayer = true
                    },
                    onDismiss: {
                        showNetworkBrowser = false
                    }
                )
            }
            .fullScreenCover(isPresented: $showPlayer) {
                FullscreenPlayerView(viewModel: playerViewModel, onClose: {
                    playerViewModel.stop()
                    showPlayer = false
                })
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    onOpenLocalFiles: {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showFilePicker = true
                        }
                    },
                    onOpenNetworkBrowser: {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showNetworkBrowser = true
                        }
                    }
                )
            }
            .sheet(isPresented: $showUploadedVideos) {
                UploadedVideosView()
            }
            .alert(uploadManager.completionSuccess ? "Upload Geslaagd!" : "Upload Mislukt", isPresented: $uploadManager.showCompletionAlert) {
                Button("OK") {}
                if uploadManager.completionSuccess, let videoId = uploadManager.uploadedVideoId {
                    Button("Bekijk op YouTube") {
                        if let url = URL(string: "https://youtube.com/watch?v=\(videoId)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } message: {
                Text(uploadManager.completionMessage)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Upload Progress View

    private var uploadProgressView: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(uploadManager.statusMessage)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(uploadManager.currentVideoTitle)
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if uploadManager.isDownloadingFromSMB && uploadManager.downloadTotalBytes > 0 {
                            HStack(spacing: 12) {
                                Text(formatFileSize(uploadManager.downloadTotalBytes))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if uploadManager.downloadSpeedBytesPerSec > 0 {
                                    Text(formatSpeed(uploadManager.downloadSpeedBytesPerSec))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else if !uploadManager.isDownloadingFromSMB && uploadManager.uploadTotalBytes > 0 {
                            HStack(spacing: 12) {
                                Text(formatFileSize(uploadManager.uploadTotalBytes))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let startTime = uploadManager.uploadStartTime, uploadManager.uploadedBytes > 0 {
                                    let elapsed = Date().timeIntervalSince(startTime)
                                    if elapsed > 0 {
                                        Text(formatSpeed(Double(uploadManager.uploadedBytes) / elapsed))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Spacer()

                    Text("\(Int(uploadManager.overallProgress * 100))%")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.blue)
                }

                ProgressView(value: uploadManager.overallProgress)
                    .scaleEffect(y: 2)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 10)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
        } else {
            return String(format: "%.0f MB", Double(bytes) / 1_048_576.0)
        }
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            Text("Geen video geselecteerd")
                .font(.title2)
                .foregroundColor(.secondary)

            Button(action: { showNetworkBrowser = true }) {
                Label("Film selecteren", systemImage: "server.rack")
                    .font(.title2.bold())
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }

            Button(action: { showFilePicker = true }) {
                Label("Lokaal", systemImage: "folder")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Text("Ondersteunt: AVI, MKV, MP4, MOV, WMV, FLV\nInclusief DV en MS-Video codecs\n\nNetwerk: Apple en Windows")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showUploadedVideos = true }) {
                Label("YouTube video's", systemImage: "film.stack")
                    .font(.title2.bold())
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
        }
        .padding()
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            .avi,
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
            UTType(filenameExtension: "mkv") ?? .movie,
            UTType(filenameExtension: "wmv") ?? .movie,
            UTType(filenameExtension: "flv") ?? .movie,
            UTType(filenameExtension: "webm") ?? .movie
        ]

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            // Start security-scoped access
            guard url.startAccessingSecurityScopedResource() else { return }

            onSelect(url)
        }
    }
}

#Preview {
    ContentView()
}
