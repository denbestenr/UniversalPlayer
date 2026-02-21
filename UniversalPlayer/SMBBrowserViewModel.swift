import Foundation
import SwiftUI
@preconcurrency import MobileVLCKit

struct SMBItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    let media: VLCMedia
}

@MainActor
class SMBBrowserViewModel: ObservableObject {
    @Published var items: [SMBItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var currentPath: String = ""
    @Published var pathComponents: [String] = []

    private var currentServer: SMBServer?
    private var currentMedia: VLCMedia?
    private var mediaListDelegate: MediaListObserver?

    func browse(server: SMBServer, path: String = "") {
        currentServer = server
        currentPath = path
        pathComponents = path.isEmpty ? [] : path.components(separatedBy: "/").filter { !$0.isEmpty }

        guard let url = server.urlForPath(path) else {
            error = "Ongeldige URL"
            return
        }

        loadDirectory(url: url)
    }

    func navigateToSubfolder(_ item: SMBItem) {
        guard let server = currentServer, item.isDirectory else { return }

        let newPath: String
        if currentPath.isEmpty {
            newPath = item.name
        } else {
            newPath = "\(currentPath)/\(item.name)"
        }

        browse(server: server, path: newPath)
    }

    func navigateUp() {
        guard let server = currentServer, !pathComponents.isEmpty else { return }

        var components = pathComponents
        components.removeLast()
        let newPath = components.joined(separator: "/")

        browse(server: server, path: newPath)
    }

    func navigateToRoot() {
        guard let server = currentServer else { return }
        browse(server: server, path: "")
    }

    private func loadDirectory(url: URL) {
        isLoading = true
        error = nil
        items = []

        let media = VLCMedia(url: url)
        currentMedia = media

        // Create observer for media list updates
        let observer = MediaListObserver { [weak self] in
            Task { @MainActor in
                self?.processMediaList()
            }
        }
        mediaListDelegate = observer

        // Parse the directory to get subitems
        let options = VLCMediaParsingOptions.parseNetwork.rawValue | VLCMediaParsingOptions.fetchNetwork.rawValue
        _ = media.parse(options: VLCMediaParsingOptions(rawValue: options), timeout: 10000)

        // Set up a timer to check for results
        Task {
            // Wait for parsing
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            await MainActor.run {
                self.processMediaList()
            }
        }
    }

    private func processMediaList() {
        guard let media = currentMedia else {
            isLoading = false
            return
        }

        var newItems: [SMBItem] = []

        if let subitems = media.subitems {
            subitems.lock()
            let count = subitems.count
            for i in 0..<count {
                if let item = subitems.media(at: UInt(i)),
                   let url = item.url {
                    let name = url.lastPathComponent
                    let isDirectory = item.mediaType == .directory

                    // Filter out hidden files
                    if !name.hasPrefix(".") {
                        newItems.append(SMBItem(
                            name: name,
                            url: url,
                            isDirectory: isDirectory,
                            media: item
                        ))
                    }
                }
            }
            subitems.unlock()
        }

        // Sort: directories first, then by name
        newItems.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        items = newItems
        isLoading = false

        if items.isEmpty && error == nil {
            // Check if we got any results
            if media.parsedStatus == .failed {
                error = "Kan map niet openen. Controleer de inloggegevens."
            }
        }
    }

    func isVideoFile(_ item: SMBItem) -> Bool {
        let videoExtensions = ["avi", "mkv", "mp4", "mov", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "ts", "vob"]
        let ext = item.url.pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }

    func isImageFile(_ item: SMBItem) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp"]
        let ext = item.url.pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    var imageFiles: [SMBItem] {
        items.filter { isImageFile($0) }
    }

    func indexOfImage(_ item: SMBItem) -> Int? {
        imageFiles.firstIndex(where: { $0.id == item.id })
    }
}

// Helper class to observe VLCMediaList changes
private class MediaListObserver: NSObject, VLCMediaListDelegate {
    let onUpdate: () -> Void

    init(onUpdate: @escaping () -> Void) {
        self.onUpdate = onUpdate
        super.init()
    }

    func mediaList(_ aMediaList: VLCMediaList, mediaAdded media: VLCMedia, at index: UInt) {
        onUpdate()
    }

    func mediaList(_ aMediaList: VLCMediaList, mediaRemovedAt index: UInt) {
        onUpdate()
    }
}
