import Foundation
import AuthenticationServices

class YouTubeService: NSObject, ObservableObject {
    static let shared = YouTubeService()

    @Published var isAuthenticated = false
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var uploadError: String?
    @Published var channelName: String?

    private let keychainService = "com.universalplayer.youtube"
    private var accessToken: String?
    private var refreshToken: String?

    // YouTube API endpoints
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let uploadURL = "https://www.googleapis.com/upload/youtube/v3/videos"
    private let channelURL = "https://www.googleapis.com/youtube/v3/channels"

    // Hardcoded client ID for YouTube API
    let clientId = "890743800150-mm6bsb57ug4577e9e5mjb2e29j0f3qt8.apps.googleusercontent.com"
    let clientSecret = ""

    // Redirect URI is the reversed client ID
    private var redirectURI: String {
        // Convert client ID like "123456789-abc.apps.googleusercontent.com"
        // to "com.googleusercontent.apps.123456789-abc:/oauthredirect"
        let parts = clientId.components(separatedBy: ".apps.googleusercontent.com")
        if let clientPart = parts.first, !clientPart.isEmpty {
            return "com.googleusercontent.apps.\(clientPart):/oauthredirect"
        }
        return "com.universalplayer:/oauth2callback"
    }
    private let scope = "https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly"

    override init() {
        super.init()
        loadTokens()
    }

    // MARK: - Token Management

    private func loadTokens() {
        if let data = KeychainService.shared.loadCredentials(for: "youtube_tokens") {
            accessToken = data.username
            refreshToken = data.password
            isAuthenticated = !accessToken!.isEmpty
            if isAuthenticated {
                fetchChannelInfo()
            }
        }
    }

    private func saveTokens() {
        if let access = accessToken, let refresh = refreshToken {
            KeychainService.shared.saveCredentials(for: "youtube_tokens", username: access, password: refresh)
        }
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        channelName = nil
        isAuthenticated = false
        KeychainService.shared.deleteCredentials(for: "youtube_tokens")
    }

    // MARK: - Authentication

    func getAuthURL() -> URL? {
        guard !clientId.isEmpty else { return nil }

        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url
    }

    func getCallbackScheme() -> String {
        // Extract the callback scheme from the redirect URI
        // e.g., "com.googleusercontent.apps.123456789-abc:/oauthredirect" -> "com.googleusercontent.apps.123456789-abc"
        let parts = clientId.components(separatedBy: ".apps.googleusercontent.com")
        if let clientPart = parts.first, !clientPart.isEmpty {
            return "com.googleusercontent.apps.\(clientPart)"
        }
        return "com.universalplayer"
    }

    func handleAuthCallback(url: URL) async throws {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw YouTubeError.authFailed("No authorization code received")
        }

