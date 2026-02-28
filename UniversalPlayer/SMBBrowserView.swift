import SwiftUI
@preconcurrency import MobileVLCKit

struct SMBBrowserView: View {
    @StateObject private var serverStorage = SMBServerStorage()
    @StateObject private var browserViewModel = SMBBrowserViewModel()
    @StateObject private var networkScanner = SMBNetworkScanner()
    @State private var showAddServer = false
    @State private var selectedServer: SMBServer?
    @State private var isConnected = false
    @State private var selectedDiscoveredServer: DiscoveredServer?
    @State private var showImageViewer = false
    @State private var selectedImageIndex: Int = 0

    var showDiscovery: Bool = true
    let onSelectMedia: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            Group {
                if isConnected {
                    fileBrowserView
                } else {
                    serverListView
                }
            }
            .navigationTitle(isConnected ? (selectedServer?.name ?? "Browser") : "Netwerkservers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isConnected {
                        Button("Servers") {
                            disconnect()
                        }
                    } else {
                        Button("Annuleer") {
                            onDismiss()
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if !isConnected {
                        Button(action: { showAddServer = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddServer) {
                AddServerView(serverStorage: serverStorage)
            }
            .sheet(item: $selectedDiscoveredServer) { discovered in
                SharePickerView(
                    discoveredServer: discovered,
                    serverStorage: serverStorage,
                    onDismiss: {
                        selectedDiscoveredServer = nil
                    }
                )
            }
            .fullScreenCover(isPresented: $showImageViewer) {
                FullscreenImageViewer(
                    images: browserViewModel.imageFiles,
                    currentIndex: $selectedImageIndex,
                    onClose: {
                        showImageViewer = false
                    }
                )
            }
            .onAppear {
                if !isConnected && showDiscovery {
                    networkScanner.startScan()
                }
            }
            .onDisappear {
                networkScanner.stopScan()
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Server List View

    private var serverListView: some View {
        List {
            // Discovered servers section
            if showDiscovery {
                Section {
                    if networkScanner.isScanning {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Scannen naar servers...")
                                .foregroundColor(.secondary)
                        }
                    } else if networkScanner.discoveredServers.isEmpty {
                        HStack {
                            Image(systemName: "wifi.exclamationmark")
                                .foregroundColor(.secondary)
                            Text(networkScanner.scanError ?? "Geen servers gevonden")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: { networkScanner.startScan() }) {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    } else {
                        ForEach(networkScanner.discoveredServers) { server in
                            DiscoveredServerRowView(server: server) {
                                selectedDiscoveredServer = server
                            }
                        }

                        Button(action: { networkScanner.startScan() }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Opnieuw scannen")
                            }
                            .foregroundColor(.accentColor)
                        }
                    }
                } header: {
                    Text("Gevonden op netwerk")
                }
            }

            // Saved servers section
            if !serverStorage.servers.isEmpty {
                Section {
                    ForEach(serverStorage.servers) { server in
                        ServerRowView(server: server) {
                            connect(to: server)
                        }
                    }
                    .onDelete(perform: showDiscovery ? deleteServers : nil)
                } header: {
                    if showDiscovery {
                        Text("Opgeslagen servers")
                    }
                }
            }
        }
    }

    // MARK: - File Browser View

    private var fileBrowserView: some View {
        VStack(spacing: 0) {
            // Breadcrumb navigation
            breadcrumbView

            // File list
            if browserViewModel.isLoading {
                Spacer()
                ProgressView("Laden...")
                Spacer()
            } else if let error = browserViewModel.error {
                Spacer()
                errorView(message: error)
                Spacer()
            } else if browserViewModel.items.isEmpty {
                Spacer()
                Text("Map is leeg")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(browserViewModel.items) { item in
                    FileRowView(item: item) {
                        handleItemTap(item)
                    }
                }
            }
        }
    }

    private var breadcrumbView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(action: { browserViewModel.navigateToRoot() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "house")
                        Text(selectedServer?.share ?? "Root")
                    }
                    .foregroundColor(.accentColor)
                }

                ForEach(Array(browserViewModel.pathComponents.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: {
                        navigateToPathIndex(index)
                    }) {
                        Text(component)
                            .foregroundColor(index == browserViewModel.pathComponents.count - 1 ? .primary : .accentColor)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("Fout")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Opnieuw proberen") {
                if let server = selectedServer {
                    browserViewModel.browse(server: server, path: browserViewModel.currentPath)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func connect(to server: SMBServer) {
        selectedServer = server
        isConnected = true
        browserViewModel.browse(server: server)
    }

    private func disconnect() {
        selectedServer = nil
        isConnected = false
    }

    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            serverStorage.removeServer(serverStorage.servers[index])
        }
    }

    private func handleItemTap(_ item: SMBItem) {
        if item.isDirectory {
            browserViewModel.navigateToSubfolder(item)
        } else if browserViewModel.isVideoFile(item) {
            onSelectMedia(item.url)
            onDismiss()
        } else if browserViewModel.isImageFile(item) {
            if let index = browserViewModel.indexOfImage(item) {
                selectedImageIndex = index
                showImageViewer = true
            }
        }
    }

    private func navigateToPathIndex(_ index: Int) {
        guard let server = selectedServer else { return }
        let path = browserViewModel.pathComponents.prefix(index + 1).joined(separator: "/")
        browserViewModel.browse(server: server, path: path)
    }
}

// MARK: - Discovered Server Row View

struct DiscoveredServerRowView: View {
    let server: DiscoveredServer
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(server.hostname)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .foregroundColor(.accentColor)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Server Row View

struct ServerRowView: View {
    let server: SMBServer
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(server.hostname)/\(server.share)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let item: SMBItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 40)

                Text(item.name)
                    .foregroundColor(.primary)

                Spacer()

                if item.isDirectory {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var iconName: String {
        if item.isDirectory {
            return "folder.fill"
        }
        let ext = item.url.pathExtension.lowercased()
        let videoExtensions = ["avi", "mkv", "mp4", "mov", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "ts", "vob"]
        if videoExtensions.contains(ext) {
            return "film"
        }
        return "doc"
    }

    private var iconColor: Color {
        if item.isDirectory {
            return .blue
        }
        let ext = item.url.pathExtension.lowercased()
        let videoExtensions = ["avi", "mkv", "mp4", "mov", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "ts", "vob"]
        if videoExtensions.contains(ext) {
            return .purple
        }
        return .gray
    }
}

// MARK: - Add Server View

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var serverStorage: SMBServerStorage

    @State private var name = ""
    @State private var hostname = ""
    @State private var share = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Server") {
                    TextField("Naam (bijv. NAS)", text: $name)
                    TextField("Hostnaam of IP", text: $hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Share naam", text: $share)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Inloggegevens (optioneel)") {
                    TextField("Gebruikersnaam", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Wachtwoord", text: $password)
                }

                Section {
                    Text("Voorbeeld URL: smb://\(hostname.isEmpty ? "server" : hostname)/\(share.isEmpty ? "share" : share)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Server toevoegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Voeg toe") {
                        addServer()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !name.isEmpty && !hostname.isEmpty && !share.isEmpty
    }

    private func addServer() {
        let server = SMBServer(
            name: name,
            hostname: hostname,
            share: share,
            username: username,
            password: password
        )
        serverStorage.addServer(server)
        dismiss()
    }
}

// MARK: - Share Picker View

struct SharePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let discoveredServer: DiscoveredServer
    @ObservedObject var serverStorage: SMBServerStorage
    let onDismiss: () -> Void

    @StateObject private var shareBrowser = ShareBrowserViewModel()
    @State private var username = ""
    @State private var password = ""
    @State private var showCredentials = true
    @State private var selectedShare: String?

    var body: some View {
        NavigationView {
            Group {
                if showCredentials {
                    credentialsView
                } else {
                    shareListView
                }
            }
            .navigationTitle(showCredentials ? "Inloggen" : "Kies een share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") {
                        onDismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if !showCredentials && selectedShare != nil {
                        Button("Voeg toe") {
                            addServer()
                        }
                    }
                }
            }
        }
    }

    private var credentialsView: some View {
        Form {
            Section {
                HStack {
                    Text("Server")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(discoveredServer.name)
                }
                HStack {
                    Text("Adres")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(discoveredServer.hostname)
                }
            }

            Section("Inloggegevens (optioneel)") {
                TextField("Gebruikersnaam", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Wachtwoord", text: $password)
            }

            Section {
                Button(action: browseShares) {
                    HStack {
                        Text("Zoek shares")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                    }
                }
            }
        }
    }

    private var shareListView: some View {
        Group {
            if shareBrowser.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Shares laden...")
                        .scaleEffect(1.5)
                    Spacer()
                }
            } else if let error = shareBrowser.error {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Fout")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Terug naar inloggen") {
                        showCredentials = true
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            } else if shareBrowser.shares.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("Geen shares gevonden")
                        .font(.headline)
                    Button("Terug naar inloggen") {
                        showCredentials = true
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            } else {
                List(shareBrowser.shares, id: \.self, selection: $selectedShare) { share in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        Text(share)
                            .font(.headline)
                        Spacer()
                        if selectedShare == share {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedShare = share
                    }
                }
            }
        }
    }

    private func browseShares() {
        showCredentials = false
        shareBrowser.browseShares(
            hostname: discoveredServer.hostname,
            username: username,
            password: password
        )
    }

    private func addServer() {
        guard let share = selectedShare else { return }

        let server = SMBServer(
            name: "\(discoveredServer.name) - \(share)",
            hostname: discoveredServer.hostname,
            share: share,
            username: username,
            password: password
        )
        serverStorage.addServer(server)
        onDismiss()
    }
}

// MARK: - Share Browser ViewModel

@MainActor
class ShareBrowserViewModel: ObservableObject {
    @Published var shares: [String] = []
    @Published var isLoading = false
    @Published var error: String?

    private var currentMedia: VLCMedia?

    func browseShares(hostname: String, username: String, password: String) {
        isLoading = true
        error = nil
        shares = []

        // Build SMB URL for the server root
        var urlString = "smb://"
        if !username.isEmpty {
            let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            urlString += encodedUsername
            if !password.isEmpty {
                let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
                urlString += ":\(encodedPassword)"
            }
            urlString += "@"
        }
        urlString += hostname

        guard let url = URL(string: urlString) else {
            error = "Ongeldige server URL"
            isLoading = false
            return
        }

        let media = VLCMedia(url: url)
        currentMedia = media

        // Parse the server to get shares
        let options = VLCMediaParsingOptions.parseNetwork.rawValue | VLCMediaParsingOptions.fetchNetwork.rawValue
        _ = media.parse(options: VLCMediaParsingOptions(rawValue: options), timeout: 15000)

        // Wait for parsing to complete
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self.processShares()
            }
        }
    }

    private func processShares() {
        guard let media = currentMedia else {
            isLoading = false
            return
        }

        var foundShares: [String] = []

        if let subitems = media.subitems {
            subitems.lock()
            let count = subitems.count
            for i in 0..<count {
                if let item = subitems.media(at: UInt(i)),
                   let url = item.url {
                    let name = url.lastPathComponent
                    // Filter out hidden shares (ending with $) and special shares
                    if !name.hasPrefix(".") && !name.hasSuffix("$") && !name.isEmpty {
                        foundShares.append(name)
                    }
                }
            }
            subitems.unlock()
        }

        foundShares.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        shares = foundShares
        isLoading = false

        if shares.isEmpty {
            if media.parsedStatus == .failed {
                error = "Kan niet verbinden. Controleer de inloggegevens."
            }
        }
    }
}

// MARK: - Fullscreen Image Viewer

struct FullscreenImageViewer: View {
    let images: [SMBItem]
    @Binding var currentIndex: Int
    let onClose: () -> Void

