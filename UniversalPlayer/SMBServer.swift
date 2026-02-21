import Foundation

struct SMBServer: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var hostname: String
    var share: String

    // Credentials are stored in Keychain, not in UserDefaults
    // These are transient properties populated at runtime
    var username: String = ""
    var password: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, hostname, share
        // username and password excluded from Codable
    }

    init(id: UUID = UUID(), name: String, hostname: String, share: String, username: String = "", password: String = "") {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.share = share
        self.username = username
        self.password = password
    }

    // Unique key for keychain storage
    var keychainKey: String {
        "\(hostname)/\(share)"
    }

    // Load credentials from keychain
    mutating func loadCredentials() {
        if let creds = KeychainService.shared.loadCredentials(for: keychainKey) {
            self.username = creds.username
            self.password = creds.password
        }
    }

    // Save credentials to keychain
    func saveCredentials() {
        if !username.isEmpty || !password.isEmpty {
            KeychainService.shared.saveCredentials(for: keychainKey, username: username, password: password)
        }
    }

    // Delete credentials from keychain
    func deleteCredentials() {
        KeychainService.shared.deleteCredentials(for: keychainKey)
    }

    var baseURL: URL? {
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
        if !share.isEmpty {
            urlString += "/\(share)"
        }
        return URL(string: urlString)
    }

    func urlForPath(_ path: String) -> URL? {
        guard let base = baseURL else { return nil }
        if path.isEmpty {
            return base
        }
        return base.appendingPathComponent(path)
    }
}

class SMBServerStorage: ObservableObject {
    @Published var servers: [SMBServer] = []

    private let storageKey = "savedSMBServers"

    init() {
        loadServers()
    }

    func loadServers() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           var decoded = try? JSONDecoder().decode([SMBServer].self, from: data) {
            // Load credentials from keychain for each server
            for i in decoded.indices {
                decoded[i].loadCredentials()
            }
            servers = decoded
        }
    }

    func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    func addServer(_ server: SMBServer) {
        // Save credentials to keychain
        server.saveCredentials()
        servers.append(server)
        saveServers()
    }

    func removeServer(_ server: SMBServer) {
        // Remove credentials from keychain
        server.deleteCredentials()
        servers.removeAll { $0.id == server.id }
        saveServers()
    }

    func updateServer(_ server: SMBServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            // Update credentials in keychain
            server.saveCredentials()
            servers[index] = server
            saveServers()
        }
    }
}
