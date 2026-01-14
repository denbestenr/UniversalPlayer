import SwiftUI

struct SMBBrowserView: View {
    @StateObject private var serverStorage = SMBServerStorage()
    @StateObject private var browserViewModel = SMBBrowserViewModel()
    @State private var showAddServer = false
    @State private var selectedServer: SMBServer?
    @State private var isConnected = false

    let onSelectMedia: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
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
        }
    }

    // MARK: - Server List View

    private var serverListView: some View {
        Group {
            if serverStorage.servers.isEmpty {
                emptyServerView
            } else {
                List {
                    ForEach(serverStorage.servers) { server in
                        ServerRowView(server: server) {
                            connect(to: server)
                        }
                    }
                    .onDelete(perform: deleteServers)
                }
            }
        }
    }

    private var emptyServerView: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Geen servers")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Voeg een SMB/CIFS netwerkserver toe om bestanden te browsen")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: { showAddServer = true }) {
                Label("Server toevoegen", systemImage: "plus")
                    .font(.headline)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
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
        }
    }

    private func navigateToPathIndex(_ index: Int) {
        guard let server = selectedServer else { return }
        let path = browserViewModel.pathComponents.prefix(index + 1).joined(separator: "/")
        browserViewModel.browse(server: server, path: path)
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
        NavigationStack {
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

#Preview {
    SMBBrowserView(
        onSelectMedia: { _ in },
        onDismiss: { }
    )
}
