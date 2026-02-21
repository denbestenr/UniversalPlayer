import SwiftUI
import AuthenticationServices
import UIKit

struct YouTubeSettingsView: View {
    @ObservedObject var youtubeService = YouTubeService.shared
    @State private var authError: String?
    @State private var isAuthenticating = false

    var body: some View {
        Form {
            Section(header: Text("Account").font(.title3)) {
                if youtubeService.isAuthenticated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text("Ingelogd")
                            .font(.title2)
                        if let channelName = youtubeService.channelName {
                            Text("(\(channelName))")
                                .foregroundColor(.secondary)
                                .font(.title3)
                        }
                    }

                    Button("Uitloggen", role: .destructive) {
                        youtubeService.logout()
                    }
                    .font(.title3)
                } else {
                    Button(action: startAuthentication) {
                        HStack {
                            if isAuthenticating {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Inloggen bij YouTube")
                        }
                    }
                    .disabled(isAuthenticating)
                    .font(.title3)
                }

                if let error = authError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.body)
                }
            }
        }
        .navigationTitle("YouTube")
    }

    private func startAuthentication() {
        guard let authURL = youtubeService.getAuthURL() else {
            authError = "Kon authenticatie URL niet maken"
            return
        }

        isAuthenticating = true
        authError = nil

        // Get the callback URL scheme from the client ID
        let callbackScheme = youtubeService.getCallbackScheme()

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { callbackURL, error in
            isAuthenticating = false

            if let error = error as? ASWebAuthenticationSessionError,
               error.code == .canceledLogin {
                // User cancelled, no error to show
                return
            }

            if let error = error {
                authError = "Authenticatie mislukt: \(error.localizedDescription)"
                return
            }

            guard let callbackURL = callbackURL else {
                authError = "Geen callback URL ontvangen"
                return
            }

            Task {
                do {
                    try await youtubeService.handleAuthCallback(url: callbackURL)
                } catch {
                    await MainActor.run {
                        authError = error.localizedDescription
                    }
                }
            }
        }

        session.presentationContextProvider = AuthPresentationContext.shared
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }
}

// MARK: - Presentation Context

class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

#Preview {
    NavigationView {
        YouTubeSettingsView()
    }
}
