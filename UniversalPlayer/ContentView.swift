import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var playerViewModel = PlayerViewModel()
    @State private var showFilePicker = false
    @State private var showNetworkBrowser = false

    var body: some View {
        NavigationStack {
            VStack {
                if let url = playerViewModel.currentMediaURL {
                    PlayerView(viewModel: playerViewModel)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Universal Player")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showFilePicker = true }) {
                            Label("Lokale bestanden", systemImage: "folder")
                        }
                        Button(action: { showNetworkBrowser = true }) {
                            Label("Netwerkserver (SMB)", systemImage: "server.rack")
                        }
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker(onSelect: { url in
                    playerViewModel.loadMedia(url: url)
                })
            }
            .sheet(isPresented: $showNetworkBrowser) {
                SMBBrowserView(
                    onSelectMedia: { url in
                        playerViewModel.loadMedia(url: url)
                    },
                    onDismiss: {
                        showNetworkBrowser = false
                    }
                )
            }
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

            HStack(spacing: 16) {
                Button(action: { showFilePicker = true }) {
                    Label("Lokaal", systemImage: "folder")
                        .font(.headline)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button(action: { showNetworkBrowser = true }) {
                    Label("Netwerk", systemImage: "server.rack")
                        .font(.headline)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }

            Text("Ondersteunt: AVI, MKV, MP4, MOV, WMV, FLV\nInclusief DV en MS-Video codecs\n\nNetwerk: SMB/CIFS shares")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
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