    @State private var loadedImages: [Int: UIImage] = [:]
    @State private var isLoading = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Zwarte achtergrond
                Color.black
                    .ignoresSafeArea()

                if images.isEmpty {
                    Text("Geen afbeeldingen")
                        .foregroundColor(.white)
                } else {
                    // Image carousel
                    TabView(selection: $currentIndex) {
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                            ZStack {
                                if let image = loadedImages[index] {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    ProgressView()
                                        .scaleEffect(2)
                                        .tint(.white)
                                        .onAppear {
                                            loadImage(at: index)
                                        }
                                }
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }

                // Controls overlay
                VStack {
                    // Top bar
                    HStack {
                        // Bestandsnaam en teller
                        VStack(alignment: .leading, spacing: 4) {
                            if !images.isEmpty {
                                Text(images[currentIndex].name)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("\(currentIndex + 1) / \(images.count)")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.leading, 20)

                        Spacer()

                        // Sluit knop
                        Button(action: onClose) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 60, height: 60)
                                Image(systemName: "xmark")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .shadow(radius: 8)
                        }
                        .padding(20)
                    }
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.6), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )

                    Spacer()

                    // Bottom hint
                    if images.count > 1 {
                        Text("Swipe om te bladeren")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.bottom, 30)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onChange(of: currentIndex) { newIndex in
            // Preload adjacent images
            loadImage(at: newIndex - 1)
            loadImage(at: newIndex + 1)
        }
        .onAppear {
            // Load current and adjacent images
            loadImage(at: currentIndex)
            loadImage(at: currentIndex - 1)
            loadImage(at: currentIndex + 1)
        }
    }

    private func loadImage(at index: Int) {
        guard index >= 0 && index < images.count else { return }
        guard loadedImages[index] == nil else { return }

        let item = images[index]

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: item.url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        loadedImages[index] = image
                    }
                }
            } catch {
                print("Failed to load image: \(error)")
            }
        }
    }
}

#Preview {
    SMBBrowserView(
        onSelectMedia: { _ in },
        onDismiss: { }
    )
}