        try await exchangeCodeForTokens(code: code)
    }

    private func exchangeCodeForTokens(code: String) async throws {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        // Client secret is optional for iOS apps
        if !clientSecret.isEmpty {
            body["client_secret"] = clientSecret
        }
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw YouTubeError.authFailed("Token exchange failed")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        await MainActor.run {
            self.accessToken = tokenResponse.access_token
            self.refreshToken = tokenResponse.refresh_token ?? self.refreshToken
            self.isAuthenticated = true
            self.saveTokens()
            self.fetchChannelInfo()
        }
    }

    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else {
            throw YouTubeError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = [
            "client_id": clientId,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ]
        // Client secret is optional for iOS apps
        if !clientSecret.isEmpty {
            body["client_secret"] = clientSecret
        }
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            await MainActor.run {
                self.logout()
            }
            throw YouTubeError.authFailed("Token refresh failed")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        await MainActor.run {
            self.accessToken = tokenResponse.access_token
            self.saveTokens()
        }
    }

    // MARK: - Channel Info

    private func fetchChannelInfo() {
        guard let token = accessToken else { return }

        Task {
            var components = URLComponents(string: channelURL)!
            components.queryItems = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "mine", value: "true")
            ]

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(ChannelListResponse.self, from: data)
                await MainActor.run {
                    self.channelName = response.items?.first?.snippet?.title
                }
            } catch {
                print("Failed to fetch channel info: \(error)")
            }
        }
    }

    // MARK: - Upload

    func uploadVideo(url: URL, title: String, description: String = "", privacy: String = "private") async throws -> String {
        guard isAuthenticated, let token = accessToken else {
            throw YouTubeError.notAuthenticated
        }

        await MainActor.run {
            self.isUploading = true
            self.uploadProgress = 0
            self.uploadError = nil
        }

        do {
            // Read video data - handle both local and network files
            let videoData: Data

            if url.scheme == "smb" {
                // SMB files need to be downloaded first using VLC
                throw YouTubeError.smbNotSupported
            } else if url.isFileURL {
                // For local files, read directly
                // Start security-scoped access if needed
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                videoData = try Data(contentsOf: url)
            } else {
                // Try to read directly for other URLs
                videoData = try Data(contentsOf: url)
            }

            // Create upload metadata
            let metadata: [String: Any] = [
                "snippet": [
                    "title": title,
                    "description": description,
                    "categoryId": "22" // People & Blogs
                ],
                "status": [
                    "privacyStatus": privacy,
                    "selfDeclaredMadeForKids": true
                ]
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadata)

            // Create multipart request
            let boundary = UUID().uuidString
            var body = Data()

            // Metadata part
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
            body.append(metadataData)
            body.append("\r\n".data(using: .utf8)!)

            // Video part
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Type: video/*\r\n\r\n".data(using: .utf8)!)
            body.append(videoData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)

            // Create request
            var components = URLComponents(string: uploadURL)!
            components.queryItems = [
                URLQueryItem(name: "uploadType", value: "multipart"),
                URLQueryItem(name: "part", value: "snippet,status")
            ]

            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")

            // Upload with progress tracking
            let (responseData, response) = try await uploadWithProgress(request: request, data: body)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw YouTubeError.uploadFailed("Invalid response")
            }

            if httpResponse.statusCode == 401 {
                // Token expired, refresh and retry
                try await refreshAccessToken()
                return try await uploadVideo(url: url, title: title, description: description, privacy: privacy)
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
                throw YouTubeError.uploadFailed("Upload failed: \(errorMessage)")
            }

            let uploadResponse = try JSONDecoder().decode(VideoUploadResponse.self, from: responseData)

            await MainActor.run {
                self.isUploading = false
                self.uploadProgress = 1.0
            }

            return uploadResponse.id

        } catch {
            await MainActor.run {
                self.isUploading = false
                self.uploadError = error.localizedDescription
            }
            throw error
        }
    }

    private func uploadWithProgress(request: URLRequest, data: Data) async throws -> (Data, URLResponse) {
        let delegate = UploadProgressDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (responseData, response) = try await session.upload(for: request, from: data, delegate: delegate)

        await MainActor.run {
            self.uploadProgress = 1.0
        }

        return (responseData, response)
    }

    // MARK: - Video Status

    private let videosURL = "https://www.googleapis.com/youtube/v3/videos"

    func getVideoStatus(videoId: String) async throws -> YouTubeProcessingStatus {
        guard let token = accessToken else {
            throw YouTubeError.notAuthenticated
        }

        var components = URLComponents(string: videosURL)!
        components.queryItems = [
            URLQueryItem(name: "part", value: "status,processingDetails"),
            URLQueryItem(name: "id", value: videoId)
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw YouTubeError.uploadFailed("Could not get video status")
        }

        let videoResponse = try JSONDecoder().decode(VideoListResponse.self, from: data)

        guard let video = videoResponse.items?.first else {
            return YouTubeProcessingStatus.failed
        }

        // Check processing status
        if let processingStatus = video.processingDetails?.processingStatus {
            switch processingStatus {
            case "processing":
                return YouTubeProcessingStatus.processing
            case "succeeded":
                return YouTubeProcessingStatus.processed
            case "failed", "terminated":
                return YouTubeProcessingStatus.failed
            default:
                return YouTubeProcessingStatus.processing
            }
        }

        // If no processing details, check upload status
        if video.status?.uploadStatus == "processed" {
            return YouTubeProcessingStatus.processed
        }

        return YouTubeProcessingStatus.processing
    }
}

// MARK: - Response Models

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
    let token_type: String
}

struct ChannelListResponse: Codable {
    let items: [ChannelItem]?
}

struct ChannelItem: Codable {
    let snippet: ChannelSnippet?
}

struct ChannelSnippet: Codable {
    let title: String?
}

struct VideoUploadResponse: Codable {
    let id: String
    let snippet: VideoSnippet?
}

struct VideoSnippet: Codable {
    let title: String?
}

struct VideoListResponse: Codable {
    let items: [VideoItem]?
}

struct VideoItem: Codable {
    let id: String
    let status: VideoStatus?
    let processingDetails: ProcessingDetails?
}

struct VideoStatus: Codable {
    let uploadStatus: String?
    let privacyStatus: String?
}

struct ProcessingDetails: Codable {
    let processingStatus: String?
}

enum YouTubeProcessingStatus: String {
    case processing
    case processed
    case failed
}

// MARK: - Upload Progress Delegate

class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    override init() {
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        Task { @MainActor in
            let manager = BackgroundUploadManager.shared
            manager.uploadTotalBytes = totalBytesExpectedToSend
            manager.uploadedBytes = totalBytesSent
            if totalBytesExpectedToSend > 0 {
                // Upload progress maps to 50-100% of overall
                let uploadFraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
                manager.overallProgress = 0.5 + (uploadFraction * 0.5)
            }
        }
    }
}

// MARK: - Errors

enum YouTubeError: LocalizedError {
    case notAuthenticated
    case authFailed(String)
    case uploadFailed(String)
    case notConfigured
    case smbNotSupported

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Niet ingelogd bij YouTube"
        case .authFailed(let message):
            return "Authenticatie mislukt: \(message)"
        case .uploadFailed(let message):
            return "Upload mislukt: \(message)"
        case .notConfigured:
            return "YouTube API niet geconfigureerd"
        case .smbNotSupported:
            return "Netwerkbestanden kunnen niet direct worden geüpload. Gebruik 'Bewaar lokaal' om het bestand eerst op te slaan."
        }
    }
}
