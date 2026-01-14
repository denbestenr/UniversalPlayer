import Foundation

struct SMBServer: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var hostname: String
    var share: String
    var username: String
    var password: String

    init(id: UUID = UUID(), name: String, hostname: String, share: String, username: String = "", password: String = "") {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.share = share
        self.username = username
        self.password = password
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
           let decoded = try? JSONDecoder().decode([SMBServer].self, from: data) {
            servers = decoded
        }
    }

    func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    func addServer(_ server: SMBServer) {
        servers.append(server)
        saveServers()
    }

    func removeServer(_ server: SMBServer) {
        servers.removeAll { $0.id == server.id }
        saveServers()
    }

    func updateServer(_ server: SMBServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }
}
