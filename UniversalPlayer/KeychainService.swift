import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()

    private let serviceIdentifier = "com.universalplayer.smb"

    private init() {}

    // MARK: - Save Credentials

    func saveCredentials(for server: String, username: String, password: String) {
        let account = "\(server)"
        let credentials = "\(username):\(password)"

        guard let data = credentials.data(using: .utf8) else { return }

        // Delete existing item first
        deleteCredentials(for: server)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain save error: \(status)")
        }
    }

    // MARK: - Load Credentials

    func loadCredentials(for server: String) -> (username: String, password: String)? {
        let account = "\(server)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let credentials = String(data: data, encoding: .utf8) else {
            return nil
        }

        let parts = credentials.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        } else if parts.count == 1 {
            return (String(parts[0]), "")
        }

        return nil
    }

    // MARK: - Delete Credentials

    func deleteCredentials(for server: String) {
        let account = "\(server)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Check if credentials exist

    func hasCredentials(for server: String) -> Bool {
        return loadCredentials(for: server) != nil
    }
}
